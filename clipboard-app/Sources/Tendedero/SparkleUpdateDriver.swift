#if canImport(Sparkle)
import AppKit
import Combine
import Sparkle

/// Sparkle owns the native release-notes, download, install and relaunch flow.
/// This driver has no credential API: the signed official feed is anonymous.
@MainActor
final class SparkleUpdateDriver: NSObject, ObservableObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    struct State: Equatable {
        let status: String
        let error: String?
        let availableVersion: String?
        let availableBuild: Int?
        let busy: Bool
        let lastSuccessfulCheck: Date?
        let automaticChecksEnabled: Bool
    }

    @Published private(set) var status = L("Check for updates…")
    @Published private(set) var error: String?
    @Published private(set) var availableVersion: String?
    @Published private(set) var availableBuild: Int?
    @Published private(set) var busy = false
    @Published private(set) var lastSuccessfulCheck: Date?
    @Published private(set) var automaticChecksEnabled: Bool

    var state: State {
        State(status: status, error: error, availableVersion: availableVersion,
              availableBuild: availableBuild, busy: busy, lastSuccessfulCheck: lastSuccessfulCheck,
              automaticChecksEnabled: automaticChecksEnabled)
    }

    /// Published values arrive before their stored properties change. Forward
    /// those values directly, including while Sparkle runs a native modal loop.
    var states: AnyPublisher<State, Never> {
        Publishers.CombineLatest4($status, $error, $availableVersion, $availableBuild)
            .combineLatest(Publishers.CombineLatest3($busy, $lastSuccessfulCheck, $automaticChecksEnabled))
            .map { details, checks in
                State(status: details.0, error: details.1, availableVersion: details.2,
                      availableBuild: details.3, busy: checks.0, lastSuccessfulCheck: checks.1,
                      automaticChecksEnabled: checks.2)
            }
            .eraseToAnyPublisher()
    }

    var canQuit: () -> Bool = { true }
    var onAvailable: ((String, Int) -> Void)?

    private let defaults: UserDefaults
    private let channel: PublicUpdateChannel
    private var controller: SPUStandardUpdaterController?
    private var observations: [NSKeyValueObservation] = []
    private var started = false
    private var pendingInstall: (() -> Void)?
    private var lastAnnouncedBuild: Int?

    init?(enabled: Bool = true, defaults: UserDefaults = .standard, info: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        guard enabled, let channel = PublicUpdateChannel(info: info) else { return nil }
        self.defaults = defaults
        self.channel = channel
        automaticChecksEnabled = PublicUpdateChannel.automaticChecksEnabled(in: defaults)
        lastSuccessfulCheck = defaults.object(forKey: AutomaticUpdateSchedule.lastSuccessfulCheckKey) as? Date
        super.init()
    }

    func start() {
        guard !started else { return }
        // Pin the intended preference before Sparkle persists its own lifecycle
        // changes. A default-on legacy client must stay on after quit/update.
        defaults.set(automaticChecksEnabled, forKey: AutomaticUpdateSchedule.preferenceKey)
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        // Set this before starting Sparkle so a legacy opt-out also applies to
        // its first scheduled check. Automatic downloads are never allowed.
        controller.updater.automaticallyChecksForUpdates = automaticChecksEnabled
        controller.updater.automaticallyDownloadsUpdates = false
        self.controller = controller
        started = true
        do {
            try controller.updater.start()
            observations = [controller.updater.observe(\.sessionInProgress, options: [.new]) { [weak self] _, change in
                Task { @MainActor in
                    guard let self, self.started else { return }
                    if change.newValue == false { self.busy = false }
                }
            }]
        } catch {
            self.error = error.localizedDescription
            status = L("Update check could not be completed.")
            started = false
            self.controller = nil
        }
    }

    func stop() {
        controller?.updater.automaticallyChecksForUpdates = false
        observations.removeAll()
        controller = nil
        started = false
        pendingInstall = nil
        busy = false
    }

    func manualCheck() {
        guard started, let controller, !busy || controller.updater.sessionInProgress else { return }
        error = nil
        NSApp.activate(ignoringOtherApps: true)
        // Sparkle focuses an existing gentle reminder instead of starting a
        // second session. It retains the verified feed and download state.
        controller.checkForUpdates(nil)
    }

    func refreshWhenShown() {
        guard started, automaticChecksEnabled, !busy, availableVersion == nil,
              let updater = controller?.updater, updater.canCheckForUpdates, !updater.sessionInProgress,
              AutomaticUpdateSchedule.shouldRefreshWhenShown(now: Date(),
                lastAttempt: defaults.object(forKey: AutomaticUpdateSchedule.lastAttemptKey) as? Date) else { return }
        updater.checkForUpdatesInBackground()
    }

    func setAutomaticChecksEnabled(_ enabled: Bool) {
        automaticChecksEnabled = enabled
        defaults.set(enabled, forKey: AutomaticUpdateSchedule.preferenceKey)
        controller?.updater.automaticallyChecksForUpdates = enabled
    }

    func installAvailableUpdate(expectedBuild: Int) {
        guard expectedBuild > 0, availableBuild == expectedBuild else { manualCheck(); return }
        guard !busy else { return }
        guard canQuit() else {
            error = L("Save your open edits before installing the update.")
            return
        }
        if let install = pendingInstall {
            pendingInstall = nil
            error = nil
            busy = true
            install()
        } else { manualCheck() }
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool { false }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        recordAvailable(update)
    }

    func standardUserDriverWillFinishUpdateSession() {
        guard started else { return }
        busy = false
        pendingInstall = nil
    }

    func feedURLString(for updater: SPUUpdater) -> String? { channel.feedURL.absoluteString }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard started else { throw DriverError.stopped }
        defaults.set(Date(), forKey: AutomaticUpdateSchedule.lastAttemptKey)
        busy = true
        error = nil
        status = L("Checking for updates…")
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        guard started else { return }
        recordSuccessfulCheck()
        recordAvailable(item)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        guard started else { return }
        recordSuccessfulCheck()
        availableVersion = nil
        availableBuild = nil
        status = L("You are up to date.")
    }

    func updater(_ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice, forUpdate item: SUAppcastItem, state: SPUUserUpdateState) {
        guard started else { return }
        if choice == .install { busy = true; status = L("Downloading update…") }
        else { busy = false }
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        // Requests are Sparkle's unauthenticated public-feed requests. Never
        // add a token, cookies or a private-repository fallback here.
        busy = true
        status = L("Downloading update…")
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        status = L("Verifying update…")
    }

    func updater(_ updater: SPUUpdater, didAbortWithError failure: Error) {
        guard started else { return }
        busy = false
        pendingInstall = nil
        let failure = failure as NSError
        guard failure.domain != SUSparkleErrorDomain || failure.code != Int(SUError.noUpdateError.rawValue) else { return }
        error = failure.localizedDescription
        status = L("Update check could not be completed.")
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        postponeRelaunchIfNeeded(installHandler)
    }

    /// A failed save vetoes restart. Keep the verified installation pending;
    /// retry only after an explicit Update click, never by polling a failed save.
    @discardableResult
    func postponeRelaunchIfNeeded(_ install: @escaping () -> Void) -> Bool {
        guard !canQuit() else { pendingInstall = nil; return false }
        pendingInstall = install
        busy = false
        error = L("Save your open edits before installing the update.")
        return true
    }

    private func recordAvailable(_ item: SUAppcastItem) {
        guard started, let build = Int(item.versionString), build > 0 else { return }
        availableVersion = item.displayVersionString
        availableBuild = build
        status = String(format: L("Version %@ is ready to install."), item.displayVersionString)
        busy = false
        error = nil
        if lastAnnouncedBuild != build {
            lastAnnouncedBuild = build
            onAvailable?(item.displayVersionString, build)
        }
    }

    private func recordSuccessfulCheck() {
        let checked = Date()
        lastSuccessfulCheck = checked
        defaults.set(checked, forKey: AutomaticUpdateSchedule.lastSuccessfulCheckKey)
        busy = false
        error = nil
    }

    private enum DriverError: Error { case stopped }
}
#endif
