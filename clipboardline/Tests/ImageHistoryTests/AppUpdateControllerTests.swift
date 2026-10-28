#if !STANDALONE_TESTS
import AppKit
import XCTest
@testable import Tendedero

private final class UpdateProgressCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Double] = []
    var values: [Double] { lock.lock(); defer { lock.unlock() }; return storage }
    func record(_ value: Double) { lock.lock(); defer { lock.unlock() }; storage.append(value) }
}

private enum SyntheticCredentialError: Error { case denied, deadline }

/// All credential tests use injected synthetic closures. Nothing calls a
/// Security framework operation, opens a real keychain item or uses a token.
private final class UpdateCredentialGate: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var starts = 0
    private var finishes = 0
    private var mainThread = false
    var entered: Int { lock.lock(); defer { lock.unlock() }; return starts }
    var completed: Int { lock.lock(); defer { lock.unlock() }; return finishes }
    var ranOnMain: Bool { lock.lock(); defer { lock.unlock() }; return mainThread }
    func run(blockFirstOnly: Bool = false) throws {
        lock.lock(); starts += 1; let first = starts == 1; mainThread = mainThread || Thread.isMainThread; lock.unlock()
        defer { lock.lock(); finishes += 1; lock.unlock() }
        if !blockFirstOnly || first {
            guard semaphore.wait(timeout: .now() + 5) == .success else { throw SyntheticCredentialError.deadline }
        }
    }
    func release() { semaphore.signal() }
}

private final class UpdateCredentialCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return storage }
    func call() { lock.lock(); storage += 1; lock.unlock() }
}

private final class SyntheticBrokerTransport: UpdateCredentialBrokerTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var log: [String] = []
    var events: [String] { lock.lock(); defer { lock.unlock() }; return log }
    var onFailure: (@Sendable () -> Void)?
    let handshakeAccepted: Bool
    let dropsReply: Bool
    let deniesCredential: Bool
    init(handshakeAccepted: Bool = true, dropsReply: Bool = false, deniesCredential: Bool = false) {
        self.handshakeAccepted = handshakeAccepted; self.dropsReply = dropsReply; self.deniesCredential = deniesCredential
    }
    private func event(_ value: String) { lock.lock(); log.append(value); lock.unlock() }
    func setRequirement(_ requirement: String) { event("requirement:\(requirement)") }
    func resume() { event("resume") }
    func handshake(_ reply: @escaping @Sendable (Bool) -> Void) { event("handshake"); if !dropsReply { reply(handshakeAccepted) } }
    func read(allowInteraction: Bool, reply: @escaping @Sendable (String?, Bool) -> Void) { event(allowInteraction ? "authorize" : "read"); reply("synthetic-broker-token", !deniesCredential) }
    func write(_ token: String, reply: @escaping @Sendable (Bool) -> Void) { event("write"); reply(!deniesCredential) }
    func remove(_ reply: @escaping @Sendable (Bool) -> Void) { event("remove"); reply(!deniesCredential) }
    func invalidate() { event("invalidate") }
}

final class AppUpdateControllerTests: XCTestCase {
    @MainActor private func wait(_ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        let end = Date().addingTimeInterval(2)
        while !predicate() && Date() < end { try? await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertTrue(predicate(), "Synthetic update operation did not settle", file: file, line: line)
    }
    @MainActor private func syntheticConfiguration() -> (UpdateRepository, Data, Int)? {
        (try! UpdateRepository(owner: "synthetic", name: "clipboardline"), Data(repeating: 1, count: 32), 1)
    }
    @MainActor private func heartbeat() async {
        var delivered = false
        Task { @MainActor in delivered = true }
        await wait { delivered }
    }

    private func brokerInfo() -> [String: Any] {
        ["ClipboardLineCredentialBrokerService": UpdateCredentialBrokerConfiguration.service,
         "ClipboardLineCredentialBrokerCertificateSHA1": String(repeating: "a", count: 40),
         "ClipboardLineCredentialBrokerBinarySHA256": String(repeating: "b", count: 64),
         "ClipboardLineCredentialBrokerBundleSHA256": String(repeating: "c", count: 64)]
    }
    private func brokerConfiguration() throws -> UpdateCredentialBrokerConfiguration {
        try UpdateCredentialBrokerConfiguration(appURL: URL(fileURLWithPath: "/synthetic/ClipboardLine.app"), info: brokerInfo())
    }
    func testBrokerConfigurationRequiresExactServiceCertificateAndFrozenHashes() throws {
        let configuration = try brokerConfiguration()
        XCTAssertEqual(configuration.requirement, "identifier \"local.clipboardline.review.credentials.v2\" and certificate leaf = H\"\(String(repeating: "a", count: 40))\"")
        for key in brokerInfo().keys {
            var missing = brokerInfo(); missing.removeValue(forKey: key)
            XCTAssertThrowsError(try UpdateCredentialBrokerConfiguration(appURL: URL(fileURLWithPath: "/synthetic"), info: missing))
            missing[key] = key == "ClipboardLineCredentialBrokerService" ? "untrusted.helper" : "bad\" or anchor trusted"
            XCTAssertThrowsError(try UpdateCredentialBrokerConfiguration(appURL: URL(fileURLWithPath: "/synthetic"), info: missing))
        }
    }

    func testBrokerHandshakeAndPinnedRequirementPrecedeEveryCredentialMessage() async throws {
        let config = try brokerConfiguration()
        for operation in ["read", "authorize", "write", "remove"] {
            let connection = SyntheticBrokerTransport(), validation = UpdateCredentialCalls()
            let client = UpdateCredentialBrokerClient(configuration: { config }, validate: { _ in validation.call() }, connect: { _ in
                XCTAssertEqual(validation.count, 1); return connection
            })
            try await Task.detached {
                switch operation {
                case "read": XCTAssertEqual(try client.readToken(), "synthetic-broker-token")
                case "authorize": XCTAssertEqual(try client.readToken(allowInteraction: true), "synthetic-broker-token")
                case "write": try client.writeToken("synthetic-new-token")
                default: try client.deleteToken()
                }
            }.value
            XCTAssertEqual(connection.events, ["requirement:\(config.requirement)", "resume", "handshake", operation, "invalidate"])
        }
    }

    func testBrokerRejectsUnverifiedBundleAndFailedHandshakeBeforeSendingToken() async throws {
        let config = try brokerConfiguration(), factoryCalls = UpdateCredentialCalls()
        let invalid = UpdateCredentialBrokerClient(configuration: { config }, validate: { _ in throw UpdateCredentialBrokerError.identity },
            connect: { _ in factoryCalls.call(); return SyntheticBrokerTransport() })
        try await Task.detached { XCTAssertThrowsError(try invalid.writeToken("synthetic-must-not-leave-client")) }.value
        XCTAssertEqual(factoryCalls.count, 0)
        let connection = SyntheticBrokerTransport(handshakeAccepted: false)
        let rejected = UpdateCredentialBrokerClient(configuration: { config }, validate: { _ in }, connect: { _ in connection })
        try await Task.detached { XCTAssertThrowsError(try rejected.writeToken("synthetic-must-not-leave-client")) }.value
        XCTAssertFalse(connection.events.contains("write")); XCTAssertEqual(connection.events.last, "invalidate")
    }

    func testBrokerTimeoutDenialAndMainThreadCallsFailWithoutLeakingToken() async throws {
        let config = try brokerConfiguration()
        let silent = SyntheticBrokerTransport(dropsReply: true)
        let client = UpdateCredentialBrokerClient(timeout: 0.02, configuration: { config }, validate: { _ in }, connect: { _ in silent })
        try await Task.detached {
            XCTAssertThrowsError(try client.readToken()) { XCTAssertEqual($0 as? UpdateCredentialBrokerError, .timeout) }
        }.value
        XCTAssertEqual(silent.events.last, "invalidate"); XCTAssertFalse(silent.events.contains("read"))
        let denied = SyntheticBrokerTransport(deniesCredential: true)
        let deniedClient = UpdateCredentialBrokerClient(configuration: { config }, validate: { _ in }, connect: { _ in denied })
        try await Task.detached {
            XCTAssertThrowsError(try deniedClient.readToken()) { XCTAssertFalse($0.localizedDescription.contains("synthetic")) }
        }.value
        try await MainActor.run { XCTAssertThrowsError(try deniedClient.readToken()) }
    }

    func testFrozenBundleHashIncludesModesAndResourcesAndRejectsSymlinks() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("synthetic-broker-seal-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let binary = folder.appendingPathComponent("binary"), resource = folder.appendingPathComponent("Info.plist")
        try Data("synthetic binary".utf8).write(to: binary); try Data("synthetic metadata".utf8).write(to: resource)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        let initial = try UpdateCredentialBrokerClient.bundleHash(folder)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: binary.path)
        XCTAssertNotEqual(try UpdateCredentialBrokerClient.bundleHash(folder), initial)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        XCTAssertEqual(try UpdateCredentialBrokerClient.bundleHash(folder), initial)
        try Data("altered metadata".utf8).write(to: resource)
        XCTAssertNotEqual(try UpdateCredentialBrokerClient.bundleHash(folder), initial)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("alias"), withDestinationURL: binary)
        XCTAssertThrowsError(try UpdateCredentialBrokerClient.bundleHash(folder))
    }

    @MainActor func testSavedTokenAuthorizationIsExplicitAndRetriesCheckOnlyAfterSuccess() async {
        let authorization = UpdateCredentialGate(), reads = UpdateCredentialCalls(), fetches = UpdateCredentialCalls()
        defer { authorization.release() }
        let credentials = UpdateCredentialStore(load: { reads.call(); if authorization.completed == 0 { throw UpdateCredentialBrokerError.denied }; return "synthetic-authorized-token" },
            save: { _ in }, remove: {}, authorize: { try authorization.run(); return "synthetic-authorized-token" })
        let controller = AppUpdateController(credentials: credentials, configuration: syntheticConfiguration, fetch: { _, _, _, _ in fetches.call(); return Data("[]".utf8) })
        controller.manualCheck(); await wait { !controller.busy }
        XCTAssertTrue(controller.needsAuthorization); XCTAssertEqual(authorization.entered, 0); XCTAssertEqual(fetches.count, 0)
        controller.authorizeSavedToken(); await wait { authorization.entered == 1 }; await heartbeat()
        XCTAssertTrue(controller.busy); XCTAssertEqual(reads.count, 1); XCTAssertEqual(fetches.count, 0)
        controller.authorizeSavedToken(); XCTAssertEqual(authorization.entered, 1)
        authorization.release(); await wait { !controller.busy }
        XCTAssertFalse(controller.needsAuthorization); XCTAssertTrue(controller.hasSavedToken)
        XCTAssertEqual(reads.count, 2); XCTAssertEqual(fetches.count, 1); XCTAssertEqual(controller.status, L("You are up to date."))
    }

    @MainActor func testDeniedAuthorizationNeverRetriesNetworkOrPublishesSuccess() async {
        let calls = UpdateCredentialCalls()
        let credentials = UpdateCredentialStore(load: { calls.call(); return nil }, save: { _ in }, remove: {}, authorize: { throw UpdateCredentialBrokerError.denied })
        let controller = AppUpdateController(credentials: credentials, configuration: syntheticConfiguration, fetch: { _, _, _, _ in calls.call(); return Data("[]".utf8) })
        controller.authorizeSavedToken(); await wait { !controller.busy }
        XCTAssertNotNil(controller.error); XCTAssertTrue(controller.needsAuthorization); XCTAssertFalse(controller.hasSavedToken); XCTAssertEqual(calls.count, 0)
        let disabled = AppUpdateController(enabled: false, credentials: credentials, configuration: syntheticConfiguration)
        disabled.authorizeSavedToken(); await heartbeat()
        XCTAssertFalse(disabled.busy); XCTAssertNil(disabled.error); XCTAssertEqual(calls.count, 0)
    }

    @MainActor func testBlockedCredentialReadKeepsMainActorAliveAndCheckCompletesAfterRelease() async {
        let gate = UpdateCredentialGate(), unexpected = UpdateCredentialCalls(), fetched = UpdateCredentialCalls()
        defer { gate.release() }
        let credentials = UpdateCredentialStore(load: { try gate.run(); return "synthetic-read-token" },
            save: { _ in unexpected.call() }, remove: { unexpected.call() })
        let controller = AppUpdateController(credentials: credentials, configuration: syntheticConfiguration, fetch: { _, token, _, _ in
            fetched.call(); XCTAssertEqual(token, "synthetic-read-token"); return Data("[]".utf8)
        })
        controller.manualCheck(); XCTAssertTrue(controller.busy)
        await wait { gate.entered == 1 }; await heartbeat()
        XCTAssertTrue(controller.busy); XCTAssertEqual(gate.completed, 0); XCTAssertFalse(gate.ranOnMain)
        controller.manualCheck(); controller.saveToken("must-not-start-another-operation"); controller.disconnect()
        XCTAssertEqual(gate.entered, 1); XCTAssertEqual(unexpected.count, 0); XCTAssertEqual(fetched.count, 0)
        gate.release(); await wait { !controller.busy }
        XCTAssertNil(controller.error); XCTAssertTrue(controller.hasSavedToken)
        XCTAssertEqual(controller.status, L("You are up to date.")); XCTAssertEqual(fetched.count, 1)
    }

    @MainActor func testCredentialSaveAndRemoveRunOffMainAndPublishOnlyAfterCompletion() async {
        let save = UpdateCredentialGate(), remove = UpdateCredentialGate()
        defer { save.release(); remove.release() }
        let credentials = UpdateCredentialStore(load: { nil }, save: { _ in try save.run() }, remove: { try remove.run() })
        let controller = AppUpdateController(credentials: credentials)
        controller.saveToken("synthetic-save-token")
        await wait { save.entered == 1 }; await heartbeat()
        XCTAssertTrue(controller.busy); XCTAssertFalse(controller.hasSavedToken); XCTAssertFalse(save.ranOnMain)
        controller.disconnect(); XCTAssertEqual(remove.entered, 0)
        save.release(); await wait { !controller.busy }
        XCTAssertTrue(controller.hasSavedToken); XCTAssertNil(controller.error)
        XCTAssertEqual(controller.status, L("GitHub token saved in Keychain."))
        controller.disconnect(); await wait { remove.entered == 1 }; await heartbeat()
        XCTAssertTrue(controller.busy); XCTAssertTrue(controller.hasSavedToken); XCTAssertFalse(remove.ranOnMain)
        remove.release(); await wait { !controller.busy }
        XCTAssertFalse(controller.hasSavedToken); XCTAssertNil(controller.error)
        XCTAssertEqual(controller.status, L("GitHub token removed from this Mac."))
    }

    @MainActor func testCredentialFailuresResetBusyAndDoNotPublishFalseSuccess() async {
        let fetched = UpdateCredentialCalls()
        let credentials = UpdateCredentialStore(load: { throw SyntheticCredentialError.denied },
            save: { _ in throw SyntheticCredentialError.denied }, remove: { throw SyntheticCredentialError.denied })
        let controller = AppUpdateController(credentials: credentials, configuration: syntheticConfiguration, fetch: { _, _, _, _ in
            fetched.call(); return Data("[]".utf8)
        })
        let initial = controller.status
        controller.saveToken("synthetic-denied-token"); await wait { !controller.busy }
        XCTAssertNotNil(controller.error); XCTAssertFalse(controller.hasSavedToken); XCTAssertEqual(controller.status, initial)
        controller.disconnect(); await wait { !controller.busy }
        XCTAssertNotNil(controller.error); XCTAssertFalse(controller.hasSavedToken); XCTAssertEqual(controller.status, initial)
        controller.manualCheck(); await wait { !controller.busy }
        XCTAssertNotNil(controller.error); XCTAssertFalse(controller.needsAuthorization); XCTAssertNil(controller.available)
        XCTAssertEqual(controller.status, L("Update check could not be completed.")); XCTAssertEqual(fetched.count, 0)
    }

    @MainActor func testTimedOutCredentialCannotQueueWritesOrPublishLateCheckResults() async {
        let gate = UpdateCredentialGate(), writes = UpdateCredentialCalls(), fetches = UpdateCredentialCalls()
        defer { gate.release() }
        let credentials = UpdateCredentialStore(timeout: 0.05, load: { try gate.run(blockFirstOnly: true); return "synthetic-timeout-token" },
            save: { _ in writes.call() }, remove: { writes.call() })
        let controller = AppUpdateController(credentials: credentials, configuration: syntheticConfiguration, fetch: { _, _, _, _ in
            fetches.call(); return Data("[]".utf8)
        })
        controller.manualCheck(); await wait { gate.entered == 1 }; await heartbeat(); await wait { !controller.busy }
        XCTAssertEqual(gate.completed, 0); XCTAssertNotNil(controller.error); XCTAssertNil(controller.available)
        let failure = controller.status
        controller.saveToken("synthetic-must-not-queue-write"); await wait { !controller.busy }
        controller.disconnect(); await wait { !controller.busy }
        XCTAssertNotNil(controller.error); XCTAssertEqual(writes.count, 0)
        gate.release(); await wait { gate.completed == 1 }
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(controller.status, failure); XCTAssertEqual(fetches.count, 0); XCTAssertEqual(writes.count, 0)
        controller.manualCheck(); await wait { !controller.busy }
        XCTAssertEqual(controller.status, L("You are up to date.")); XCTAssertNil(controller.error); XCTAssertEqual(fetches.count, 1)
    }

    @MainActor func testDisabledControllerNeverTouchesInjectedCredentialsConfigurationOrNetwork() async {
        let calls = UpdateCredentialCalls()
        let credentials = UpdateCredentialStore(load: { calls.call(); return nil }, save: { _ in calls.call() }, remove: { calls.call() })
        let controller = AppUpdateController(enabled: false, credentials: credentials, configuration: { calls.call(); return self.syntheticConfiguration() },
            fetch: { _, _, _, _ in calls.call(); return Data("[]".utf8) })
        let original = controller.status
        XCTAssertFalse(controller.isConfigured)
        controller.manualCheck(); controller.downloadAndInstall(); controller.saveToken("synthetic-disabled-token"); controller.disconnect()
        await heartbeat()
        XCTAssertEqual(calls.count, 0); XCTAssertFalse(controller.busy); XCTAssertNil(controller.error)
        XCTAssertFalse(controller.hasSavedToken); XCTAssertEqual(controller.status, original)
    }

    @MainActor func testInvalidTokensAreRejectedBeforeStartingCredentialWorker() async {
        let calls = UpdateCredentialCalls()
        let credentials = UpdateCredentialStore(load: { calls.call(); return nil }, save: { _ in calls.call() }, remove: { calls.call() })
        let controller = AppUpdateController(credentials: credentials)
        for value in ["short", String(repeating: "x", count: 513), "invalid token spaces", "invalid-token-✓"] {
            controller.saveToken(value)
            XCTAssertFalse(controller.busy); XCTAssertNotNil(controller.error); XCTAssertFalse(controller.hasSavedToken)
        }
        await heartbeat(); XCTAssertEqual(calls.count, 0)
    }

    func testEveryAllowedRedirectDropsAuthorizationAndCookies() throws {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let guardDelegate = UpdateRedirectGuard()
        let source = URL(string: "https://api.github.com/repos/example/clipboardline/releases/assets/17")!
        let task = session.dataTask(with: source) // Never resumed: no network I/O.
        let response = HTTPURLResponse(url: source, statusCode: 302, httpVersion: nil, headerFields: nil)!
        for host in ["github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com"] {
            var request = URLRequest(url: URL(string: "https://\(host)/signed-asset?signature=synthetic")!)
            request.setValue("Bearer synthetic-test-token", forHTTPHeaderField: "Authorization")
            request.setValue("synthetic-cookie", forHTTPHeaderField: "Cookie")
            var redirected: URLRequest?
            guardDelegate.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: request) { redirected = $0 }
            let clean = try XCTUnwrap(redirected)
            XCTAssertEqual(clean.url, request.url)
            XCTAssertNil(clean.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(clean.value(forHTTPHeaderField: "Cookie"))
        }
        task.cancel()
    }

    func testRedirectsRejectInsecureUnexpectedAndCredentialBearingDestinations() {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let guardDelegate = UpdateRedirectGuard()
        let source = URL(string: "https://api.github.com/repos/example/clipboardline/releases/assets/17")!
        let task = session.dataTask(with: source) // Never resumed.
        let response = HTTPURLResponse(url: source, statusCode: 302, httpVersion: nil, headerFields: nil)!
        for value in ["http://github.com/asset", "https://github.com.evil.example/asset", "https://evil.example/asset",
                      "https://user:password@github.com/asset", "https://github.com:8443/asset", "https://api.github.com/other-repository"] {
            var called = false
            guardDelegate.urlSession(session, task: task, willPerformHTTPRedirection: response,
                                     newRequest: URLRequest(url: URL(string: value)!)) { request in
                called = true; XCTAssertNil(request, value)
            }
            XCTAssertTrue(called)
        }
        task.cancel()
    }

    func testStreamingDownloadCancelsWhenWrittenOrDeclaredBytesExceedSignedSize() {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        for (written, declared): (Int64, Int64) in [(11, 10), (1, 11)] {
            let progress = UpdateProgressCapture()
            let observer = UpdateDownloadObserver(limit: 10, progress: { progress.record($0) })
            let task = session.downloadTask(with: URL(string: "https://release-assets.githubusercontent.com/synthetic")!) // Never resumed.
            observer.urlSession(session, downloadTask: task, didWriteData: written, totalBytesWritten: written, totalBytesExpectedToWrite: declared)
            XCTAssertTrue(task.state == .canceling || task.state == .completed)
            XCTAssertTrue(progress.values.isEmpty)
        }
    }

    func testStreamingDownloadAllowsUnknownLengthWithinSignedBoundAndReportsProgress() {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let progress = UpdateProgressCapture()
        let observer = UpdateDownloadObserver(limit: 10, progress: { progress.record($0) })
        let task = session.downloadTask(with: URL(string: "https://release-assets.githubusercontent.com/synthetic")!) // Never resumed.
        observer.urlSession(session, downloadTask: task, didWriteData: 5, totalBytesWritten: 5, totalBytesExpectedToWrite: -1)
        XCTAssertEqual(task.state, .suspended)
        XCTAssertEqual(progress.values, [0.5])
        task.cancel()
    }

    @MainActor func testIsolatedHarnessCannotCheckInstallOrChangeCredentials() {
        let controller = AppUpdateController(enabled: false)
        XCTAssertFalse(controller.isConfigured)
        let original = controller.status
        controller.manualCheck()
        controller.downloadAndInstall()
        controller.saveToken("synthetic-token-that-must-not-be-saved")
        controller.disconnect()
        XCTAssertEqual(controller.status, original)
        XCTAssertNil(controller.error)
        XCTAssertNil(controller.available)
        XCTAssertFalse(controller.busy)
        XCTAssertFalse(controller.hasSavedToken)
    }
}
#endif
