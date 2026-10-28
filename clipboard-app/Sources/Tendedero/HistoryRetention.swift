import Foundation

enum HistoryRetention {
    static func key(_ kind: LibraryKind) -> String {
        switch kind { case .image: "historyRetentionDays"; case .text: "textHistoryRetentionDays"; case .link: "linkHistoryRetentionDays" }
    }
    static func days(_ kind: LibraryKind, defaults: UserDefaults) -> Int {
        let specific = defaults.integer(forKey: key(kind))
        if ImageHistory.dayChoices.contains(specific) { return specific }
        let legacy = defaults.integer(forKey: "historyRetentionDays")
        return ImageHistory.dayChoices.contains(legacy) ? legacy : 30
    }
}
