import AppKit

/// A file snapshot shared by the persisted index reader and the OCR worker.
/// An empty cached string is a valid result: an image without text does not
/// need another expensive Vision request simply because it was selected.
struct ImageTextSource: Equatable, Sendable {
    let url: URL
    let fingerprint: String
    let cachedText: String?
}

/// Copying image text never loads an image or runs recognition on the UI
/// thread. Only the newest request can replace the clipboard or report a
/// result, and its record/file identity is checked again after recognition.
@MainActor final class ImageTextCopy {
    enum Outcome: Equatable { case copied, noText, unavailable, failed }
    private let store: LibraryStore
    private let writeText: (String) -> Bool
    private let recognize: @Sendable (URL) throws -> String
    private var generation = 0
    private var task: Task<Void, Never>?

    init(store: LibraryStore, writeText: ((String) -> Bool)? = nil,
         recognize: @escaping @Sendable (URL) throws -> String = { try ImageSearchWorker.recognize($0) }) {
        self.store = store
        self.writeText = writeText ?? { ClipboardTransfer.write(ClipboardTransfer.textItems([$0])) }
        self.recognize = recognize
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
    }

    func copy(_ id: UUID, completion: @escaping (Outcome) -> Void) {
        cancel()
        let token = generation
        task = Task { [weak self] in
            guard let self else { return }
            let result: Outcome
            do {
                guard let source = try await store.imageTextSource(id) else {
                    finish(.unavailable, token: token, completion: completion); return
                }
                guard !Task.isCancelled, token == generation else { return }
                let text: String
                if let cached = source.cachedText { text = cached }
                else {
                    let recognize = self.recognize
                    text = try await Task.detached(priority: .userInitiated) {
                        try recognize(source.url)
                    }.value
                }
                guard !Task.isCancelled, token == generation else { return }
                // The image can be edited, moved, retained under a new owned
                // path or deleted while Vision is reading it. Never copy the
                // old pixels' text into the new record's clipboard action.
                guard let current = try await store.imageTextSource(id),
                      current.url == source.url, current.fingerprint == source.fingerprint,
                      let record = try store.item(id), record.kind == .image,
                      record.deletedAt == nil, record.fileURL == source.url else {
                    finish(.unavailable, token: token, completion: completion); return
                }
                guard !Task.isCancelled, token == generation else { return }
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result = .noText }
                else { result = writeText(text) ? .copied : .failed }
            } catch { result = .failed }
            finish(result, token: token, completion: completion)
        }
    }

    private func finish(_ result: Outcome, token: Int, completion: (Outcome) -> Void) {
        guard token == generation, !Task.isCancelled else { return }
        task = nil
        completion(result)
    }
}
