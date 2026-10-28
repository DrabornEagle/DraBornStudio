import AppKit

/// Only two decodes can run at once. A fling replaces the pending work with
/// its latest visible range, rather than queuing every card it passed.
@MainActor
final class ThumbnailStore {
    struct Key: Hashable {
        let url: URL
        let pixels: Int
        let generation: Int
    }
    private var cache = [Key: (image: NSImage, cost: Int)]()
    private var recency = [Key]()
    private(set) var cachedBytes = 0
    var cachedCount: Int { cache.count }
    static let maximumBytes = 32 * 1024 * 1024
    static let maximumCount = 64
    private var wanted: [Key] = []
    private var inFlight = Set<Key>()
    private var failed = Set<Key>()
    private var delivered = Set<Key>()
    private var generation = 0
    var onLoad: (() -> Void)?
    private(set) var decodeCount = 0
    private(set) var peakConcurrentDecodes = 0
    private(set) var decodedOnMainThread = false
    var pendingCount: Int { inFlight.count }

    struct Stats { let decodes: Int; let concurrent: Int; let onMain: Bool; let cachedCount: Int; let cachedBytes: Int; let pending: Int }
    var stats: Stats { Stats(decodes: decodeCount, concurrent: peakConcurrentDecodes, onMain: decodedOnMainThread, cachedCount: cachedCount, cachedBytes: cachedBytes, pending: pendingCount) }
    private func key(_ url: URL, _ pixels: Int) -> Key { Key(url: url.standardizedFileURL, pixels: pixels, generation: generation) }
    func image(for url: URL, pixels: Int) -> NSImage? {
        let key = key(url, pixels)
        guard let value = cache[key] else { return nil }
        recency.removeAll { $0 == key }; recency.append(key); return value.image
    }
    func seed(_ image: NSImage, url: URL, pixels: Int) {
        insert(image, key: key(url, pixels), cost: Int(image.size.width * image.size.height * 4))
    }
    private func insert(_ image: NSImage, key: Key, cost: Int) {
        guard cost <= Self.maximumBytes else { return }
        if let old = cache.removeValue(forKey: key) { cachedBytes -= old.cost }; recency.removeAll { $0 == key }
        while cache.count >= Self.maximumCount || cachedBytes + cost > Self.maximumBytes {
            guard !recency.isEmpty else { break }; let oldest = recency.removeFirst()
            if let old = cache.removeValue(forKey: oldest) { cachedBytes -= old.cost }
        }
        cache[key] = (image, cost); recency.append(key); cachedBytes += cost
    }
    func invalidate() { generation += 1; cache.removeAll(); recency.removeAll(); cachedBytes = 0; failed.removeAll(); delivered.removeAll(); wanted.removeAll() }
    func request(_ urls: [URL], pixels: Int) {
        // An oversized visible/prefetched set must not endlessly decode the
        // entries evicted by its own cache budget. Prefer viewport order.
        let capacity = min(Self.maximumCount, max(1, Self.maximumBytes / (max(1, pixels) * max(1, pixels) * 4)))
        var seen = Set<Key>()
        wanted = Array(urls.map { key($0, pixels) }.filter { seen.insert($0).inserted }.prefix(capacity))
        failed.formIntersection(Set(wanted))
        delivered.formIntersection(Set(wanted))
        schedule()
    }
    private func schedule() {
        for key in wanted {
            guard inFlight.count < 2 else { break }
            guard !inFlight.contains(key), !failed.contains(key), !delivered.contains(key), cache[key] == nil else { continue }
            inFlight.insert(key); decodeCount += 1
            peakConcurrentDecodes = max(peakConcurrentDecodes, inFlight.count)
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let onMain = Thread.isMainThread
                let cg = decodeThumbnail(key.url, maxPixels: key.pixels)
                DispatchQueue.main.async { self?.complete(key, image: cg, onMain: onMain) }
            }
        }
    }
    private func complete(_ key: Key, image: CGImage?, onMain: Bool) {
        inFlight.remove(key); decodedOnMainThread = decodedOnMainThread || onMain
        if key.generation == generation {
            delivered.insert(key)
            if let image {
                let thumbnail = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
                insert(thumbnail, key: key, cost: image.bytesPerRow * image.height)
            } else { failed.insert(key) }
            if wanted.contains(key) { onLoad?() }
        }
        schedule()
    }
}
