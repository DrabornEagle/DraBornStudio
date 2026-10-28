import AppKit
import ApplicationServices
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

@MainActor private final class PasteAccessibilityFixture {
    final class Element: NSObject {
        var attributes: [String: AnyObject] = [:]
        var valueSettable: Bool?
        let ownerPID: pid_t
        init(role: String, ownerPID: pid_t = 101) {
            self.ownerPID = ownerPID
            attributes[kAXRoleAttribute] = role as NSString
        }
        func set(_ name: String, _ value: Bool) { attributes[name] = NSNumber(value: value) }
    }
    var focused: AnyObject?
    var requestedPIDs = [pid_t]()
    var reads = [String]()
    var setterQueries = [AnyObject]()
    var environment: DirectPasteAccessibility.Environment {
        .init(focusedElement: { self.requestedPIDs.append($0); return self.focused }, attribute: { element, name in
            self.reads.append(name)
            return (element as? Element)?.attributes[name]
        }, isElement: { $0 is Element }, valueSettable: { element in
            self.setterQueries.append(element)
            return (element as? Element)?.valueSettable
        })
    }
    func resolve() -> DirectPasteCoordinator.FocusedField? { DirectPasteAccessibility.focusedField(101, environment: environment) }
}

@MainActor final class DirectPasteAccessibilityTests: HistoryTestCase {
    func testPasteAccessibilityTextRolesAcceptUnsupportedSetterCapabilityWithoutReadingContent() throws {
        for role in [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole] {
            let fixture = PasteAccessibilityFixture(), element = PasteAccessibilityFixture.Element(role: role)
            // An unsupported AX setter capability is not a read-only verdict.
            // The resolver asks only capability metadata, never the value.
            element.attributes[kAXValueAttribute] = "Must not be read" as NSString
            element.attributes[kAXSelectedTextAttribute] = "Must not be read" as NSString
            fixture.focused = element
            let field = try XCTUnwrap(fixture.resolve())
            XCTAssertTrue(field.identity === element); XCTAssertTrue(field.editable); XCTAssertFalse(field.secure)
            XCTAssertFalse(fixture.reads.contains(kAXValueAttribute)); XCTAssertFalse(fixture.reads.contains(kAXSelectedTextAttribute))
            XCTAssertFalse(fixture.reads.contains(kAXSelectedTextRangeAttribute))
        }
    }

    func testPasteAccessibilityRejectsExplicitReadOnlyTextRoleBeforeUsingAnAncestor() throws {
        for role in [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole] {
            let fixture = PasteAccessibilityFixture(), leaf = PasteAccessibilityFixture.Element(role: role)
            let ancestor = PasteAccessibilityFixture.Element(role: kAXGroupRole)
            leaf.valueSettable = false
            leaf.attributes["AXDOMIdentifier"] = "synthetic-readonly" as NSString
            leaf.attributes["AXHighestEditableAncestor"] = ancestor
            fixture.focused = leaf
            let field = try XCTUnwrap(fixture.resolve())
            XCTAssertTrue(field.identity === leaf); XCTAssertFalse(field.editable)
            XCTAssertFalse(field.awaitingAccessibility); XCTAssertFalse(field.secure)
            XCTAssertFalse(fixture.reads.contains("AXHighestEditableAncestor"))
            XCTAssertFalse(fixture.reads.contains(kAXValueAttribute))
        }
    }

    func testPasteAccessibilityNativeAndExplicitCustomTextEditorsKeepNonassignableValueCompatibility() throws {
        for role in [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole] {
            for explicitHint in [false, true] {
                let fixture = PasteAccessibilityFixture(), editor = PasteAccessibilityFixture.Element(role: role)
                editor.valueSettable = false
                if explicitHint {
                    editor.attributes["AXDOMIdentifier"] = "custom-rich-editor" as NSString
                    editor.set("AXEditable", true)
                }
                fixture.focused = editor
                let field = try XCTUnwrap(fixture.resolve())
                XCTAssertTrue(field.identity === editor); XCTAssertTrue(field.editable)
                XCTAssertTrue(fixture.setterQueries.isEmpty, "Native/custom paste eligibility does not require AXValue assignment")
                XCTAssertFalse(fixture.reads.contains(kAXValueAttribute))
            }
        }
    }

    func testPasteAccessibilityWebIdentifierMayBeEmptyAndUnsupportedSetterIsNotReadOnly() throws {
        for setter: Bool? in [nil, true, false] {
            let fixture = PasteAccessibilityFixture(), editor = PasteAccessibilityFixture.Element(role: kAXTextAreaRole)
            editor.attributes["AXDOMIdentifier"] = "" as NSString; editor.valueSettable = setter
            fixture.focused = editor
            XCTAssertEqual(try XCTUnwrap(fixture.resolve()).editable, setter != false)
            XCTAssertEqual(fixture.setterQueries.count, 1)
            XCTAssertFalse(fixture.reads.contains(kAXValueAttribute))
        }
    }

    func testPasteAccessibilityCustomRichEditorsDoNotRequireAValueSetter() throws {
        for direct in [false, true] {
            let fixture = PasteAccessibilityFixture()
            let leaf = PasteAccessibilityFixture.Element(role: kAXStaticTextRole)
            let root = PasteAccessibilityFixture.Element(role: kAXGroupRole)
            leaf.valueSettable = false; root.valueSettable = false
            if direct { root.set("AXEditable", true); fixture.focused = root }
            else { leaf.attributes["AXHighestEditableAncestor"] = root; fixture.focused = leaf }
            let field = try XCTUnwrap(fixture.resolve())
            XCTAssertTrue(field.identity === root); XCTAssertTrue(field.editable)
            XCTAssertTrue(fixture.setterQueries.isEmpty, "Do not equate generic rich-editor value assignment with paste")
            XCTAssertFalse(fixture.reads.contains(kAXValueAttribute))
        }
    }

    func testPasteAccessibilityResolvesTextRootBeforeQueryingItsSetterCapability() throws {
        for readOnly in [false, true] {
            let fixture = PasteAccessibilityFixture()
            let leaf = PasteAccessibilityFixture.Element(role: kAXStaticTextRole)
            let root = PasteAccessibilityFixture.Element(role: kAXTextAreaRole)
            leaf.valueSettable = false; root.valueSettable = !readOnly
            root.attributes["AXDOMIdentifier"] = "synthetic-rich-root" as NSString
            leaf.attributes["AXHighestEditableAncestor"] = root; fixture.focused = leaf
            let field = try XCTUnwrap(fixture.resolve())
            XCTAssertTrue(field.identity === root); XCTAssertEqual(field.editable, !readOnly)
            XCTAssertTrue(fixture.setterQueries.count == 1 && fixture.setterQueries[0] === root)
            XCTAssertFalse(fixture.reads.contains(kAXValueAttribute))
        }
    }

    func testPasteAccessibilityResolvesContenteditableDescendantsToStableHighestRoot() throws {
        let fixture = PasteAccessibilityFixture()
        let leaf = PasteAccessibilityFixture.Element(role: kAXStaticTextRole)
        let editable = PasteAccessibilityFixture.Element(role: kAXTextAreaRole)
        let highest = PasteAccessibilityFixture.Element(role: kAXGroupRole)
        leaf.attributes["AXEditableAncestor"] = editable
        leaf.attributes["AXHighestEditableAncestor"] = highest
        fixture.focused = leaf
        let field = try XCTUnwrap(fixture.resolve())
        XCTAssertTrue(field.identity === highest); XCTAssertTrue(field.editable); XCTAssertFalse(field.awaitingAccessibility)
        let nextLeaf = PasteAccessibilityFixture.Element(role: kAXStaticTextRole)
        nextLeaf.attributes["AXEditableAncestor"] = highest
        fixture.focused = nextLeaf
        XCTAssertTrue(try XCTUnwrap(fixture.resolve()).identity === highest)
    }

    func testPasteAccessibilityExplicitEditableHintSupportsCustomEditorRoles() throws {
        for hint in ["AXEditable", kAXIsEditableAttribute] {
            let fixture = PasteAccessibilityFixture(), element = PasteAccessibilityFixture.Element(role: kAXGroupRole)
            element.set(hint, true); fixture.focused = element
            XCTAssertTrue(try XCTUnwrap(fixture.resolve()).editable)
        }
    }

    func testPasteAccessibilityDisabledSecureAndReadOnlyDescendantsCannotUseAncestor() throws {
        for blocked in ["disabled", "secure", "AXEditable", kAXIsEditableAttribute] {
            let fixture = PasteAccessibilityFixture(), leaf = PasteAccessibilityFixture.Element(role: kAXTextFieldRole)
            let ancestor = PasteAccessibilityFixture.Element(role: kAXTextAreaRole)
            leaf.attributes["AXEditableAncestor"] = ancestor
            switch blocked {
            case "disabled": leaf.set(kAXEnabledAttribute, false)
            case "secure": leaf.attributes[kAXSubroleAttribute] = kAXSecureTextFieldSubrole as NSString
            default: leaf.set(blocked, false)
            }
            fixture.focused = leaf
            let field = try XCTUnwrap(fixture.resolve())
            XCTAssertTrue(field.identity === leaf); XCTAssertFalse(field.editable)
            XCTAssertEqual(field.secure, blocked == "secure")
        }
    }

    func testPasteAccessibilityBlocksUnsafeAncestorsAndConflictingReadOnlyHints() throws {
        for blocked in ["disabled", "secure", "readOnly"] {
            let fixture = PasteAccessibilityFixture(), leaf = PasteAccessibilityFixture.Element(role: kAXStaticTextRole)
            let ancestor = PasteAccessibilityFixture.Element(role: kAXTextAreaRole)
            switch blocked {
            case "disabled": ancestor.set(kAXEnabledAttribute, false)
            case "secure": ancestor.attributes[kAXSubroleAttribute] = kAXSecureTextFieldSubrole as NSString
            default: ancestor.set("AXEditable", true); ancestor.set(kAXIsEditableAttribute, false)
            }
            leaf.attributes["AXHighestEditableAncestor"] = ancestor; fixture.focused = leaf
            XCTAssertFalse(try XCTUnwrap(fixture.resolve()).editable)
        }
    }

    func testPasteAccessibilityRejectsUnrelatedRolesAndMalformedFocusOrAncestors() throws {
        let fixture = PasteAccessibilityFixture()
        for role in [kAXButtonRole, kAXStaticTextRole, "AXWebArea", kAXGroupRole] {
            let element = PasteAccessibilityFixture.Element(role: role)
            element.attributes["AXEditableAncestor"] = "Not an element" as NSString
            fixture.focused = element
            XCTAssertFalse(try XCTUnwrap(fixture.resolve()).editable)
        }
        fixture.focused = nil; XCTAssertNil(fixture.resolve())
        fixture.focused = "Not an element" as NSString; XCTAssertNil(fixture.resolve())
    }

    func testPasteAccessibilityAcceptsAppVendedRemoteWebContentElement() throws {
        let fixture = PasteAccessibilityFixture()
        let remote = PasteAccessibilityFixture.Element(role: kAXTextAreaRole, ownerPID: 202)
        fixture.focused = remote
        let field = try XCTUnwrap(fixture.resolve())
        XCTAssertEqual(fixture.requestedPIDs, [101]); XCTAssertTrue(remote.ownerPID != 101)
        XCTAssertTrue(field.identity === remote); XCTAssertTrue(field.editable)
    }

    func testPasteAccessibilityFollowsOnlyAppVendedFocusProxiesIntoRemoteEditor() throws {
        let fixture = PasteAccessibilityFixture()
        let proxy = PasteAccessibilityFixture.Element(role: kAXGroupRole)
        let webArea = PasteAccessibilityFixture.Element(role: "AXWebArea", ownerPID: 202)
        let remote = PasteAccessibilityFixture.Element(role: kAXTextAreaRole, ownerPID: 202)
        proxy.attributes[kAXFocusedUIElementAttribute] = webArea
        webArea.attributes[kAXFocusedUIElementAttribute] = remote
        // Ordinary container editability does not describe its focused editor.
        webArea.set("AXEditable", false)
        fixture.focused = proxy
        let field = try XCTUnwrap(fixture.resolve())
        XCTAssertTrue(field.identity === remote); XCTAssertTrue(field.editable); XCTAssertFalse(field.secure)
        XCTAssertEqual(fixture.requestedPIDs, [101], "Keyboard/activation ownership stays with the application")
        XCTAssertFalse(fixture.reads.contains(kAXChildrenAttribute))
        XCTAssertFalse(fixture.reads.contains(kAXValueAttribute))
        XCTAssertFalse(fixture.reads.contains(kAXSelectedTextAttribute))
        XCTAssertFalse(fixture.reads.contains(kAXSelectedTextRangeAttribute))
    }

    func testPasteAccessibilityFocusProxiesKeepStableEditableAncestorAndChangedTargetIdentity() throws {
        let fixture = PasteAccessibilityFixture()
        let root = PasteAccessibilityFixture.Element(role: kAXGroupRole, ownerPID: 202)
        func proxy(to root: PasteAccessibilityFixture.Element) -> PasteAccessibilityFixture.Element {
            let proxy = PasteAccessibilityFixture.Element(role: "AXWebArea")
            let leaf = PasteAccessibilityFixture.Element(role: kAXStaticTextRole, ownerPID: 202)
            proxy.attributes[kAXFocusedUIElementAttribute] = leaf
            leaf.attributes["AXHighestEditableAncestor"] = root
            return proxy
        }
        fixture.focused = proxy(to: root)
        let original = try XCTUnwrap(fixture.resolve())
        XCTAssertTrue(original.identity === root); XCTAssertTrue(original.editable)
        fixture.focused = proxy(to: root)
        XCTAssertTrue(CFEqual(original.identity, try XCTUnwrap(fixture.resolve()).identity))
        let changedRoot = PasteAccessibilityFixture.Element(role: kAXGroupRole, ownerPID: 202)
        fixture.focused = proxy(to: changedRoot)
        XCTAssertFalse(CFEqual(original.identity, try XCTUnwrap(fixture.resolve()).identity),
            "A different editable root must still fail the coordinator's identity check")
    }

    func testPasteAccessibilityFocusProxiesPreserveTerminalSecurityAndReadOnlyRejection() throws {
        for blocked in ["disabled", "secure", "AXEditable", kAXIsEditableAttribute] {
            let fixture = PasteAccessibilityFixture()
            let proxy = PasteAccessibilityFixture.Element(role: "AXWebArea")
            let leaf = PasteAccessibilityFixture.Element(role: kAXTextFieldRole, ownerPID: 202)
            let ancestor = PasteAccessibilityFixture.Element(role: kAXTextAreaRole, ownerPID: 202)
            proxy.attributes[kAXFocusedUIElementAttribute] = leaf
            leaf.attributes["AXEditableAncestor"] = ancestor
            switch blocked {
            case "disabled": leaf.set(kAXEnabledAttribute, false)
            case "secure": leaf.attributes[kAXSubroleAttribute] = kAXSecureTextFieldSubrole as NSString
            default: leaf.set(blocked, false)
            }
            fixture.focused = proxy
            let field = try XCTUnwrap(fixture.resolve())
            XCTAssertTrue(field.identity === leaf); XCTAssertFalse(field.editable)
            XCTAssertEqual(field.secure, blocked == "secure")
        }
    }

    func testPasteAccessibilityRejectsMalformedAndCyclicFocusProxies() throws {
        for cycle in ["malformed", "self", "pair"] {
            let fixture = PasteAccessibilityFixture()
            let first = PasteAccessibilityFixture.Element(role: "AXWebArea")
            switch cycle {
            case "malformed": first.attributes[kAXFocusedUIElementAttribute] = "Not an element" as NSString
            case "self": first.attributes[kAXFocusedUIElementAttribute] = first
            default:
                let second = PasteAccessibilityFixture.Element(role: kAXGroupRole)
                first.attributes[kAXFocusedUIElementAttribute] = second
                second.attributes[kAXFocusedUIElementAttribute] = first
            }
            fixture.focused = first
            XCTAssertNil(fixture.resolve(), "Must not fall back to a cyclic/malformed container for \(cycle)")
            first.attributes.removeAll() // Break the synthetic ownership cycle.
        }
    }

    func testPasteAccessibilityBoundsFocusedProxyTraversal() throws {
        for count in [8, 9, 20] {
            let fixture = PasteAccessibilityFixture()
            let elements = (0..<count).map { PasteAccessibilityFixture.Element(role: $0 == count - 1 ? kAXTextAreaRole : kAXGroupRole) }
            for index in 1..<elements.count { elements[index - 1].attributes[kAXFocusedUIElementAttribute] = elements[index] }
            fixture.focused = elements[0]
            let field = fixture.resolve()
            if count == 8 { XCTAssertTrue(try XCTUnwrap(field).identity === elements.last!) }
            else { XCTAssertNil(field) }
            XCTAssertEqual(fixture.reads.filter { $0 == kAXFocusedUIElementAttribute }.count, count == 8 ? 7 : 8)
        }
    }

    func testPasteAccessibilityStopsAtSelfVendedTextAndEditableTerminals() throws {
        for role in [kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole, kAXGroupRole] {
            let fixture = PasteAccessibilityFixture()
            let editor = PasteAccessibilityFixture.Element(role: role, ownerPID: 202)
            if role == kAXGroupRole { editor.set("AXEditable", true) }
            editor.attributes[kAXFocusedUIElementAttribute] = editor
            fixture.focused = editor
            let field = try XCTUnwrap(fixture.resolve())
            XCTAssertTrue(field.identity === editor); XCTAssertTrue(field.editable)
            XCTAssertFalse(fixture.reads.contains(kAXFocusedUIElementAttribute), "A resolved editor is not a focus proxy")
            editor.attributes.removeAll()
        }
    }

    func testPasteAccessibilityCannotTraverseSecureOrDisabledContainerProxies() throws {
        for blocked in ["secure", "disabled"] {
            let fixture = PasteAccessibilityFixture()
            let first = PasteAccessibilityFixture.Element(role: "AXWebArea")
            let middle = PasteAccessibilityFixture.Element(role: kAXGroupRole)
            let editor = PasteAccessibilityFixture.Element(role: kAXTextAreaRole, ownerPID: 202)
            first.attributes[kAXFocusedUIElementAttribute] = middle
            middle.attributes[kAXFocusedUIElementAttribute] = editor
            if blocked == "secure" { middle.attributes[kAXSubroleAttribute] = kAXSecureTextFieldSubrole as NSString }
            else { middle.set(kAXEnabledAttribute, false) }
            fixture.focused = first
            let field = try XCTUnwrap(fixture.resolve())
            XCTAssertTrue(field.identity === middle); XCTAssertFalse(field.editable)
            XCTAssertEqual(field.secure, blocked == "secure")
            XCTAssertEqual(fixture.reads.filter { $0 == kAXFocusedUIElementAttribute }.count, 1)
        }
    }

    func testPasteAccessibilityDoesNotFollowFocusGettersOnNonContainerDescendants() throws {
        for role in [kAXStaticTextRole, kAXButtonRole] {
            let fixture = PasteAccessibilityFixture()
            let leaf = PasteAccessibilityFixture.Element(role: role)
            let ancestor = PasteAccessibilityFixture.Element(role: kAXGroupRole)
            leaf.attributes[kAXFocusedUIElementAttribute] = leaf
            if role == kAXStaticTextRole { leaf.attributes["AXHighestEditableAncestor"] = ancestor }
            fixture.focused = leaf
            let field = try XCTUnwrap(fixture.resolve())
            XCTAssertFalse(fixture.reads.contains(kAXFocusedUIElementAttribute))
            XCTAssertEqual(field.editable, role == kAXStaticTextRole)
            XCTAssertTrue(field.identity === (role == kAXStaticTextRole ? ancestor : leaf))
            leaf.attributes.removeAll()
        }
    }
}

@MainActor final class DirectPasteWarmupTests: HistoryTestCase {
    func testColdTreePreparationReadsOnlyApplicationRoleAndEnablesOnlyManualAccessibilityOnce() {
        let app = NSObject(); var calls = [String]()
        let environment = DirectPasteAccessibility.WarmupEnvironment(ownPID: 900, trusted: { true },
            application: { pid in XCTAssertEqual(pid, 101); calls.append("application"); return app },
            attribute: { object, name in XCTAssertTrue(object === app); calls.append(name); return kAXApplicationRole as NSString },
            setBoolean: { object, name, value in XCTAssertTrue(object === app); XCTAssertTrue(value); calls.append(name); return true })
        XCTAssertTrue(DirectPasteAccessibility.prepareAccessibility(101, environment: environment))
        XCTAssertEqual(calls, ["application", kAXRoleAttribute, "AXManualAccessibility"])
        XCTAssertFalse(calls.contains("AXEnhancedUserInterface")); XCTAssertFalse(calls.contains(kAXValueAttribute))
    }
    func testColdTreePreparationRejectsOwnProcessMissingTrustAndUnsupportedAppsWithoutPrompts() {
        var trust = false, calls = [String]()
        let environment = DirectPasteAccessibility.WarmupEnvironment(ownPID: 900, trusted: { trust },
            application: { _ in calls.append("application"); return NSObject() },
            attribute: { _, name in calls.append(name); return nil },
            setBoolean: { _, name, _ in calls.append(name); return false })
        XCTAssertFalse(DirectPasteAccessibility.prepareAccessibility(101, environment: environment)); XCTAssertTrue(calls.isEmpty)
        trust = true
        for pid: pid_t in [0, -1, 900] { XCTAssertFalse(DirectPasteAccessibility.prepareAccessibility(pid, environment: environment)) }
        XCTAssertTrue(calls.isEmpty)
        XCTAssertFalse(DirectPasteAccessibility.prepareAccessibility(101, environment: environment))
        XCTAssertEqual(calls, ["application", kAXRoleAttribute, "AXManualAccessibility"])
    }
    func testColdTreeApplicationRoleCanActivateNativeAPIsWhenManualAttributeIsUnsupported() {
        let environment = DirectPasteAccessibility.WarmupEnvironment(ownPID: 900, trusted: { true },
            application: { _ in NSObject() }, attribute: { _, _ in kAXApplicationRole as NSString },
            setBoolean: { _, name, value in XCTAssertEqual(name, "AXManualAccessibility"); XCTAssertTrue(value); return false })
        XCTAssertTrue(DirectPasteAccessibility.prepareAccessibility(101, environment: environment))
    }
    func testOnlyEligibleFocusContainersCanAwaitTheColdAccessibilityTree() throws {
        for role in [kAXGroupRole, "AXWebArea", kAXScrollAreaRole, kAXWindowRole, kAXSplitGroupRole] {
            let f = PasteAccessibilityFixture(), element = PasteAccessibilityFixture.Element(role: role)
            f.focused = element
            let field = try XCTUnwrap(f.resolve()); XCTAssertFalse(field.editable); XCTAssertTrue(field.awaitingAccessibility)
            element.set("AXEditable", false); XCTAssertFalse(try XCTUnwrap(f.resolve()).awaitingAccessibility)
            element.attributes.removeValue(forKey: "AXEditable"); element.set(kAXEnabledAttribute, false)
            XCTAssertFalse(try XCTUnwrap(f.resolve()).awaitingAccessibility)
        }
        for role in [kAXButtonRole, kAXStaticTextRole, "AXUnknown", kAXTextAreaRole] {
            let f = PasteAccessibilityFixture(); f.focused = PasteAccessibilityFixture.Element(role: role)
            XCTAssertFalse(try XCTUnwrap(f.resolve()).awaitingAccessibility)
        }
    }
}
