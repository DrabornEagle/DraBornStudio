import AppKit
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

@MainActor final class MainWindowPasteFocusTests: HistoryTestCase {
    private var boundaries: [(NSEvent, Bool, (() -> Void)?) -> Void] {
        [LibraryNativeWindow.prepareForMouseKeyFocus, SettingsNativeWindow.prepareForMouseKeyFocus]
    }
    private func mouse(_ type: NSEvent.EventType) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    }
    private var command: NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: 0, context: nil, characters: "k", charactersIgnoringModifiers: "k", isARepeat: false, keyCode: 40)!
    }

    func testNativeMainWindowMouseBoundaryOnlyCapturesOnFreshLeftClick() throws {
        for prepare in boundaries {
            var captures = 0
            let capture = { captures += 1 }
            prepare(command, false, capture)
            prepare(mouse(.leftMouseUp), false, capture)
            prepare(mouse(.rightMouseDown), false, capture)
            prepare(mouse(.leftMouseDown), true, capture)
            XCTAssertEqual(captures, 0)
            prepare(mouse(.leftMouseDown), false, capture)
            XCTAssertEqual(captures, 1)
        }
    }

    func testMainWindowControllersForwardEarlyCaptureWithoutDisplayingOrChangingKeyDispatch() throws {
        _ = NSApplication.shared
        let fixture = try SyntheticFixture(); defer { fixture.cleanup() }
        let store = try LibraryStore(defaults: fixture.defaults, inbox: fixture.inbox)
        let line = Line(defaults: fixture.defaults, inbox: fixture.inbox, breeze: false, library: store)
        let library = LibraryWindowController(store: store, line: line)
        let settings = SettingsWindowController(model: SettingsModel(line: line, allowsSystemChanges: false))
        let libraryWindow = try XCTUnwrap(library.window as? LibraryNativeWindow)
        let settingsWindow = try XCTUnwrap(settings.window as? SettingsNativeWindow)
        defer { libraryWindow.contentViewController = nil; settingsWindow.contentView = nil }
        XCTAssertFalse(libraryWindow.isVisible); XCTAssertFalse(settingsWindow.isVisible)

        var order = [String](), previewCaptures = 0
        library.onBeforeMouseKeyFocus = { order.append("library capture") }
        library.onBeforePreviewMouseKeyFocus = { previewCaptures += 1 }
        settings.onBeforeMouseKeyFocus = { order.append("settings capture") }
        LibraryNativeWindow.prepareForMouseKeyFocus(mouse(.leftMouseDown), isKeyWindow: false, onEntry: libraryWindow.onBeforeMouseKeyFocus)
        order.append("library action")
        SettingsNativeWindow.prepareForMouseKeyFocus(mouse(.leftMouseDown), isKeyWindow: false, onEntry: settingsWindow.onBeforeMouseKeyFocus)
        order.append("settings action")
        XCTAssertEqual(order, ["library capture", "library action", "settings capture", "settings action"])
        XCTAssertEqual(previewCaptures, 0, "The existing preview callback stays independent")

        // Callback assignment after construction must reach the window too.
        library.onBeforeMouseKeyFocus = { order.append("replacement") }
        LibraryNativeWindow.prepareForMouseKeyFocus(mouse(.leftMouseDown), isKeyWindow: false, onEntry: libraryWindow.onBeforeMouseKeyFocus)
        XCTAssertEqual(order.last, "replacement")
        var keys = 0
        libraryWindow.onKey = { _, _ in keys += 1; return true }
        settingsWindow.onCommandKey = { _ in keys += 1; return true }
        XCTAssertTrue(libraryWindow.performKeyEquivalent(with: command))
        XCTAssertTrue(settingsWindow.performKeyEquivalent(with: command))
        XCTAssertEqual(keys, 2); XCTAssertEqual(order.count, 5)
        XCTAssertFalse(libraryWindow.isVisible); XCTAssertFalse(settingsWindow.isVisible)
    }

    func testMainWindowMouseEntryPreservesOwnHandoffsAndRefreshesLaterExternalField() throws {
        for prepare in boundaries {
            let data = try SyntheticFixture(); defer { data.cleanup() }
            let line = data.line()
            let first = NSObject(), latest = NSObject()
            var current: DirectPasteCoordinator.FocusedField? = .init(identity: first, editable: true, secure: false)
            var ownFocus = false, reads = 0, writes = 0, events = [pid_t]()
            let environment = DirectPasteCoordinator.Environment(ownPID: 900, trusted: { true }, frontmostPID: { 101 },
                running: { $0 == 101 }, focusedField: { _ in reads += 1; return current },
                sameField: { $0.identity === $1.identity }, activate: { $0 == 101 },
                write: { _ in writes += 1; return true }, sendPaste: { events.append($0); return true },
                pause: { await Task.yield() }, ownsKeyboardFocus: { ownFocus })
            let service = DirectPasteCoordinator(environment: environment)
            let app = AppDelegate(line: line, watchesFiles: false, directPaste: service, ownsKeyboardFocus: { ownFocus })
            app.capturePasteTarget()
            XCTAssertEqual(reads, 1)
            ownFocus = true
            current = .init(identity: NSObject(), editable: false, secure: false)
            prepare(mouse(.leftMouseDown), false, app.capturePasteTarget)
            XCTAssertEqual(reads, 1, "A different own window must not replace the captured external editor")

            ownFocus = false
            current = .init(identity: latest, editable: true, secure: false)
            prepare(mouse(.leftMouseDown), false, app.capturePasteTarget)
            XCTAssertEqual(reads, 2, "A later external entry must capture its latest field")
            ownFocus = true
            current = nil
            var result: DirectPasteCoordinator.Outcome?
            service.paste(items: ClipboardTransfer.textItems(["Synthetic main-window target"]), dismiss: {
                ownFocus = false; current = .init(identity: latest, editable: true, secure: false)
            }) { result = $0 }
            let deadline = Date().addingTimeInterval(5)
            while result == nil, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
            XCTAssertEqual(result, .pasted); XCTAssertEqual(writes, 1); XCTAssertEqual(events, [101])

            // A fresh entry without a valid external field must not reuse it.
            ownFocus = false; current = nil
            prepare(mouse(.leftMouseDown), false, app.capturePasteTarget)
            service.paste(items: ClipboardTransfer.textItems(["Must not send"]), dismiss: {}) { result = $0 }
            XCTAssertEqual(result, .noTarget); XCTAssertEqual(writes, 1); XCTAssertEqual(events, [101])
        }
    }
}
