import Foundation
import CoreGraphics

struct WindowPlacement: Codable, Equatable {
    let version: Int
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(frame: CGRect) {
        version = 1; x = frame.origin.x; y = frame.origin.y
        width = frame.width; height = frame.height
    }
    var frame: CGRect? {
        guard version == 1, [x, y, width, height].allSatisfy({ $0.isFinite && abs($0) <= 100_000 }), width > 0, height > 0 else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Frames use AppKit's logical screen coordinates, so Retina scaling does
    /// not enlarge the restored window. A removed screen falls back to primary.
    static func constrain(_ frame: CGRect, to screens: [CGRect], minimum: CGSize = CGSize(width: 760, height: 560)) -> CGRect {
        guard let primary = screens.first else { return frame }
        let screen = screens.max { left, right in
            let l = left.intersection(frame), r = right.intersection(frame)
            return (l.isNull ? 0 : l.width * l.height) < (r.isNull ? 0 : r.width * r.height)
        }.flatMap { $0.intersects(frame) ? $0 : nil } ?? primary
        let width = min(screen.width, max(minimum.width, frame.width))
        let height = min(screen.height, max(minimum.height, frame.height))
        return CGRect(x: min(max(frame.minX, screen.minX), screen.maxX - width),
                      y: min(max(frame.minY, screen.minY), screen.maxY - height), width: width, height: height)
    }
}

struct WindowPlacementStore {
    let url: URL
    func load() -> CGRect? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 2048,
              let data = try? Data(contentsOf: url), let placement = try? JSONDecoder().decode(WindowPlacement.self, from: data) else { return nil }
        return placement.frame
    }
    func save(_ frame: CGRect) {
        let placement = WindowPlacement(frame: frame)
        guard placement.frame != nil, let data = try? JSONEncoder().encode(placement) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { /* A window preference must never prevent opening saved work. */ }
    }
}
