import AppKit

enum LanguagePreferences {
    static let key = "AppLanguageOverride"
    static var relaunching = false
    static var available: [String] { Array(Set(Bundle.main.localizations)).filter { $0 != "Base" }.sorted { name($0).localizedCompare(name($1)) == .orderedAscending } }
    static func name(_ code: String) -> String { Locale(identifier: code).localizedString(forLanguageCode: code)?.capitalized ?? code }
    static func selection(_ defaults: UserDefaults = .standard) -> String { defaults.string(forKey: key) ?? "" }
    @discardableResult static func set(_ code: String, defaults: UserDefaults = .standard, languages: [String] = available) -> Bool {
        guard code.isEmpty || languages.contains(code) else { return false }
        if code.isEmpty { defaults.removeObject(forKey: key); defaults.removeObject(forKey: "AppleLanguages") }
        else { defaults.set(code, forKey: key); defaults.set([code], forKey: "AppleLanguages") }
        return true
    }
    /// The helper waits for this writer to quit and restore screenshot settings
    /// before the next process opens the same SQLite store.
    @MainActor static func reopen() throws {
        let helper = Process(); helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.1; done; exec /usr/bin/open \"$2\"", "clipboardline-reopen", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundleURL.path]
        try helper.run(); relaunching = true
        NSApp.terminate(nil)
    }
}
