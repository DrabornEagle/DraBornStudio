#if !STANDALONE_TESTS
import XCTest
import UserNotifications
@testable import Tendedero

final class UpdateNotificationTests: XCTestCase {
    @MainActor func testNotificationContainsOnlyVersionAndBuildWithoutCredentialOrDownloadURL() {
        let request = UpdateNotifications.request(version: "1.5.0-review.32", build: 40)
        XCTAssertEqual(request.identifier, "clipboardline.update.40")
        XCTAssertEqual(request.content.categoryIdentifier, UpdateNotifications.category)
        XCTAssertEqual(Set(request.content.userInfo.keys.compactMap { $0 as? String }), ["build"])
        XCTAssertEqual(request.content.userInfo["build"] as? Int, 40)
        XCTAssertTrue(request.content.body.contains("1.5.0-review.32"))
        XCTAssertNil(request.trigger)
        XCTAssertNil(request.content.sound)
    }

    func testOnlyMatchingUpdateNotificationActionsReachTheController() {
        let category = UpdateNotifications.category, id = "clipboardline.update.40"
        XCTAssertEqual(UpdateNotifications.response(identifier: id, category: category,
            action: UNNotificationDefaultActionIdentifier, build: 40), .show(40))
        XCTAssertEqual(UpdateNotifications.response(identifier: id, category: category,
            action: UpdateNotifications.installAction, build: 40), .install(40))
        for action in [UNNotificationDismissActionIdentifier, "unknown", ""] {
            XCTAssertNil(UpdateNotifications.response(identifier: id, category: category, action: action, build: 40))
        }
        XCTAssertNil(UpdateNotifications.response(identifier: id, category: "unrelated", action: UpdateNotifications.installAction, build: 40))
        XCTAssertNil(UpdateNotifications.response(identifier: "clipboardline.update.41", category: category,
            action: UpdateNotifications.installAction, build: 40))
        for build: Any? in [nil, "40", true, -1, 0, 1.5, Double.infinity, Double.nan] {
            XCTAssertNil(UpdateNotifications.response(identifier: id, category: category,
                action: UpdateNotifications.installAction, build: build))
        }
    }
}
#endif
