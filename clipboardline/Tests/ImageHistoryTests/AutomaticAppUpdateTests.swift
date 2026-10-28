#if !STANDALONE_TESTS
import CryptoKit
import XCTest
@testable import Tendedero

private enum SyntheticAutomaticUpdateFailure: Error { case offline, unexpectedRequest }

private final class AutomaticUpdateCredentialCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var readStorage = 0
    private var authorizationStorage = 0
    private var mutationStorage = 0
    var reads: Int { lock.lock(); defer { lock.unlock() }; return readStorage }
    var authorizations: Int { lock.lock(); defer { lock.unlock() }; return authorizationStorage }
    var mutations: Int { lock.lock(); defer { lock.unlock() }; return mutationStorage }
    func read() { lock.lock(); readStorage += 1; lock.unlock() }
    func authorize() { lock.lock(); authorizationStorage += 1; lock.unlock() }
    func mutate() { lock.lock(); mutationStorage += 1; lock.unlock() }
}

/// Synthetic in-memory GitHub responses. No request is ever sent to a network,
/// and suspended responses deliberately ignore cancellation to test stale work.
private actor AutomaticUpdateServer {
    let repository: UpdateRepository
    let signingKey: Curve25519.Signing.PrivateKey
    private var responses: [String: Data] = [:]
    private var requests = 0
    private var failure = false
    private var pauseNext = false
    private var suspended: CheckedContinuation<Void, Never>?
    init(repository: UpdateRepository, signingKey: Curve25519.Signing.PrivateKey) {
        self.repository = repository; self.signingKey = signingKey
    }
    var requestCount: Int { requests }
    var isSuspended: Bool { suspended != nil }
    func setFailure(_ value: Bool) { failure = value }
    func suspendNextRequest() { pauseNext = true }
    func resume() { let continuation = suspended; suspended = nil; continuation?.resume() }
    func setOffers(_ builds: [Int], signingKey override: Curve25519.Signing.PrivateKey? = nil) throws {
        var releases: [[String: Any]] = []
        responses = [:]
        for build in builds {
            let version = "1.5.0-review.\(build)", tag = "release-\(build)"
            let manifest = UpdateManifest(schemaVersion: 1, repository: repository.slug, version: version, build: build,
                                          minimumSystemVersion: "14.0", archiveName: "ClipboardLine-\(version)-build\(build).zip",
                                          archiveSize: 1024, archiveSHA256: String(repeating: "a", count: 64))
            let payload = try JSONEncoder().encode(manifest)
            let envelope = try JSONEncoder().encode(SignedUpdateEnvelope(payload: payload.base64EncodedString(),
                signature: (override ?? signingKey).signature(for: payload).base64EncodedString()))
            let manifestID = build * 10 + 1, archiveID = build * 10 + 2
            func asset(id: Int, name: String, size: Int) throws -> [String: Any] {
                ["id": id, "name": name, "size": size, "url": try repository.releaseAssetURL(id: id).absoluteString,
                 "browser_download_url": "https://github.com/\(repository.slug)/releases/download/\(tag)/\(name)"]
            }
            releases.append(["id": build, "tag_name": tag, "draft": false, "prerelease": true,
                             "assets": [try asset(id: manifestID, name: "clipboardline-update.json", size: envelope.count),
                                        try asset(id: archiveID, name: manifest.archiveName, size: 1024)]])
            responses[try repository.releaseAssetURL(id: manifestID).path] = envelope
        }
        responses[repository.releasesURL.path] = try JSONSerialization.data(withJSONObject: releases)
    }
    func fetch(_ url: URL, token: String?, limit: Int, asset: Bool) async throws -> Data {
        requests += 1
        if pauseNext {
            pauseNext = false
            await withCheckedContinuation { suspended = $0 }
        }
        if failure { throw SyntheticAutomaticUpdateFailure.offline }
        guard let response = responses[url.path] else { throw SyntheticAutomaticUpdateFailure.unexpectedRequest }
        return response
    }
}

@MainActor
private final class AutomaticUpdateFixture {
    let suite = "synthetic-automatic-updates-\(UUID().uuidString)"
    let defaults: UserDefaults
    let key = Curve25519.Signing.PrivateKey()
    let repository = try! UpdateRepository(owner: "synthetic", name: "clipboardline")
    let calls = AutomaticUpdateCredentialCalls()
    let server: AutomaticUpdateServer
    var clock = Date(timeIntervalSince1970: 1_800_000_000)
    init() {
        defaults = UserDefaults(suiteName: suite)!
        server = AutomaticUpdateServer(repository: repository, signingKey: key)
    }
    func makeController(enabled: Bool = true, build: Int = 1, publicKey: Data? = nil,
                        startupDelay: TimeInterval = 0.02, interval: TimeInterval = AutomaticUpdateSchedule.interval,
                        deniedRead: Bool = false) -> AppUpdateController {
        let calls = calls, server = server, repository = repository, verificationKey = publicKey ?? key.publicKey.rawRepresentation
        let credentials = UpdateCredentialStore(load: {
            calls.read()
            if deniedRead { throw UpdateCredentialBrokerError.denied }
            return "synthetic-automatic-token"
        }, save: { _ in calls.mutate() }, remove: { calls.mutate() }, authorize: { calls.authorize(); return "synthetic-automatic-token" })
        return AppUpdateController(enabled: enabled, credentials: credentials,
            configuration: { (repository, verificationKey, build) },
            fetch: { url, token, limit, asset in try await server.fetch(url, token: token, limit: limit, asset: asset) },
            defaults: defaults, now: { [weak self] in self?.clock ?? Date(timeIntervalSince1970: 1_800_000_000) },
            startupDelay: startupDelay, automaticInterval: interval, automaticBusyRetryDelay: 0.02)
    }
    func clean() { defaults.removePersistentDomain(forName: suite) }
}

final class AutomaticAppUpdateTests: XCTestCase {
    @MainActor private func wait(_ predicate: () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(3)
        while !(await predicate()) && Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
        let result = await predicate()
        XCTAssertTrue(result, "Synthetic automatic update did not settle", file: file, line: line)
    }
    private func settle() async { try? await Task.sleep(nanoseconds: 80_000_000) }

    func testSchedulingPolicyUsesTwelveHoursAndBoundsClockChanges() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(AutomaticUpdateSchedule.startupDelay, 30)
        XCTAssertEqual(AutomaticUpdateSchedule.interval, 43_200)
        XCTAssertEqual(AutomaticUpdateSchedule.delay(now: now, lastAttempt: nil), 0)
        XCTAssertEqual(AutomaticUpdateSchedule.delay(now: now, lastAttempt: now), 43_200)
        XCTAssertEqual(AutomaticUpdateSchedule.delay(now: now, lastAttempt: now.addingTimeInterval(-43_199)), 1)
        XCTAssertEqual(AutomaticUpdateSchedule.delay(now: now, lastAttempt: now.addingTimeInterval(-43_201)), 0)
        XCTAssertEqual(AutomaticUpdateSchedule.delay(now: now, lastAttempt: now.addingTimeInterval(600)), 43_200)
        XCTAssertEqual(AutomaticUpdateSchedule.bounded(.infinity, fallback: 30), 30)
        XCTAssertEqual(AutomaticUpdateSchedule.bounded(-1, fallback: 30), 30)
        XCTAssertEqual(AutomaticUpdateSchedule.aboutRefreshInterval, 60)
        XCTAssertTrue(AutomaticUpdateSchedule.shouldRefreshWhenShown(now: now, lastAttempt: nil))
        XCTAssertFalse(AutomaticUpdateSchedule.shouldRefreshWhenShown(now: now, lastAttempt: now))
        XCTAssertFalse(AutomaticUpdateSchedule.shouldRefreshWhenShown(now: now, lastAttempt: now.addingTimeInterval(-59)))
        XCTAssertTrue(AutomaticUpdateSchedule.shouldRefreshWhenShown(now: now, lastAttempt: now.addingTimeInterval(-60)))
        XCTAssertTrue(AutomaticUpdateSchedule.shouldRefreshWhenShown(now: now, lastAttempt: now.addingTimeInterval(600)))
    }

    @MainActor func testDefaultsOnButLifecycleMustStartBeforeAnyBackgroundActivity() async throws {
        let fixture = AutomaticUpdateFixture(); defer { fixture.clean() }
        try await fixture.server.setOffers([])
        let controller = fixture.makeController()
        defer { controller.stopAutomaticChecks() }
        XCTAssertTrue(controller.automaticChecksEnabled)
        await settle()
        XCTAssertEqual(fixture.calls.reads, 0)
        controller.startAutomaticChecks()
        await wait { fixture.calls.reads == 1 && !controller.busy }
        XCTAssertNil(controller.error); XCTAssertEqual(controller.status, L("You are up to date."))
        XCTAssertEqual(fixture.calls.authorizations, 0); XCTAssertEqual(fixture.calls.mutations, 0)
    }

    @MainActor func testAboutRefreshFindsNewBuildBeforePeriodicInterval() async throws {
        let fixture = AutomaticUpdateFixture(); defer { fixture.clean() }
        try await fixture.server.setOffers([49])
        let controller = fixture.makeController(build: 49)
        controller.manualCheck(); await wait { !controller.busy }
        XCTAssertEqual(controller.status, L("You are up to date.")); XCTAssertNil(controller.available)
        let firstCheck = fixture.clock
        XCTAssertEqual(controller.lastSuccessfulCheck, firstCheck)
        try await fixture.server.setOffers([51])
        fixture.clock.addTimeInterval(60)
        controller.refreshWhenUpdatesAreShown()
        XCTAssertEqual(controller.status, L("Checking for updates…"))
        await wait { !controller.busy }
        XCTAssertEqual(controller.available?.manifest.build, 51)
        XCTAssertEqual(controller.lastSuccessfulCheck, fixture.clock)
        XCTAssertLessThan(fixture.clock.timeIntervalSince(firstCheck), AutomaticUpdateSchedule.interval)
        XCTAssertEqual(fixture.calls.reads, 2); XCTAssertEqual(fixture.calls.authorizations, 0)
    }

    @MainActor func testAboutRefreshIsThrottledAndDoesNotOverlapBusyCheck() async throws {
        let fixture = AutomaticUpdateFixture(); defer { fixture.clean() }
        try await fixture.server.setOffers([]); await fixture.server.suspendNextRequest()
        let controller = fixture.makeController()
        controller.refreshWhenUpdatesAreShown()
        await wait { await fixture.server.isSuspended }
        controller.refreshWhenUpdatesAreShown(); await settle()
        XCTAssertEqual(fixture.calls.reads, 1); XCTAssertNil(controller.lastSuccessfulCheck)
        await fixture.server.resume(); await wait { !controller.busy }
        controller.refreshWhenUpdatesAreShown(); fixture.clock.addTimeInterval(59)
        controller.refreshWhenUpdatesAreShown(); await settle()
        XCTAssertEqual(fixture.calls.reads, 1)
        fixture.clock.addTimeInterval(1); controller.refreshWhenUpdatesAreShown()
        await wait { fixture.calls.reads == 2 && !controller.busy }
        fixture.clock.addTimeInterval(-600); controller.refreshWhenUpdatesAreShown()
        await wait { fixture.calls.reads == 3 && !controller.busy }
        controller.refreshWhenUpdatesAreShown(); await settle()
        XCTAssertEqual(fixture.calls.reads, 3, "The backwards-clock refresh establishes a fresh throttle baseline")
        XCTAssertEqual(fixture.calls.authorizations, 0)
    }

    @MainActor func testAboutRefreshRespectsDisabledPreferenceHarnessAndMissingConfiguration() async throws {
        let fixture = AutomaticUpdateFixture(); defer { fixture.clean() }
        let disabled = fixture.makeController(enabled: false)
        disabled.refreshWhenUpdatesAreShown()
        let optedOut = fixture.makeController(); optedOut.setAutomaticChecksEnabled(false)
        optedOut.refreshWhenUpdatesAreShown()
        let calls = fixture.calls
        let unconfigured = AppUpdateController(credentials: UpdateCredentialStore(load: { calls.read(); return "synthetic-token" },
            save: { _ in calls.mutate() }, remove: { calls.mutate() }, authorize: { calls.authorize(); return "synthetic-token" }),
            configuration: { nil }, defaults: fixture.defaults)
        unconfigured.setAutomaticChecksEnabled(true); unconfigured.refreshWhenUpdatesAreShown()
        await settle()
        XCTAssertEqual(fixture.calls.reads, 0); XCTAssertEqual(fixture.calls.authorizations, 0)
        XCTAssertEqual(fixture.calls.mutations, 0)
        let count = await fixture.server.requestCount; XCTAssertEqual(count, 0)
        XCTAssertFalse(disabled.busy); XCTAssertFalse(optedOut.busy); XCTAssertFalse(unconfigured.busy)
    }

    @MainActor func testAboutRefreshDenialIsVisibleWithoutAuthorization() async throws {
        let fixture = AutomaticUpdateFixture(); defer { fixture.clean() }
        let controller = fixture.makeController(deniedRead: true)
        controller.refreshWhenUpdatesAreShown()
        XCTAssertEqual(controller.status, L("Checking for updates…"))
        await wait { !controller.busy }
        XCTAssertEqual(controller.status, L("Update check could not be completed."))
        XCTAssertNotNil(controller.error); XCTAssertTrue(controller.needsAuthorization)
        XCTAssertEqual(fixture.calls.reads, 1); XCTAssertEqual(fixture.calls.authorizations, 0)
        XCTAssertEqual(fixture.calls.mutations, 0); XCTAssertNil(controller.lastSuccessfulCheck)
        XCTAssertNil(fixture.defaults.object(forKey: AutomaticUpdateSchedule.lastSuccessfulCheckKey))
        let count = await fixture.server.requestCount; XCTAssertEqual(count, 0)
    }

    @MainActor func testSuccessfulCheckTimestampSurvivesRelaunchAndFailedOrCancelledChecks() async throws {
        let fixture = AutomaticUpdateFixture(); defer { fixture.clean() }
        try await fixture.server.setOffers([])
        let controller = fixture.makeController()
        controller.manualCheck(); await wait { !controller.busy }
        let successful = fixture.clock
        XCTAssertEqual(controller.lastSuccessfulCheck, successful)
        XCTAssertEqual(fixture.defaults.object(forKey: AutomaticUpdateSchedule.lastSuccessfulCheckKey) as? Date, successful)
        XCTAssertEqual(fixture.makeController().lastSuccessfulCheck, successful)
        fixture.clock.addTimeInterval(60); await fixture.server.setFailure(true)
        controller.refreshWhenUpdatesAreShown(); await wait { !controller.busy }
        XCTAssertNotNil(controller.error); XCTAssertEqual(controller.lastSuccessfulCheck, successful)
        await fixture.server.setFailure(false); await fixture.server.suspendNextRequest()
        fixture.clock.addTimeInterval(60); controller.startAutomaticChecks()
        await wait { await fixture.server.isSuspended }
        controller.stopAutomaticChecks(); await fixture.server.resume()
        await wait { !controller.busy }
        XCTAssertEqual(controller.lastSuccessfulCheck, successful)
        XCTAssertEqual(fixture.defaults.object(forKey: AutomaticUpdateSchedule.lastSuccessfulCheckKey) as? Date, successful)
    }

    @MainActor func testPreferencePersistsAndDisabledHarnessCannotEnableOrDoAnyIO() async throws {
        let fixture = AutomaticUpdateFixture(); defer { fixture.clean() }
        let controller = fixture.makeController()
        controller.setAutomaticChecksEnabled(false)
        let restored = fixture.makeController()
        XCTAssertFalse(restored.automaticChecksEnabled)
        restored.startAutomaticChecks(); restored.recheckAutomaticUpdatesAfterWake()
        let disabled = fixture.makeController(enabled: false)
        disabled.setAutomaticChecksEnabled(true); disabled.startAutomaticChecks(); disabled.recheckAutomaticUpdatesAfterWake()
        disabled.manualCheck(); disabled.installAvailableUpdate(expectedBuild: 2)
        await settle()
        XCTAssertFalse(disabled.automaticChecksEnabled)
        XCTAssertEqual(fixture.calls.reads, 0)
        let count = await fixture.server.requestCount
        XCTAssertEqual(count, 0); XCTAssertNil(disabled.available)
        XCTAssertFalse(fixture.defaults.bool(forKey: AutomaticUpdateSchedule.preferenceKey))
        restored.stopAutomaticChecks()
    }

    @MainActor func testAutomaticCheckAuthenticatesHighestBuildAndOnlyFetchesMetadata() async throws {
        let fixture = AutomaticUpdateFixture(); defer { fixture.clean() }
        try await fixture.server.setOffers([3, 5, 1])
        let controller = fixture.makeController()
        defer { controller.stopAutomaticChecks() }
        var notifications: [Int] = []
        controller.onAutomaticUpdateAvailable = { offer, complete in notifications.append(offer.manifest.build); complete(true) }
        controller.startAutomaticChecks()
        await wait { controller.available?.manifest.build == 5 && !controller.busy }
        XCTAssertEqual(notifications, [5]); XCTAssertEqual(controller.available?.asset.id, 52)
        XCTAssertEqual(fixture.defaults.integer(forKey: AutomaticUpdateSchedule.notifiedBuildKey), 5)
        let count = await fixture.server.requestCount
        XCTAssertEqual(count, 4, "Only release list and signed manifests may be fetched; never archive52")
        XCTAssertEqual(fixture.calls.authorizations, 0); XCTAssertEqual(fixture.calls.mutations, 0)
        XCTAssertNotNil(fixture.defaults.data(forKey: AutomaticUpdateSchedule.availableUpdateKey))
    }

    @MainActor func testWrongSignatureAndNonIncreasingBuildNeverNotify() async throws {
        let fixture = AutomaticUpdateFixture(); defer { fixture.clean() }
        try await fixture.server.setOffers([5], signingKey: Curve25519.Signing.PrivateKey())
        let controller = fixture.makeController()
        defer { controller.stopAutomaticChecks() }
        let initial = controller.status
        var notifications = 0
        controller.onAutomaticUpdateAvailable = { _, complete in notifications += 1; complete(true) }
        controller.startAutomaticChecks()
        await wait { fixture.calls.reads == 1 && !controller.busy }
        XCTAssertNil(controller.available); XCTAssertNil(controller.error); XCTAssertEqual(controller.status, initial)
        try await fixture.server.setOffers([1])
        fixture.clock.addTimeInterval(43_201)
        controller.recheckAutomaticUpdatesAfterWake()
        await wait { fixture.calls.reads == 2 && !controller.busy }
        XCTAssertNil(controller.available); XCTAssertEqual(notifications, 0)
        XCTAssertNil(fixture.defaults.object(forKey: AutomaticUpdateSchedule.notifiedBuildKey))
    }

    @MainActor func testBackgroundCredentialFailureIsQuietAndNeverRequestsAuthorization() async {
        let fixture = AutomaticUpdateFixture(); defer { fixture.clean() }
        let controller = fixture.makeController(deniedRead: true)
        defer { controller.stopAutomaticChecks() }
        let initial = controller.status
        controller.startAutomaticChecks()
        await wait { fixture.calls.reads == 1 && !controller.busy }
        XCTAssertEqual(controller.status, initial); XCTAssertNil(controller.error)
        XCTAssertFalse(controller.needsAuthorization); XCTAssertEqual(fixture.calls.authorizations, 0)
        let count = await fixture.server.requestCount
        XCTAssertEqual(count, 0)
    }

    @MainActor func testDisableCancelsPendingStartupAndReenableChecksDespiteRecentAttempt() async throws {
        let fixture = AutomaticUpdateFixture(); defer { fixture.clean() }
        try await fixture.server.setOffers([])
        fixture.defaults.set(fixture.clock, forKey: AutomaticUpdateSchedule.lastAttemptKey)
        let controller = fixture.makeController(startupDelay: 0.05)
        defer { controller.stopAutomaticChecks() }
        controller.startAutomaticChecks(); controller.setAutomaticChecksEnabled(false)
        await settle(); XCTAssertEqual(fixture.calls.reads, 0)
        controller.setAutomaticChecksEnabled(true)
        await wait { fixture.calls.reads == 1 && !controller.busy }
        XCTAssertEqual(controller.status, L("You are up to date."))
    }

    @MainActor func testDisableDuringFetchSuppressesLateOfferAndNotification() async throws {
        let fixture = AutomaticUpdateFixture(); defer { fixture.clean() }
        try await fixture.server.setOffers([5]); await fixture.server.suspendNextRequest()
        let controller = fixture.makeController()
        defer { controller.stopAutomaticChecks() }
        let original = controller.status
        var notifications = 0
        controller.onAutomaticUpdateAvailable = { _, complete in notifications += 1; complete(true) }
        controller.startAutomaticChecks()
        await wait { await fixture.server.isSuspended }
        XCTAssertTrue(controller.busy)
        controller.setAutomaticChecksEnabled(false)
        await fixture.server.resume()
        await wait { !controller.busy }
        XCTAssertNil(controller.available); XCTAssertNil(controller.error); XCTAssertEqual(controller.status, original)
        XCTAssertEqual(notifications, 0)
        XCTAssertNil(fixture.defaults.object(forKey: AutomaticUpdateSchedule.availableUpdateKey))
        let count = await fixture.server.requestCount
        XCTAssertEqual(count, 1, "Stale release list must not lead to manifest requests")
    }

    @MainActor func testStoppingLifecycleCancelsRunningAutomaticWorkWithoutChangingPreference() async throws {
        let fixture = AutomaticUpdateFixture(); defer { fixture.clean() }
        try await fixture.server.setOffers([5]); await fixture.server.suspendNextRequest()
        let controller = fixture.makeController()
        controller.startAutomaticChecks(); await wait { await fixture.server.isSuspended }
        controller.stopAutomaticChecks(); await fixture.server.resume()
        await wait { !controller.busy }
        XCTAssertTrue(controller.automaticChecksEnabled); XCTAssertNil(controller.available)
        controller.startAutomaticChecks()
        await wait { controller.available != nil && !controller.busy }
        controller.stopAutomaticChecks()
    }

    @MainActor func testOffOnWhileCancelledFetchSettlesKeepsFreshStartupDeadline() async throws {
        let fixture = AutomaticUpdateFixture(); defer { fixture.clean() }
        try await fixture.server.setOffers([5]); await fixture.server.suspendNextRequest()
        let controller = fixture.makeController(startupDelay: 0.03)
        defer { controller.stopAutomaticChecks() }
        var notifications: [Int] = []
        controller.onAutomaticUpdateAvailable = { offer, complete in notifications.append(offer.manifest.build); complete(true) }
        controller.startAutomaticChecks(); await wait { await fixture.server.isSuspended }
        controller.setAutomaticChecksEnabled(false); controller.setAutomaticChecksEnabled(true)
        await fixture.server.resume()
        await wait { fixture.calls.reads == 2 && !controller.busy }
        XCTAssertEqual(controller.available?.manifest.build, 5)
        XCTAssertEqual(notifications, [5])
    }

    @MainActor func testDisablingAutomaticChecksDoesNotCancelExplicitManualCheck() async throws {
        let fixture = AutomaticUpdateFixture(); defer { fixture.clean() }
        try await fixture.server.setOffers([5]); await fixture.server.suspendNextRequest()
        let controller = fixture.makeController(startupDelay: 0.2)
        defer { controller.stopAutomaticChecks() }
        controller.startAutomaticChecks(); controller.manualCheck()
        await wait { await fixture.server.isSuspended }
        controller.setAutomaticChecksEnabled(false); await fixture.server.resume()
        await wait { !controller.busy }
        XCTAssertEqual(controller.available?.manifest.build, 5); XCTAssertNil(controller.error)
        XCTAssertEqual(fixture.calls.reads, 1)
    }

    @MainActor func testWakeChecksOnlyWhenDueAndDuplicateStartsNeverOverlap() async throws {
        let fixture = AutomaticUpdateFixture(); defer { fixture.clean() }
        try await fixture.server.setOffers([])
        let controller = fixture.makeController()
        defer { controller.stopAutomaticChecks() }
        controller.startAutomaticChecks(); controller.startAutomaticChecks()
        await wait { fixture.calls.reads == 1 && !controller.busy }
        controller.recheckAutomaticUpdatesAfterWake(); await settle()
        XCTAssertEqual(fixture.calls.reads, 1)
        fixture.clock.addTimeInterval(43_201)
        await fixture.server.suspendNextRequest()
        controller.recheckAutomaticUpdatesAfterWake()
        await wait { await fixture.server.isSuspended }
        controller.recheckAutomaticUpdatesAfterWake(); controller.startAutomaticChecks(); controller.manualCheck()
        await settle(); XCTAssertEqual(fixture.calls.reads, 2)
        await fixture.server.resume(); await wait { !controller.busy }
        await settle(); XCTAssertEqual(fixture.calls.reads, 2)
    }

    @MainActor func testPeriodicTimerPerformsAnotherCheckWithoutWake() async throws {
        let fixture = AutomaticUpdateFixture(); defer { fixture.clean() }
        try await fixture.server.setOffers([])
        let controller = fixture.makeController(interval: 0.04)
        controller.startAutomaticChecks()
        await wait { fixture.calls.reads >= 2 && !controller.busy }
        controller.stopAutomaticChecks()
        XCTAssertEqual(fixture.calls.authorizations, 0)
    }

    @MainActor func testOfferAndNotificationDedupeSurviveControllerRelaunch() async throws {
        let fixture = AutomaticUpdateFixture(); defer { fixture.clean() }
        try await fixture.server.setOffers([5])
        let first = fixture.makeController()
        var notifications: [Int] = []
        first.onAutomaticUpdateAvailable = { offer, complete in notifications.append(offer.manifest.build); complete(true) }
        first.startAutomaticChecks(); await wait { first.available != nil && !first.busy }
        first.stopAutomaticChecks()
        let second = fixture.makeController()
        XCTAssertEqual(second.available?.manifest.build, 5)
        second.onAutomaticUpdateAvailable = { offer, complete in notifications.append(offer.manifest.build); complete(true) }
        second.startAutomaticChecks(); await wait { fixture.calls.reads == 2 && !second.busy }
        XCTAssertEqual(notifications, [5])
        try await fixture.server.setOffers([6])
        fixture.clock.addTimeInterval(43_201); second.recheckAutomaticUpdatesAfterWake()
        await wait { second.available?.manifest.build == 6 && !second.busy }
        XCTAssertEqual(notifications, [5, 6])
        second.stopAutomaticChecks()
    }

    @MainActor func testCallbackMissingDoesNotConsumeNotificationAndBackgroundFailureKeepsOffer() async throws {
        let fixture = AutomaticUpdateFixture(); defer { fixture.clean() }
        try await fixture.server.setOffers([5])
        let controller = fixture.makeController()
        defer { controller.stopAutomaticChecks() }
        controller.startAutomaticChecks(); await wait { controller.available != nil && !controller.busy }
        XCTAssertNil(fixture.defaults.object(forKey: AutomaticUpdateSchedule.notifiedBuildKey))
        let status = controller.status
        var notifications: [Int] = []
        controller.onAutomaticUpdateAvailable = { offer, complete in notifications.append(offer.manifest.build); complete(true) }
        fixture.clock.addTimeInterval(43_201); controller.recheckAutomaticUpdatesAfterWake()
        await wait { fixture.calls.reads == 2 && !controller.busy }
        XCTAssertEqual(notifications, [5])
        await fixture.server.setFailure(true)
        fixture.clock.addTimeInterval(43_201); controller.recheckAutomaticUpdatesAfterWake()
        await wait { fixture.calls.reads == 3 && !controller.busy }
        XCTAssertEqual(controller.available?.manifest.build, 5); XCTAssertEqual(controller.status, status); XCTAssertNil(controller.error)
        controller.setAutomaticChecksEnabled(false)
        XCTAssertEqual(controller.available?.manifest.build, 5)
    }

    @MainActor func testCachedOfferIsReverifiedAgainstKeyBuildAndUntrustedAssetFields() async throws {
        let fixture = AutomaticUpdateFixture(); defer { fixture.clean() }
        try await fixture.server.setOffers([5])
        let controller = fixture.makeController(); controller.manualCheck()
        await wait { !controller.busy }
        let valid = try XCTUnwrap(fixture.defaults.data(forKey: AutomaticUpdateSchedule.availableUpdateKey))
        XCTAssertEqual(fixture.makeController().available?.manifest.build, 5)
        XCTAssertNil(fixture.makeController(build: 5).available)
        XCTAssertNil(fixture.makeController(publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation).available)
        var stored = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        stored["assetSize"] = 2048
        fixture.defaults.set(try JSONSerialization.data(withJSONObject: stored), forKey: AutomaticUpdateSchedule.availableUpdateKey)
        XCTAssertNil(fixture.makeController().available)
        stored = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        stored["assetURL"] = "https://evil.example/archive"
        fixture.defaults.set(try JSONSerialization.data(withJSONObject: stored), forKey: AutomaticUpdateSchedule.availableUpdateKey)
        XCTAssertNil(fixture.makeController().available)
        stored = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        stored["envelope"] = Data("forged unsigned update".utf8).base64EncodedString()
        fixture.defaults.set(try JSONSerialization.data(withJSONObject: stored), forKey: AutomaticUpdateSchedule.availableUpdateKey)
        XCTAssertNil(fixture.makeController().available)
        fixture.defaults.set(Data(repeating: 0x20, count: 131_073), forKey: AutomaticUpdateSchedule.availableUpdateKey)
        XCTAssertNil(fixture.makeController().available)
    }

    @MainActor func testNotificationCancellationDoesNotConsumeBuildAndRetriesAfterReenable() async throws {
        let fixture = AutomaticUpdateFixture(); defer { fixture.clean() }
        try await fixture.server.setOffers([5])
        let controller = fixture.makeController()
        defer { controller.stopAutomaticChecks() }
        var completions: [(Bool) -> Void] = []
        controller.onAutomaticUpdateAvailable = { _, complete in completions.append(complete) }
        controller.startAutomaticChecks(); await wait { completions.count == 1 && !controller.busy }
        XCTAssertNil(fixture.defaults.object(forKey: AutomaticUpdateSchedule.notifiedBuildKey))
        controller.setAutomaticChecksEnabled(false)
        completions[0](false)
        controller.setAutomaticChecksEnabled(true)
        await wait { completions.count == 2 && !controller.busy }
        // A late old success must neither consume the new flight nor mark it.
        completions[0](true)
        XCTAssertNil(fixture.defaults.object(forKey: AutomaticUpdateSchedule.notifiedBuildKey))
        completions[1](true)
        XCTAssertEqual(fixture.defaults.integer(forKey: AutomaticUpdateSchedule.notifiedBuildKey), 5)
    }

    @MainActor func testTransientNotificationFailureRetriesAndInFlightDeliveryIsNotDuplicated() async throws {
        let fixture = AutomaticUpdateFixture(); defer { fixture.clean() }
        try await fixture.server.setOffers([5])
        let controller = fixture.makeController()
        defer { controller.stopAutomaticChecks() }
        var completions: [(Bool) -> Void] = []
        controller.onAutomaticUpdateAvailable = { _, complete in completions.append(complete) }
        controller.startAutomaticChecks(); await wait { completions.count == 1 && !controller.busy }
        fixture.clock.addTimeInterval(43_201); controller.recheckAutomaticUpdatesAfterWake()
        await wait { fixture.calls.reads == 2 && !controller.busy }
        XCTAssertEqual(completions.count, 1, "A pending permission prompt must not be duplicated")
        completions[0](false)
        XCTAssertNil(fixture.defaults.object(forKey: AutomaticUpdateSchedule.notifiedBuildKey))
        fixture.clock.addTimeInterval(43_201); controller.recheckAutomaticUpdatesAfterWake()
        await wait { completions.count == 2 && !controller.busy }
        completions[1](true); completions[1](false)
        XCTAssertEqual(fixture.defaults.integer(forKey: AutomaticUpdateSchedule.notifiedBuildKey), 5)
        fixture.clock.addTimeInterval(43_201); controller.recheckAutomaticUpdatesAfterWake()
        await wait { fixture.calls.reads == 4 && !controller.busy }
        XCTAssertEqual(completions.count, 2, "An acknowledged build stays deduplicated")
    }

    @MainActor func testLateNotificationCompletionCannotOverrideNewerBuildFlight() async throws {
        let fixture = AutomaticUpdateFixture(); defer { fixture.clean() }
        try await fixture.server.setOffers([5])
        let controller = fixture.makeController()
        defer { controller.stopAutomaticChecks() }
        var offers: [Int] = [], completions: [(Bool) -> Void] = []
        controller.onAutomaticUpdateAvailable = { offer, complete in offers.append(offer.manifest.build); completions.append(complete) }
        controller.startAutomaticChecks(); await wait { completions.count == 1 && !controller.busy }
        try await fixture.server.setOffers([6])
        fixture.clock.addTimeInterval(43_201); controller.recheckAutomaticUpdatesAfterWake()
        await wait { completions.count == 2 && !controller.busy }
        XCTAssertEqual(offers, [5, 6])
        completions[0](true)
        XCTAssertNil(fixture.defaults.object(forKey: AutomaticUpdateSchedule.notifiedBuildKey))
        completions[1](true)
        completions[0](false); completions[0](true)
        XCTAssertEqual(fixture.defaults.integer(forKey: AutomaticUpdateSchedule.notifiedBuildKey), 6)
    }

    @MainActor func testNotificationActionNeverInstallsDifferentOrMissingAdvertisedBuild() async throws {
        let fixture = AutomaticUpdateFixture(); defer { fixture.clean() }
        try await fixture.server.setOffers([5])
        let controller = fixture.makeController(); controller.manualCheck()
        await wait { !controller.busy }
        controller.installAvailableUpdate(expectedBuild: 4)
        await wait { fixture.calls.reads == 2 && !controller.busy }
        XCTAssertEqual(controller.available?.manifest.build, 5)
        XCTAssertNil(controller.progress)
        let count = await fixture.server.requestCount
        XCTAssertEqual(count, 4, "Mismatched notification actions refresh metadata, never download the archive")
        let withoutOffer = fixture.makeController(build: 5)
        withoutOffer.installAvailableUpdate(expectedBuild: 4)
        await wait { fixture.calls.reads == 3 && !withoutOffer.busy }
        XCTAssertNil(withoutOffer.available); XCTAssertNil(withoutOffer.progress)
    }
}
#endif
