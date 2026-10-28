import AppKit
import CryptoKit
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

/// Executes the portable Library contract through the shipping model, Store and
/// keyboard bindings. This intentionally proves model state rather than native
/// first-responder placement; native pane/editor tests cover physical focus.
@MainActor final class LibraryKeyboardContractTests: HistoryTestCase {
    private var checkout: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
    private func required<T>(_ value: Any?, _ type: T.Type = T.self) throws -> T {
        guard let result = value as? T else { throw CocoaError(.coderReadCorrupt) }
        return result
    }
    private func waitForModel(_ model: LibraryModel, step: String) {
        let deadline = Date().addingTimeInterval(5)
        while (model.loading || model.pendingPageCount > 0), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
        XCTAssertFalse(model.loading, "Library query did not finish: \(step)")
        XCTAssertEqual(model.pendingPageCount, 0, "Library summaries did not finish: \(step)")
    }
    private func revision() throws -> String {
        if let value = ProcessInfo.processInfo.environment["GITHUB_SHA"] { return value }
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["rev-parse", "HEAD"]; process.currentDirectoryURL = checkout
        let output = Pipe(); process.standardOutput = output; process.standardError = Pipe()
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileReadUnknown) }
        return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func event(_ step: [String: Any]) throws -> NSEvent {
        let code = try required(step["code"], String.self)
        let keys: [String: (UInt16, String)] = [
            "ArrowLeft": (123, ""), "ArrowRight": (124, ""), "ArrowDown": (125, ""), "ArrowUp": (126, ""),
            "KeyA": (0, "a"), "KeyF": (3, "f"), "KeyJ": (38, "j"), "KeyP": (35, "p"), "KeyS": (1, "s"), "KeyZ": (6, "z"),
            "Digit0": (29, "0"), "Digit1": (18, "1"), "Digit2": (19, "2"), "Digit3": (20, "3"),
            "Backspace": (51, "\u{7f}"), "Delete": (117, "\u{f728}"), "Enter": (36, "\r"),
            "Space": (49, " "), "Escape": (53, "\u{1b}"), "F6": (97, ""), "Tab": (48, "\t")
        ]
        let key = try XCTUnwrap(keys[code]); var flags = NSEvent.ModifierFlags()
        for modifier in try required(step["modifiers"], [String].self) {
            switch modifier {
            case "primary": flags.insert(.command)
            case "alt": flags.insert(.option)
            case "control": flags.insert(.control)
            case "shift": flags.insert(.shift)
            default: throw CocoaError(.coderReadCorrupt)
            }
        }
        return try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, characters: key.1, charactersIgnoringModifiers: key.1, isARepeat: false, keyCode: key.0))
    }
    private func snapshot(_ model: LibraryModel, aliases: [UUID: String], order: [UUID]) throws -> [String: Any] {
        let scope: String
        switch model.query.scope {
        case .saved: scope = "saved"
        case .trash: scope = "trash"
        default: throw CocoaError(.coderReadCorrupt)
        }
        let records = try order.compactMap { try model.store.item($0) }
        return [
            "focused": model.focusedID.map { aliases[$0] ?? "unexpected-id" } as Any? ?? NSNull(),
            "selected": model.ids.filter { model.selectedIDs.contains($0) }.map { aliases[$0] ?? "unexpected-id" },
            "visible": model.ids.map { aliases[$0] ?? "unexpected-id" },
            "scope": scope, "kind": model.query.kind?.rawValue ?? "all", "search": model.query.search, "list": model.listMode,
            "trashed": records.filter { $0.deletedAt != nil }.map { aliases[$0.id] ?? "unexpected-id" },
            "pinned": records.filter(\.favorite).map { aliases[$0.id] ?? "unexpected-id" },
            "pinnedOnly": model.showingPinnedOnly
        ]
    }
    func testSharedLibraryKeyboardContract() throws {
        let data = try Data(contentsOf: checkout.appendingPathComponent("contracts/library-keyboard.json"))
        let contract = try required(JSONSerialization.jsonObject(with: data), [String: Any].self)
        let values = try required(contract["records"], [[String: Any]].self)
        let views = try required(contract["views"], [String: [String]].self)
        let scenarios = try required(contract["scenarios"], [[String: Any]].self)
        var observations = [[String: Any]](), errors = [String]()
        for scenario in scenarios {
            let scenarioID = try required(scenario["id"], String.self)
            let fixture = try SyntheticFixture(); defer { fixture.cleanup() }
            fixture.date = Date(timeIntervalSince1970: 1_800_000_000)
            let store = try LibraryStore(defaults: fixture.defaults, inbox: fixture.inbox, now: { fixture.date }, moveToTrash: fixtureTrash(fixture.folder))
            var aliases = [UUID: String](), identities = [String: UUID]()
            // Contract records are newest first. The real Store sees separate
            // fixed capture instants and retains each synthetic item normally.
            for value in values.reversed() {
                let alias = try required(value["id"], String.self), kind = try required(value["kind"], String.self)
                let record: LibraryRecord
                switch kind {
                case "image": record = try store.captureImage(fixture.image(name: "Library-\(alias).png"))
                case "text": record = try XCTUnwrap(store.captureText(try required(value["text"], String.self)))
                case "link": record = try store.captureLink(try XCTUnwrap(URL(string: "https://example.com/library-contract/\(alias)")))
                default: throw CocoaError(.coderReadCorrupt)
                }
                let title = try required(value["title"], String.self), pinned = try required(value["pinned"], Bool.self), onShelf = try required(value["onShelf"], Bool.self)
                try store.retain([record.id])
                try store.update(record.id) { $0.title = title; $0.favorite = pinned; $0.onShelf = onShelf }
                aliases[record.id] = alias; identities[alias] = record.id; fixture.date += 1
            }
            let order = try values.map { try XCTUnwrap(identities[try required($0["id"], String.self)]) }
            let board = NSPasteboard(name: .init("library-keyboard-contract-\(UUID())"))
            let model = LibraryModel(store: store, copyPasteboard: board)
            defer { _ = model.suspendUpdates(); board.releaseGlobally() }
            model.columns = try required(scenario["columns"], Int.self)
            // This acknowledges callback intent only. Native first responder
            // placement is deliberately absent from these report observations.
            model.onContentFocus = {}
            if let mode = scenario["searchMode"] as? String { model.setSearchMode(try XCTUnwrap(LibraryQuery.SearchMode(rawValue: mode))) }
            waitForModel(model, step: "\(scenarioID):seed")
            for (index, step) in try required(scenario["steps"], [[String: Any]].self).enumerated() {
                let label = "\(scenarioID):\(index)"
                switch try required(step["action"], String.self) {
                case "open": model.resumeUpdates(); XCTAssertTrue(model.focusContent())
                case "close": XCTAssertTrue(model.suspendUpdates())
                case "key": _ = model.handleKey(try event(step), editing: try required(step["editing"], Bool.self))
                case "mode": model.listMode = try required(step["list"], Bool.self)
                case "select": XCTAssertTrue(model.select(try XCTUnwrap(identities[try required(step["id"], String.self)])))
                case "remap":
                    let action = try XCTUnwrap(KeyboardAction(rawValue: try required(step["binding"], String.self)))
                    if step["key"] is NSNull { try model.keyboardBindings.reset(action) }
                    else {
                        let key = try required(step["key"], String.self)
                        guard key.isEmpty || key == "KeyJ" else { throw CocoaError(.coderReadCorrupt) }
                        try model.keyboardBindings.set(key.isEmpty ? [] : [KeyShortcut(keyCode: 38, modifiers: 0, keyLabel: "J")], for: action)
                    }
                case "searchHandoff":
                    model.search = try required(step["value"], String.self)
                    // Entry happens in the SAME task, before the 180 ms search
                    // debounce. Await only the resulting actual Store query.
                    XCTAssertTrue(model.focusContent())
                case "scope":
                    guard try required(step["scope"], String.self) == "trash" else { throw CocoaError(.coderReadCorrupt) }
                    model.changeScope(.trash); XCTAssertTrue(model.focusContent())
                default: throw CocoaError(.coderReadCorrupt)
                }
                waitForModel(model, step: label)
                let actual = try snapshot(model, aliases: aliases, order: order)
                var expected = try required(step["expect"], [String: Any].self)
                expected["visible"] = try XCTUnwrap(views[try required(expected["visible"], String.self)])
                observations.append(["scenarioId": scenarioID, "step": index, "actual": actual])
                let matches = NSDictionary(dictionary: actual).isEqual(to: expected)
                if !matches { errors.append(label) }
                XCTAssertTrue(matches, "Shared Library contract \(label): expected \(expected), received \(actual)")
            }
        }
        let report: [String: Any] = [
            "schemaVersion": 1, "contractId": try required(contract["contractId"], String.self),
            "contractSHA256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            "platform": "macos", "hostPlatform": "darwin", "mode": "model", "sourceRevision": try revision(),
            "observations": observations, "errors": errors
        ]
        if let destination = ProcessInfo.processInfo.environment["CLIPBOARDLINE_LIBRARY_KEYBOARD_REPORT"], !destination.isEmpty {
            let path = URL(fileURLWithPath: destination, relativeTo: checkout)
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: path, options: .atomic)
        }
        // Existing CI uploads its shelf report as a single file. Keep the
        // additional, independently hashed contract in that same authenticated
        // artifact without expanding workflow or credential permissions.
        if ProcessInfo.processInfo.environment["CLIPBOARDLINE_LIBRARY_KEYBOARD_REPORT"] == nil,
           let destination = ProcessInfo.processInfo.environment["CLIPBOARDLINE_PARITY_REPORT"], !destination.isEmpty {
            let path = URL(fileURLWithPath: destination, relativeTo: checkout)
            var envelope = try required(JSONSerialization.jsonObject(with: Data(contentsOf: path)), [String: Any].self)
            envelope["libraryKeyboard"] = report
            try JSONSerialization.data(withJSONObject: envelope, options: [.prettyPrinted, .sortedKeys]).write(to: path, options: .atomic)
        }
        XCTAssertTrue(!observations.isEmpty && errors.isEmpty)
    }
}
