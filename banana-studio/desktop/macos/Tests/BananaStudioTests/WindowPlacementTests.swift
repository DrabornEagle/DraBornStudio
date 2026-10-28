import XCTest
import CoreGraphics
@testable import BananaStudio

final class WindowPlacementTests: XCTestCase {
    func testNormalFrameSurvivesRelaunchInAnIsolatedPreferenceFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BananaStudio-window-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WindowPlacementStore(url: directory.appendingPathComponent("window-placement.json"))
        XCTAssertNil(store.load())
        let original = CGRect(x: 30, y: 50, width: 900, height: 650)
        store.save(original)
        XCTAssertEqual(WindowPlacementStore(url: store.url).load(), original)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: store.url.path)[.posixPermissions] as? Int, 0o600)
        try Data("invalid json".utf8).write(to: store.url)
        XCTAssertNil(store.load())
        try Data(repeating: 32, count: 3000).write(to: store.url)
        XCTAssertNil(store.load())
    }
    func testRemovedMonitorAndSmallerScreensAlwaysKeepTheWindowReachable() {
        let primary = CGRect(x: 0, y: 40, width: 1280, height: 720)
        XCTAssertEqual(WindowPlacement.constrain(CGRect(x: 5000, y: 5000, width: 1400, height: 900), to: [primary]), primary)
        XCTAssertEqual(WindowPlacement.constrain(CGRect(x: -5000, y: -5000, width: 50, height: 50), to: [primary]), CGRect(x: 0, y: 40, width: 760, height: 560))
        let small = CGRect(x: 0, y: 0, width: 600, height: 400)
        XCTAssertEqual(WindowPlacement.constrain(primary, to: [small]), small)
    }
    func testConnectedSecondaryScreenIsPreservedAndPartialFramesAreClamped() {
        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let secondary = CGRect(x: -1600, y: 0, width: 1600, height: 1000)
        let frame = CGRect(x: -1500, y: 50, width: 900, height: 650)
        XCTAssertEqual(WindowPlacement.constrain(frame, to: [primary, secondary]), frame)
        XCTAssertEqual(WindowPlacement.constrain(CGRect(x: -1700, y: 800, width: 900, height: 650), to: [primary, secondary]), CGRect(x: -1600, y: 350, width: 900, height: 650))
    }
    func testUnknownSchemaAndInvalidGeometryAreRejected() throws {
        for json in ["{\"version\":2,\"x\":0,\"y\":0,\"width\":900,\"height\":650}",
                     "{\"version\":1,\"x\":0,\"y\":0,\"width\":-1,\"height\":650}",
                     "{\"version\":1,\"x\":100001,\"y\":0,\"width\":900,\"height\":650}"] {
            let value = try JSONDecoder().decode(WindowPlacement.self, from: Data(json.utf8))
            XCTAssertNil(value.frame)
        }
    }
}
