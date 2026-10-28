import AppKit
import Carbon
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

@MainActor final class ShelfSearchShortcutTests: HistoryTestCase {
    private func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = [], _ text: String = "") -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                        characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
    }

    func testShelfSearchDefaultKeepsTakeDownAndLibrarySearchIndependent() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let bindings = KeyboardBindings(defaults: f.defaults)
        XCTAssertEqual(bindings.action(for: key(1, .shift, "s"), in: .line), .searchShelf)
        XCTAssertEqual(bindings.action(for: key(1, [], "s"), in: .line), .removeFromLine)
        XCTAssertEqual(bindings.action(for: key(3, .command, "f"), in: .library), .search)
        for context in KeyboardContext.allCases where context != .line {
            XCTAssertNil(bindings.action(for: key(1, .shift, "s"), in: context))
        }
        XCTAssertEqual(KeyboardAction.searchShelf.contexts, [.line])
        XCTAssertEqual(KeyboardAction.searchShelf.settingsGroup, 0)
        XCTAssertTrue(bindings.hint([.searchShelf]).contains("⇧S"))
    }

    func testShelfSearchRemappingPersistsAndCanBeDisabledAndReset() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        let bindings = KeyboardBindings(defaults: f.defaults)
        let other = KeyboardBindings(defaults: f.defaults)
        let custom = KeyShortcut(keyCode: 40, modifiers: shiftKey, keyLabel: "K")
        try bindings.set([custom], for: .searchShelf)
        XCTAssertNil(other.action(for: key(1, .shift, "s"), in: .line))
        XCTAssertEqual(other.action(for: key(40, .shift, "k"), in: .line), .searchShelf)
        XCTAssertEqual(other.shortcuts(.searchShelf), [custom])
        try bindings.set([], for: .searchShelf)
        XCTAssertNil(other.action(for: key(40, .shift, "k"), in: .line))
        try bindings.reset(.searchShelf)
        XCTAssertEqual(other.action(for: key(1, .shift, "s"), in: .line), .searchShelf)
        XCTAssertEqual(other.action(for: key(1, [], "s"), in: .line), .removeFromLine)
    }

    func testShelfSearchRespectsExistingCustomBindingsAndContextConflicts() throws {
        let f = try SyntheticFixture(); defer { f.cleanup() }
        // An older version could already have stored Shift-S for another action.
        let stored = [KeyboardAction.library.rawValue: [KeyShortcut(keyCode: 1, modifiers: shiftKey, keyLabel: "S")]]
        f.defaults.set(try JSONEncoder().encode(stored), forKey: "contextKeyboardBindingsV1")
        let bindings = KeyboardBindings(defaults: f.defaults)
        XCTAssertEqual(bindings.action(for: key(1, .shift, "s"), in: .line), .library)
        var rejected = false
        do { try bindings.set([KeyShortcut(keyCode: 1, modifiers: 0, keyLabel: "S")], for: .searchShelf) }
        catch { rejected = true }
        XCTAssertTrue(rejected)
        // Command-F can be shared because Library and shelf search do not share a context.
        try bindings.set([KeyShortcut(keyCode: 3, modifiers: cmdKey, keyLabel: "F")], for: .searchShelf)
        XCTAssertEqual(bindings.action(for: key(3, .command, "f"), in: .line), .searchShelf)
        XCTAssertEqual(bindings.action(for: key(3, .command, "f"), in: .library), .search)
        XCTAssertNil(bindings.action(for: key(3, .command, "f"), in: .textPreview))
    }
}
