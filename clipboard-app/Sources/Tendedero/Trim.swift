import AppKit
import AVKit
import Combine
import CryptoKit
import Darwin

/// Bounded, cancellable I/O for private recording snapshots. No source file is
/// opened for writing, and a changed inode/size/date invalidates a read.
enum RecordingTrimFiles {
    static let maximumBytes: Int64 = 2 * 1024 * 1024 * 1024
    static func fingerprint(_ url: URL) throws -> String { try read(url) }
    static func snapshot(_ source: URL, to destination: URL) throws -> String {
        try read(source, copyingTo: destination)
    }
    private static func identity(_ descriptor: Int32) throws -> String {
        var value = stat()
        guard fstat(descriptor, &value) == 0, value.st_mode & S_IFMT == S_IFREG,
              value.st_size > 0, value.st_size <= maximumBytes else { throw HistoryFiles.Failure.unsafeFile }
        return "\(value.st_dev):\(value.st_ino):\(value.st_size):\(value.st_mtimespec.tv_sec):\(value.st_mtimespec.tv_nsec):\(value.st_ctimespec.tv_sec):\(value.st_ctimespec.tv_nsec)"
    }
    private static func read(_ source: URL, copyingTo destination: URL? = nil, makePrivate: Bool = false) throws -> String {
        try Task.checkCancellation()
        let descriptor = source.withUnsafeFileSystemRepresentation { $0.map { open($0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) } ?? -1 }
        guard descriptor >= 0 else { throw HistoryFiles.Failure.unsafeFile }
        let input = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? input.close() }
        let before = try identity(descriptor)
        var output: FileHandle?
        if let destination {
            guard destination.deletingLastPathComponent().resolvingSymlinksInPath().path == destination.deletingLastPathComponent().standardizedFileURL.path else { throw HistoryFiles.Failure.unsafeFile }
            let fd = destination.withUnsafeFileSystemRepresentation { $0.map { open($0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600) } ?? -1 }
            guard fd >= 0 else { throw HistoryFiles.Failure.unsafeFile }
            output = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        }
        defer { try? output?.close() }
        var digest = SHA256(), count: Int64 = 0
        while true {
            try Task.checkCancellation()
            let bytes = try input.read(upToCount: 1024 * 1024) ?? Data()
            if bytes.isEmpty { break }
            count += Int64(bytes.count)
            guard count <= maximumBytes else { throw HistoryFiles.Failure.unsafeFile }
            digest.update(data: bytes); try output?.write(contentsOf: bytes)
        }
        guard before == (try identity(descriptor)) else { throw HistoryFiles.Failure.unsafeFile }
        if makePrivate { guard fchmod(descriptor, 0o600) == 0 else { throw HistoryFiles.Failure.unsafeFile }; try input.synchronize() }
        try output?.synchronize(); try Task.checkCancellation()
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func validateExport(_ url: URL) async throws {
        _ = try read(url, makePrivate: true)
        let asset = AVURLAsset(url: url)
        try await withTaskCancellationHandler(operation: {
            let duration = try await asset.load(.duration)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard duration.seconds.isFinite, duration.seconds > 0, !tracks.isEmpty,
                  try await asset.load(.isPlayable) else { throw HistoryFiles.Failure.unsafeFile }
            try Task.checkCancellation()
        }, onCancel: { asset.cancelLoading() })
    }
}

/// Native AVKit trimming UI with immutable originals and an atomic Library
/// derivative commit. Closing or opening another editor cancels unpublished work.
@MainActor final class Trim: NSObject, NSWindowDelegate {
    static let shared = Trim()
    var onSaved: (UUID, URL) -> Void = { _, _ in }
    private final class Session {
        let id: UUID
        let store: LibraryStore
        var context: LibraryStore.RecordingTrimContext?
        var window: NSWindow?
        var ready: AnyCancellable?
        var task: Task<Void, Never>?
        var export: AVAssetExportSession?
        var saving = false
        var cancelled = false
        init(id: UUID, store: LibraryStore) { self.id = id; self.store = store }
    }
    private var current: Session?

    func edit(_ id: UUID, store: LibraryStore, size: CGSize) {
        cancelCurrent()
        let session = Session(id: id, store: store); current = session
        session.task = Task { [weak self, weak session] in
            guard let self, let session else { return }
            do {
                let context = try await store.prepareRecordingTrim(id)
                guard self.current === session, !session.cancelled, !Task.isCancelled else { store.discardRecordingTrim(context); return }
                session.context = context; session.task = nil
                self.show(session, context: context, size: size)
            } catch {
                if !Task.isCancelled && !session.cancelled { log.error("Could not prepare recording trim: \(error.localizedDescription, privacy: .private)"); NSSound.beep() }
                self.finish(session)
            }
        }
    }
    private func show(_ session: Session, context: LibraryStore.RecordingTrimContext, size: CGSize) {
        let item = AVPlayerItem(url: context.snapshot), playerView = AVPlayerView()
        playerView.player = AVPlayer(playerItem: item); playerView.controlsStyle = .inline
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.windowSize(for: size)), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = (try? session.store.item(session.id))?.displayTitle ?? context.source.lastPathComponent
        window.contentView = playerView; window.isReleasedWhenClosed = false; window.delegate = self
        window.center(); session.window = window
        NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
        session.ready = item.publisher(for: \.status).first { $0 != .unknown }.receive(on: RunLoop.main).sink { [weak self, weak session, weak playerView] status in
            guard let self, let session, self.current === session, !session.cancelled else { return }
            guard let playerView, status == .readyToPlay, playerView.canBeginTrimming else { NSSound.beep(); self.finish(session); return }
            playerView.beginTrimming { [weak self, weak session] result in
                DispatchQueue.main.async {
                    guard let self, let session, self.current === session, !session.cancelled else { return }
                    if result == .okButton { self.save(item, session: session) } else { self.finish(session) }
                }
            }
        }
    }
    private static func windowSize(for size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return CGSize(width: 720, height: 450) }
        let scale = min(720 / size.width, 520 / size.height)
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }
    func windowWillClose(_ notification: Notification) {
        guard let session = current, (notification.object as? NSWindow) === session.window else { return }
        cancelCurrent()
    }
    private func finish(_ session: Session) {
        guard current === session else { return }
        current = nil; session.ready = nil
        (session.window?.contentView as? AVPlayerView)?.player?.pause()
        session.window?.delegate = nil; session.window?.close(); session.window = nil
        if !session.saving, let context = session.context { session.store.discardRecordingTrim(context) }
    }
    private func cancelCurrent() {
        guard let session = current else { return }
        session.cancelled = true; session.export?.cancelExport(); session.task?.cancel()
        finish(session)
    }
    private func save(_ item: AVPlayerItem, session: Session) {
        guard !session.saving, let context = session.context,
              let export = AVAssetExportSession(asset: item.asset, presetName: AVAssetExportPresetPassthrough) else { NSSound.beep(); return }
        let start = item.reversePlaybackEndTime.isValid ? item.reversePlaybackEndTime : .zero
        let end = item.forwardPlaybackEndTime.isValid ? item.forwardPlaybackEndTime : item.duration
        guard start.seconds.isFinite, end.seconds.isFinite, start.seconds >= 0, end.seconds > start.seconds else { NSSound.beep(); return }
        session.saving = true; session.export = export
        export.outputURL = context.output
        export.outputFileType = context.output.pathExtension.lowercased() == "mp4" ? .mp4 : .mov
        export.timeRange = CMTimeRange(start: start, end: end)
        session.task = Task { [weak self, session] in
            defer { session.store.discardRecordingTrim(context); session.export = nil; session.task = nil; session.saving = false }
            do {
                await withTaskCancellationHandler(operation: { await export.export() }, onCancel: { export.cancelExport() })
                try Task.checkCancellation()
                guard !session.cancelled, self?.current === session, export.status == .completed else { throw export.error ?? HistoryFiles.Failure.unsafeFile }
                let value = try await session.store.commitRecordingTrim(context)
                guard !session.cancelled, self?.current === session, let url = value.fileURL else { return }
                self?.onSaved(value.id, url); self?.finish(session)
            } catch {
                if !Task.isCancelled && !session.cancelled { log.error("Could not save recording trim: \(error.localizedDescription, privacy: .private)"); NSSound.beep() }
                self?.finish(session)
            }
        }
    }
}
