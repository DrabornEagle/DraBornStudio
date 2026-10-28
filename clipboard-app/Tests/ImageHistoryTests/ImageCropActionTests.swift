import AppKit
import Carbon
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

@MainActor final class ImageCropActionTests: HistoryTestCase {
    private func crop(context: ActionBarCatalog.Context, bindings: KeyboardBindings) throws -> CommandPalette.Command {
        try XCTUnwrap(ActionBarCatalog.entries(context: context, bindings: bindings).first { $0.action == .keyboard(.cropImage) }?.command)
    }

    func testCropShortcutIsConfigurableAndOnlyBelongsToImagePreviewAndMarkup() throws {
        let fixture = try SyntheticFixture(); defer { fixture.cleanup() }
        let bindings = KeyboardBindings(defaults: fixture.defaults)
        XCTAssertTrue(KeyboardAction.allCases.contains(.cropImage))
        XCTAssertEqual(KeyboardAction.cropImage.title, L("Crop image"))
        XCTAssertEqual(KeyboardAction.cropImage.contexts, [.imagePreview, .imageMarkup, .library])
        XCTAssertEqual(KeyboardAction.cropImage.scopeTitle, L("Image preview"))
        for context in [KeyboardContext.imagePreview, .imageMarkup, .library] {
            XCTAssertEqual(bindings.effectiveShortcuts(.cropImage, in: context).map(\.keyCode), [8])
            XCTAssertEqual(bindings.effectiveShortcuts(.cropImage, in: context).map(\.modifiers), [0])
            XCTAssertEqual(bindings.title(.cropImage, in: context), "C")
        }
        for context in [KeyboardContext.line, .textPreview, .linkPreview] {
            XCTAssertTrue(bindings.effectiveShortcuts(.cropImage, in: context).isEmpty)
        }
        let replacement = KeyShortcut(keyCode: 8, modifiers: controlKey | optionKey, keyLabel: "C")
        try bindings.set([replacement], for: .cropImage)
        XCTAssertEqual(KeyboardBindings(defaults: fixture.defaults).title(.cropImage, in: .imagePreview), "⌃⌥C")
        try bindings.reset(.cropImage)
        XCTAssertEqual(bindings.title(.cropImage, in: .imagePreview), "C")
    }

    func testCropCatalogRequiresOneAvailableStillImage() throws {
        let fixture = try SyntheticFixture(); defer { fixture.cleanup() }
        let bindings = KeyboardBindings(defaults: fixture.defaults)
        var context = ActionBarCatalog.Context()
        context.selectedCount = 1; context.kind = .image; context.hasFile = true
        for origin in [ActionBarCatalog.Origin.line, .shelfPreview, .library, .libraryPreview] {
            context.origin = origin
            XCTAssertTrue(try crop(context: context, bindings: bindings).isEnabled)
        }
        context.isRecording = true
        XCTAssertFalse(try crop(context: context, bindings: bindings).isEnabled)
        context.isRecording = false; context.isDeleted = true
        XCTAssertFalse(try crop(context: context, bindings: bindings).isEnabled)
        context.isDeleted = false; context.hasFile = false
        XCTAssertFalse(try crop(context: context, bindings: bindings).isEnabled)
        context.hasFile = true; context.selectedCount = 2
        XCTAssertFalse(try crop(context: context, bindings: bindings).isEnabled)
        context.selectedCount = 1
        for kind in [LibraryKind.text, .link] {
            context.kind = kind
            let command = try crop(context: context, bindings: bindings)
            XCTAssertFalse(command.isEnabled)
            XCTAssertEqual(command.disabledReason, L("Select one image first"))
        }
    }

    func testCropCatalogShowsDirectPreviewShortcutWithoutMarkupPrefix() throws {
        let fixture = try SyntheticFixture(); defer { fixture.cleanup() }
        let bindings = KeyboardBindings(defaults: fixture.defaults)
        var context = ActionBarCatalog.Context()
        context.selectedCount = 1; context.kind = .image; context.hasFile = true
        for origin in [ActionBarCatalog.Origin.line] {
            context.origin = origin
            XCTAssertEqual(try crop(context: context, bindings: bindings).keyHint, "Space → C")
        }
        for origin in [ActionBarCatalog.Origin.shelfPreview, .libraryPreview, .library] {
            context.origin = origin
            XCTAssertEqual(try crop(context: context, bindings: bindings).keyHint, "C")
            context.isMarkupEditing = true
            XCTAssertEqual(try crop(context: context, bindings: bindings).keyHint, "C")
            context.isMarkupEditing = false
        }
        try bindings.set([KeyShortcut(keyCode: 8, modifiers: controlKey | optionKey, keyLabel: "C")], for: .cropImage)
        try bindings.set([KeyShortcut(keyCode: 49, modifiers: controlKey | optionKey, keyLabel: "Space")], for: .preview)
        context.origin = .line
        XCTAssertEqual(try crop(context: context, bindings: bindings).keyHint, "⌃⌥Space → ⌃⌥C")
        try bindings.set([], for: .cropImage)
        XCTAssertEqual(try crop(context: context, bindings: bindings).keyHint, "")
    }

    func testCropCatalogHasImageEditingMetadataAndBilingualSearchAliases() throws {
        let fixture = try SyntheticFixture(); defer { fixture.cleanup() }
        let bindings = KeyboardBindings(defaults: fixture.defaults)
        let command = try crop(context: .init(), bindings: bindings)
        XCTAssertEqual(command.id, KeyboardAction.cropImage.rawValue)
        XCTAssertEqual(command.title, L("Crop image"))
        XCTAssertEqual(command.group, L("Image markup"))
        XCTAssertEqual(command.systemImage, "crop")
        for alias in ["crop", "trim", "kırp", "kirp", "kes"] { XCTAssertTrue(command.keywords.contains(alias)) }
    }

    func testCropRemappingRejectsSharedImageToolConflictsAndHonorsLegacyOverrides() throws {
        let fixture = try SyntheticFixture(); defer { fixture.cleanup() }
        let bindings = KeyboardBindings(defaults: fixture.defaults)
        do {
            try bindings.set([KeyShortcut(keyCode: 8, modifiers: 0, keyLabel: "C")], for: .markupPen)
            XCTAssertTrue(false, "Crop and Pen must not share a shortcut while editing an image")
        } catch let error as KeyboardBindings.Conflict { XCTAssertEqual(error.action, .cropImage) }
        do {
            try bindings.set([KeyShortcut(keyCode: 4, modifiers: 0, keyLabel: "H")], for: .cropImage)
            XCTAssertTrue(false, "Crop must respect Marker’s existing shortcut")
        } catch let error as KeyboardBindings.Conflict { XCTAssertEqual(error.action, .markupMarker) }
        let legacy = [KeyboardAction.markupPen.rawValue: [KeyShortcut(keyCode: 8, modifiers: 0, keyLabel: "C")]]
        fixture.defaults.set(try JSONEncoder().encode(legacy), forKey: "contextKeyboardBindingsV1")
        XCTAssertEqual(bindings.title(.cropImage, in: .imagePreview), "C")
        XCTAssertTrue(bindings.effectiveShortcuts(.cropImage, in: .imageMarkup).isEmpty)
        var context = ActionBarCatalog.Context()
        context.origin = .shelfPreview; context.kind = .image; context.selectedCount = 1; context.hasFile = true; context.isMarkupEditing = true
        XCTAssertEqual(try crop(context: context, bindings: bindings).keyHint, "", "An overridden key must not be advertised as Crop")
        XCTAssertEqual(bindings.title(.markupPen, in: .imageMarkup), "C")
    }
}
