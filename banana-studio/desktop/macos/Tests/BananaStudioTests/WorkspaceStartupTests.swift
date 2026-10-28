import XCTest
@testable import BananaStudio

final class WorkspaceStartupTests: XCTestCase {
    func testTimeoutFailsOnceAndIgnoresALateReadyOrFailure() {
        let expired = expectation(description: "startup expires once")
        let startup = WorkspaceStartup(timeout: 0.01) { expired.fulfill() }
        wait(for: [expired], timeout: 1)
        XCTAssertEqual(startup.state, .failed)
        XCTAssertFalse(startup.ready()); XCTAssertFalse(startup.fail())
    }
    func testReadyCancelsDeadlineAndRuntimeFailureIsReportedOnce() {
        let expired = expectation(description: "no timeout after readiness"); expired.isInverted = true
        let startup = WorkspaceStartup(timeout: 0.01) { expired.fulfill() }
        XCTAssertTrue(startup.ready()); XCTAssertFalse(startup.ready())
        wait(for: [expired], timeout: 0.04)
        XCTAssertEqual(startup.state, .ready)
        XCTAssertTrue(startup.fail()); XCTAssertFalse(startup.fail())
    }
    func testStoppingCancelsDeadlineAndLateProcessEvents() {
        let expired = expectation(description: "no timeout after shutdown"); expired.isInverted = true
        let startup = WorkspaceStartup(timeout: 0.01) { expired.fulfill() }
        startup.stop()
        wait(for: [expired], timeout: 0.04)
        XCTAssertEqual(startup.state, .stopped)
        XCTAssertFalse(startup.ready()); XCTAssertFalse(startup.fail())
    }
}
