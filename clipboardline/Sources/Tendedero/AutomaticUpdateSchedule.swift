import Foundation

/// Time and preference policy only. The scheduler never downloads an archive
/// or asks Keychain to authorize access; installation remains an explicit action.
enum AutomaticUpdateSchedule {
    static let preferenceKey = "automaticAppUpdateChecksEnabled"
    static let lastAttemptKey = "automaticAppUpdateLastAttempt"
    static let lastSuccessfulCheckKey = "appUpdateLastSuccessfulCheck"
    static let notifiedBuildKey = "automaticAppUpdateLastNotifiedBuild"
    static let availableUpdateKey = "automaticAppUpdateVerifiedOffer"
    static let startupDelay: TimeInterval = 30
    static let interval: TimeInterval = 12 * 60 * 60
    static let busyRetryDelay: TimeInterval = 30
    static let aboutRefreshInterval: TimeInterval = 60

    static func shouldRefreshWhenShown(now: Date, lastAttempt: Date?) -> Bool {
        guard let lastAttempt, lastAttempt.timeIntervalSince1970.isFinite else { return true }
        let elapsed = now.timeIntervalSince(lastAttempt)
        // A backwards clock adjustment must not preserve an old "up to date"
        // result until the clock catches up. A new attempt resets this baseline.
        return elapsed < 0 || elapsed >= aboutRefreshInterval
    }

    static func delay(now: Date, lastAttempt: Date?, interval: TimeInterval = interval) -> TimeInterval {
        guard let lastAttempt, lastAttempt.timeIntervalSince1970.isFinite else { return 0 }
        // A clock adjustment must not postpone checks indefinitely. Re-establish
        // the cadence within one interval even when the stored date is ahead.
        return max(0, min(interval, lastAttempt.addingTimeInterval(interval).timeIntervalSince(now)))
    }

    static func bounded(_ value: TimeInterval, fallback: TimeInterval) -> TimeInterval {
        value.isFinite && value >= 0 ? min(value, 7 * 24 * 60 * 60) : fallback
    }
}
