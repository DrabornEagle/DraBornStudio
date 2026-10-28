import AppKit
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

@MainActor final class CommandPaletteTests: HistoryTestCase {
    private func key(_ code: UInt16, flags: NSEvent.ModifierFlags = [], text: String = "") -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text,
            isARepeat: false, keyCode: code)!
    }
    private func commands() -> [CommandPalette.Command] {
        [.init(id: "search", title: "Search shelves", subtitle: "Text, links and image OCR", keyHint: "⇧S", systemImage: "magnifyingglass"),
         .init(id: "unavailable", title: "Copy image text", subtitle: "Select an image first", isEnabled: false),
         .init(id: "folder", title: "Add to fólder", subtitle: "Organize the selected item", keyHint: "⇧P", systemImage: "folder"),
         .init(id: "settings", title: "Settings", subtitle: "Shortcuts and appearance", systemImage: "gearshape")]
    }
    private func clean(_ palette: CommandPalette) {
        palette.onClose = nil; palette.window.makeFirstResponder(nil)
        palette.window.close(); palette.window.contentView = nil
    }

    func testCommandPaletteFiltersTitleAndSubtitleTokensWithoutExposingInternalIDs() throws {
        _ = NSApplication.shared
        let palette = CommandPalette(commands: commands(), onExecute: { _ in })
        defer { clean(palette) }
        XCTAssertEqual(palette.visibleCommands.map(\.id), ["search", "unavailable", "folder", "settings"])
        XCTAssertEqual(palette.selectedCommandID, "search")
        palette.updateQuery("  FOLDER  organize ")
        XCTAssertEqual(palette.visibleCommands.map(\.id), ["folder"])
        XCTAssertEqual(palette.selectedCommandID, "folder", "All whitespace-separated query tokens must match title or subtitle")
        palette.updateQuery("text OCR")
        XCTAssertEqual(palette.visibleCommands.map(\.id), ["search"])
        palette.updateQuery("unavailable")
        XCTAssertTrue(palette.visibleCommands.isEmpty, "Internal action identifiers do not become user-facing search keywords")
        XCTAssertNil(palette.selectedCommandID)
        XCTAssertTrue(palette.handle(key(36)), "Return is consumed even when the query has no result")
        palette.updateQuery("image first")
        XCTAssertEqual(palette.visibleCommands.map(\.id), ["unavailable"])
        XCTAssertNil(palette.selectedCommandID, "A disabled command can be explained without becoming executable")
        palette.updateQuery("")
        XCTAssertEqual(palette.visibleCommands.count, 4)
        XCTAssertEqual(palette.selectedCommandID, "search")
        let turkish = CommandPalette(commands: [
            .init(id: "light", title: "IŞIK ayarları", subtitle: "Görsel görünümü"),
            .init(id: "other", title: "Klasör aç")
        ], onExecute: { _ in })
        defer { clean(turkish) }
        turkish.updateQuery("ışık")
        XCTAssertEqual(turkish.visibleCommands.map(\.id), ["light"], "Turkish dotless-I queries match uppercase command labels regardless of system locale")
        turkish.updateQuery("IŞIK")
        XCTAssertEqual(turkish.selectedCommandID, "light")
    }

    func testCommandPaletteArrowsSkipDisabledCommandsClampAndPreserveTextEditingShortcuts() throws {
        _ = NSApplication.shared
        var executions = [String]()
        let palette = CommandPalette(commands: commands(), onExecute: { executions.append($0) })
        defer { clean(palette) }
        XCTAssertTrue(palette.handle(key(126)))
        XCTAssertEqual(palette.selectedCommandID, "search")
        XCTAssertTrue(palette.handle(key(125)))
        XCTAssertEqual(palette.selectedCommandID, "folder")
        XCTAssertTrue(palette.handle(key(125)))
        XCTAssertTrue(palette.handle(key(125)))
        XCTAssertEqual(palette.selectedCommandID, "settings")
        XCTAssertTrue(palette.handle(key(126)))
        XCTAssertEqual(palette.selectedCommandID, "folder")
        XCTAssertFalse(palette.handle(key(123)), "Left and Right belong to the native query caret")
        XCTAssertFalse(palette.handle(key(124)))
        XCTAssertFalse(palette.handle(key(126, flags: .shift)), "Shift+arrow remains native text selection")
        XCTAssertFalse(palette.handle(key(36, flags: .command)), "Modified Return must not accidentally execute a command")
        XCTAssertFalse(palette.handle(key(0, flags: .command, text: "a")))
        XCTAssertFalse(palette.handle(key(49, text: " ")), "Spaces can occur in command search phrases")
        XCTAssertTrue(executions.isEmpty)
        XCTAssertTrue(palette.handle(key(76)))
        XCTAssertEqual(executions, ["folder"], "Keypad Enter executes the highlighted enabled result")
        XCTAssertTrue(palette.handle(key(36)))
        XCTAssertEqual(executions, ["folder"], "A stale event after closure cannot run a command twice")
    }

    func testCommandPaletteNativeEditorSearchesAndClosesBeforeRunningAction() throws {
        _ = NSApplication.shared
        var closed = false, actionObservedClosure = false, executed = [String]()
        let palette = CommandPalette(commands: commands()) { id in
            actionObservedClosure = closed; executed.append(id)
        }
        defer { clean(palette) }
        palette.onClose = { closed = true }
        palette.window.setFrame(NSRect(x: -10000, y: -10000, width: 560, height: 387), display: false)
        palette.window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertTrue(palette.window.makeFirstResponder(palette.searchField))
        let editor = try XCTUnwrap(palette.searchField.currentEditor() as? NSTextView)
        editor.insertText("appear", replacementRange: NSRange(location: NSNotFound, length: 0))
        palette.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: palette.searchField))
        XCTAssertEqual(palette.query, "appear")
        XCTAssertEqual(palette.visibleCommands.map(\.id), ["settings"])
        XCTAssertTrue(palette.window.firstResponder === editor, "Filtering keeps the native field editor alive")
        XCTAssertFalse(palette.control(palette.searchField, textView: editor, doCommandBy: #selector(NSResponder.moveLeft(_:))))
        XCTAssertTrue(palette.control(palette.searchField, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(executed, ["settings"])
        XCTAssertTrue(actionObservedClosure, "A command may open another panel only after this one has closed")
        XCTAssertTrue(palette.shouldRestoreParentFocus, "Explicit execution keeps normal parent focus restoration")
    }

    func testCommandPaletteEscapeCancelsAndDisabledCommandsCannotExecute() throws {
        _ = NSApplication.shared
        var closed = 0, executed = [String]()
        let palette = CommandPalette(commands: commands()) { executed.append($0) }
        defer { clean(palette) }
        palette.onClose = { closed += 1 }
        palette.updateQuery("image first")
        palette.table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        XCTAssertTrue(palette.handle(key(36)))
        XCTAssertTrue(executed.isEmpty)
        XCTAssertEqual(closed, 0)
        XCTAssertTrue(palette.handle(key(53)))
        XCTAssertEqual(closed, 1)
        XCTAssertTrue(palette.shouldRestoreParentFocus, "Escape returns keyboard focus to the invoking surface")
        XCTAssertTrue(executed.isEmpty)
    }

    func testActionBarFindsExplicitAliasesAndGroupsWithoutExposingInternalIDs() throws {
        _ = NSApplication.shared
        let palette = CommandPalette(commands: [
            .init(id: "opaque-storage-identifier", title: "Sabitle", subtitle: "Seçili öğeyi sakla", group: "Kütüphane düzenleme", keywords: ["favorite", "IŞIK"]),
            .init(id: "other", title: "Klasörü aç", group: "Gezinme")
        ], onExecute: { _ in })
        defer { clean(palette) }
        palette.updateQuery("favorite düzenleme")
        XCTAssertEqual(palette.visibleCommands.map(\.id), ["opaque-storage-identifier"], "Search tokens may match a deliberate alias and the localized group together")
        palette.updateQuery("ışık")
        XCTAssertEqual(palette.selectedCommandID, "opaque-storage-identifier", "Aliases use the same Turkish-aware folding as action titles")
        palette.updateQuery("kutuphane secili")
        XCTAssertEqual(palette.selectedCommandID, "opaque-storage-identifier", "Diacritics may span category and subtitle tokens")
        palette.updateQuery("opaque-storage-identifier")
        XCTAssertTrue(palette.visibleCommands.isEmpty, "IDs remain private routing details even when explicit aliases exist")
    }

    func testActionBarSearchContentsClosesFirstAndRunsOnlyOnce() throws {
        _ = NSApplication.shared
        var events = [String]()
        let palette = CommandPalette(commands: commands(), onExecute: { _ in events.append("command") })
        defer { clean(palette) }
        func searchButton(in view: NSView) -> NSButton? {
            if let button = view as? NSButton, button.identifier?.rawValue == "command-palette-search-contents" || button.accessibilityIdentifier() == "command-palette-search-contents" { return button }
            return view.subviews.lazy.compactMap { searchButton(in: $0) }.first
        }
        let button = try XCTUnwrap(searchButton(in: try XCTUnwrap(palette.window.contentView)))
        XCTAssertTrue(button.isHidden, "The mode switch stays hidden until an actual content search handler is supplied")
        palette.onClose = { events.append("closed") }
        palette.onSearchContents = { events.append("search") }
        XCTAssertFalse(button.isHidden)
        button.performClick(nil)
        XCTAssertEqual(events, ["closed", "search"], "Content search can acquire focus only after the action bar is closed")
        button.performClick(nil)
        palette.executeSelected()
        XCTAssertEqual(events, ["closed", "search"], "Late click or Enter events cannot run a second action")
        XCTAssertTrue(palette.shouldRestoreParentFocus, "The explicit content-search switch keeps normal focus restoration")
    }

    func testActionBarDisabledReasonsAndActiveStateRemainAccessible() throws {
        _ = NSApplication.shared
        let palette = CommandPalette(commands: [
            .init(id: "marker", title: "Marker", keyHint: "H", isEnabled: false, group: "Image markup", disabledReason: "Select one image first"),
            .init(id: "pinned", title: "Pinned only", keyHint: "F", group: "View", isActive: true)
        ], onExecute: { _ in })
        defer { clean(palette) }
        let disabled = try XCTUnwrap(palette.tableView(palette.table, viewFor: nil, row: 0))
        XCTAssertTrue(disabled.accessibilityLabel()?.contains("Select one image first") == true, "The reason an action is unavailable must be readable by VoiceOver")
        XCTAssertTrue(disabled.accessibilityLabel()?.contains("Image markup") == true)
        XCTAssertFalse(disabled.isAccessibilityEnabled())
        let active = try XCTUnwrap(palette.tableView(palette.table, viewFor: nil, row: 1))
        XCTAssertEqual(active.accessibilityValue() as? String, "1")
        XCTAssertEqual(active.subviews.filter { $0 is NSImageView }.count, 2, "An active action shows a checkmark in addition to its action icon")
        XCTAssertEqual(palette.selectedCommandID, "pinned", "Unavailable actions remain discoverable without taking the keyboard selection")
        palette.moveSelection(-1)
        XCTAssertEqual(palette.selectedCommandID, "pinned")
    }

    func testActionBarFocusLossDismissesWithoutReclaimingFocusOrExecutingStaleActions() throws {
        _ = NSApplication.shared
        var closed = 0, executed = [String]()
        let palette = CommandPalette(commands: commands(), onExecute: { executed.append($0) })
        defer { clean(palette) }
        palette.onClose = { closed += 1 }
        palette.window.setFrame(NSRect(x: -10000, y: -10000, width: 600, height: 465), display: false)
        palette.window.orderFront(nil)
        XCTAssertTrue(palette.window.isVisible)
        palette.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: palette.window))
        XCTAssertFalse(palette.window.isVisible)
        XCTAssertFalse(palette.shouldRestoreParentFocus, "A click outside the action bar must retain the user's newly chosen focus")
        XCTAssertEqual(closed, 1)
        palette.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: palette.window))
        palette.executeSelected()
        XCTAssertEqual(closed, 1, "Repeated focus notifications close a dismissed action bar only once")
        XCTAssertTrue(executed.isEmpty, "A stale Enter event cannot act on the previous selection after focus changed")
        palette.show(relativeTo: nil)
        XCTAssertTrue(palette.shouldRestoreParentFocus, "Reopening starts a fresh focus-restoration context")
        XCTAssertTrue(palette.handle(key(53)))
        XCTAssertTrue(palette.shouldRestoreParentFocus)
    }

    func testActionBarRanksExactTitlesPrefixesAndExplicitAliasesStably() throws {
        _ = NSApplication.shared
        let original = [
            CommandPalette.Command(id: "open", title: "Open library", group: "IŞIK tools"),
            .init(id: "pencil", title: "Pencil settings"),
            .init(id: "pen", title: "Pen"),
            .init(id: "pen-settings", title: "Pen settings", group: "Image markup"),
            .init(id: "word-prefix", title: "Draw with Pen"),
            .init(id: "alias", title: "Marker", keywords: ["IŞIK", "pen settings"]),
            .init(id: "group-only", title: "Appearance", group: "Pen settings IŞIK")
        ]
        let palette = CommandPalette(commands: original, onExecute: { _ in })
        defer { clean(palette) }
        XCTAssertEqual(palette.visibleCommands.map(\.id), original.map(\.id))
        palette.updateQuery("pen")
        XCTAssertEqual(palette.visibleCommands.map(\.id), ["pen", "pencil", "pen-settings", "word-prefix", "open", "alias", "group-only"], "Exact titles beat prefixes, word starts beat incidental title substrings, and aliases beat category-only matches")
        XCTAssertEqual(palette.selectedCommandID, "pen", "An early Open command must not win a search for the Pen tool")
        palette.updateQuery(" PEN   settings ")
        XCTAssertEqual(palette.visibleCommands.map(\.id), ["pen-settings", "pencil", "alias", "group-only"], "All query words must still match while exact phrases rank above partial or metadata matches")
        palette.updateQuery("ışık")
        XCTAssertEqual(palette.visibleCommands.map(\.id), ["alias", "open", "group-only"], "A full Turkish alias outranks incidental group matches with stable ties")
        palette.updateQuery("  ")
        XCTAssertEqual(palette.visibleCommands.map(\.id), original.map(\.id), "Clearing search restores the curated action order")
        palette.updateQuery("pen missing")
        XCTAssertTrue(palette.visibleCommands.isEmpty, "Relevance must not relax the all-token match requirement")
    }
}
