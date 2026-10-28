import Foundation
import Combine

struct ShelfSearchState: Equatable {
    var isActive = false
    var query = ""
    /// Nil leaves the row unfiltered. An empty set is a completed/no-match
    /// filter, or the initial result while its first query is running.
    var matchingIDs: Set<UUID>?
    var searching = false
    var error: String?
}

/// Per-kind execution for Line's shared visible-shelf query. Querying never loads payloads or
/// reads image pixels on the UI thread; OCR is reused from the shared index.
/// Consumers keep their existing order, pinned filter and selection behavior.
@MainActor final class ShelfSearchModel: ObservableObject {
    @Published private(set) var states = [LibraryKind: ShelfSearchState]()
    private let store: LibraryStore
    private let debounce: TimeInterval
    private var generations = [LibraryKind: Int]()
    private var scheduled = [LibraryKind: DispatchWorkItem]()
    private var favoritesOnly = [LibraryKind: Bool]()
    private var subscriptions = Set<AnyCancellable>()

    init(store: LibraryStore, debounce: TimeInterval = 0.18) {
        self.store = store; self.debounce = max(0, debounce)
        store.$revision.dropFirst().sink { [weak self] _ in
            guard let self else { return }
            for kind in LibraryKind.allCases where self.store.changedKinds.contains(kind) && self.state(for: kind).isActive && !self.trimmedQuery(for: kind).isEmpty {
                self.schedule(kind)
            }
        }.store(in: &subscriptions)
        store.$searchRevision.dropFirst().sink { [weak self] _ in
            guard let self, self.state(for: .image).isActive, !self.trimmedQuery(for: .image).isEmpty else { return }
            self.schedule(.image)
        }.store(in: &subscriptions)
    }

    func state(for kind: LibraryKind) -> ShelfSearchState { states[kind] ?? ShelfSearchState() }
    func query(for kind: LibraryKind) -> String { state(for: kind).query }
    func matchingIDs(for kind: LibraryKind) -> Set<UUID>? { state(for: kind).matchingIDs }
    func isActive(for kind: LibraryKind) -> Bool { state(for: kind).isActive }
    func isSearching(for kind: LibraryKind) -> Bool { state(for: kind).searching }
    func error(for kind: LibraryKind) -> String? { state(for: kind).error }

    /// Undo restores membership immediately. Refresh its literal filter in the
    /// same operation so a restored record can be selected before debounce.
    func refreshAfterUndo(_ kind: LibraryKind) {
        guard isActive(for: kind), !trimmedQuery(for: kind).isEmpty else { return }
        invalidate(kind)
        var state = state(for: kind)
        var query = LibraryQuery(scope: .shelf, kind: kind, search: trimmedQuery(for: kind))
        query.searchMode = .text; query.favoritesOnly = favoritesOnly[kind, default: false]
        do { state.matchingIDs = Set(try store.queryIDs(query)); state.error = nil }
        catch { state.matchingIDs = []; state.error = error.localizedDescription }
        state.searching = false; states[kind] = state
    }

    func setActive(_ active: Bool, for kind: LibraryKind) {
        guard active else { close(kind); return }
        guard !isActive(for: kind) else { return }
        var state = state(for: kind); state.isActive = true; states[kind] = state
    }

    func update(_ query: String, for kind: LibraryKind) {
        guard query != self.query(for: kind) || !isActive(for: kind) else { return }
        var state = state(for: kind); state.isActive = true; state.query = query
        // A new phrase must never leave the previous phrase's records
        // actionable while debounce/read work is pending.
        state.matchingIDs = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : []
        state.error = nil; states[kind] = state
        schedule(kind)
    }

    func setFavoritesOnly(_ value: Bool, for kind: LibraryKind) {
        guard favoritesOnly[kind, default: false] != value else { return }
        favoritesOnly[kind] = value
        if isActive(for: kind), !trimmedQuery(for: kind).isEmpty { schedule(kind) }
    }

    /// Clear a row's query while keeping its search field available.
    func clear(_ kind: LibraryKind) {
        invalidate(kind)
        var state = state(for: kind); state.query = ""; state.matchingIDs = nil
        state.searching = false; state.error = nil; states[kind] = state
    }

    func close(_ kind: LibraryKind) {
        invalidate(kind)
        states[kind] = ShelfSearchState()
    }

    /// Closing the line ends all searches. Queued/in-flight completions cannot
    /// repopulate a closed row or carry its filter into the next reveal.
    func close() {
        for kind in LibraryKind.allCases { invalidate(kind) }
        if !states.isEmpty { states.removeAll() }
    }

    private func trimmedQuery(for kind: LibraryKind) -> String {
        query(for: kind).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func invalidate(_ kind: LibraryKind) {
        scheduled.removeValue(forKey: kind)?.cancel()
        generations[kind, default: 0] += 1
    }

    private func schedule(_ kind: LibraryKind) {
        invalidate(kind)
        let query = trimmedQuery(for: kind)
        var state = state(for: kind)
        guard state.isActive, !query.isEmpty else {
            state.matchingIDs = nil; state.searching = false; state.error = nil
            states[kind] = state; return
        }
        if state.matchingIDs == nil { state.matchingIDs = [] }
        state.searching = true; state.error = nil; states[kind] = state
        let generation = generations[kind, default: 0]
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generations[kind] == generation, self.isActive(for: kind) else { return }
            self.scheduled.removeValue(forKey: kind)
            self.store.shelfMatchingIDsAsync(kind: kind, search: query, favoritesOnly: self.favoritesOnly[kind, default: false]) { [weak self] result in
                guard let self, self.generations[kind] == generation, self.isActive(for: kind) else { return }
                var state = self.state(for: kind); state.searching = false
                switch result {
                case let .success(ids): state.matchingIDs = Set(ids); state.error = nil
                case let .failure(error): state.matchingIDs = []; state.error = error.localizedDescription
                }
                self.states[kind] = state
            }
        }
        scheduled[kind] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: work)
    }
}
