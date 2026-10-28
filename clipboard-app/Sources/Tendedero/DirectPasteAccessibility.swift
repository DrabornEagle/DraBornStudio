import AppKit
import ApplicationServices

/// Resolve the keyboard input target without reading its value or selection.
/// AXValue being assignable is unrelated to an editor accepting Command-V.
@MainActor enum DirectPasteAccessibility {
    struct Environment {
        var focusedElement: (pid_t) -> AnyObject?
        var attribute: (AnyObject, String) -> AnyObject?
        var isElement: (AnyObject) -> Bool
        /// Capability only: this must never fetch AXValue itself. Unsupported
        /// providers return nil rather than being treated as read-only.
        var valueSettable: (AnyObject) -> Bool? = { _ in nil }

        static var system: Environment { system(deadline: nil) }
        static func system(deadline: TimeInterval?) -> Environment {
            func attribute(_ object: AnyObject, _ name: String) -> AnyObject? {
                let remaining = deadline.map { $0 - ProcessInfo.processInfo.systemUptime } ?? 0.15
                guard remaining > 0 else { return nil }
                let element = unsafeBitCast(object, to: AXUIElement.self)
                AXUIElementSetMessagingTimeout(element, Float(min(0.15, remaining)))
                var value: CFTypeRef?
                let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
                guard error == .success else {
                    // Missing/unsupported focus on a terminal field is normal.
                    // Report only actual query failures, never field content.
                    if name == kAXFocusedUIElementAttribute, error != .attributeUnsupported, error != .noValue {
                        DirectPasteDiagnostics.log.debug("Focused AX query failed code=\(error.rawValue, privacy: .public)")
                    }
                    return nil
                }
                return value
            }
            return Environment(focusedElement: { pid in
                let application = AXUIElementCreateApplication(pid)
                return attribute(application, kAXFocusedUIElementAttribute)
            }, attribute: attribute, isElement: { CFGetTypeID($0) == AXUIElementGetTypeID() },
                valueSettable: { object in
                    let remaining = deadline.map { $0 - ProcessInfo.processInfo.systemUptime } ?? 0.15
                    guard remaining > 0 else { return nil }
                    let element = unsafeBitCast(object, to: AXUIElement.self)
                    AXUIElementSetMessagingTimeout(element, Float(min(0.15, remaining)))
                    var settable = DarwinBoolean(false)
                    guard AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success else { return nil }
                    return settable.boolValue
                })
        }
    }

    /// Chromium/Electron may not expose web editors until an assistive client
    /// requests its application role or manual accessibility support. This is
    /// a one-shot capture preparation, not a permission grant or an editor hint.
    struct WarmupEnvironment {
        var ownPID: pid_t
        var trusted: () -> Bool
        var application: (pid_t) -> AnyObject?
        var attribute: (AnyObject, String) -> AnyObject?
        var setBoolean: (AnyObject, String, Bool) -> Bool
        static var system: WarmupEnvironment {
            .init(ownPID: ProcessInfo.processInfo.processIdentifier, trusted: { AXIsProcessTrusted() },
                application: { pid in
                    let app = AXUIElementCreateApplication(pid)
                    AXUIElementSetMessagingTimeout(app, 0.15)
                    return app
                }, attribute: Environment.system.attribute,
                setBoolean: { object, name, value in
                    let app = unsafeBitCast(object, to: AXUIElement.self)
                    return AXUIElementSetAttributeValue(app, name as CFString, value ? kCFBooleanTrue : kCFBooleanFalse) == .success
                })
        }
    }
    @discardableResult static func prepareAccessibility(_ pid: pid_t, environment: WarmupEnvironment = .system) -> Bool {
        guard pid > 0, pid != environment.ownPID, environment.trusted(),
              let app = environment.application(pid) else { return false }
        // Reading the application role is Chromium's current native/basic AX
        // activation path. Electron also documents this explicit manual flag.
        let role = environment.attribute(app, kAXRoleAttribute) as? String
        let manual = environment.setBoolean(app, "AXManualAccessibility", true)
        DirectPasteDiagnostics.log.debug("AX warmup pid=\(pid) applicationRole=\(role == kAXApplicationRole, privacy: .public) manualAccepted=\(manual, privacy: .public)")
        // Unsupported flags on native apps remain harmless. Never set the
        // undocumented AXEnhancedUserInterface or reset another AT's mode.
        return manual || role == kAXApplicationRole
    }

    private struct Capabilities {
        let textRole: Bool
        let focusContainer: Bool
        let editable: Bool?
        let enabled: Bool
        let secure: Bool
        let readOnlyTextRole: Bool
        var blocked: Bool { !enabled || editable == false || secure || readOnlyTextRole }
    }

    static func focusedField(_ pid: pid_t) -> DirectPasteCoordinator.FocusedField? {
        focusedField(pid, environment: .system)
    }

    static func focusedField(_ pid: pid_t, before deadline: TimeInterval) -> DirectPasteCoordinator.FocusedField? {
        focusedField(pid, environment: .system(deadline: deadline))
    }

    static func focusedField(_ pid: pid_t, environment: Environment) -> DirectPasteCoordinator.FocusedField? {
        guard let focused = environment.focusedElement(pid), environment.isElement(focused) else { return nil }
        func capabilities(_ element: AnyObject) -> Capabilities {
            let role = environment.attribute(element, kAXRoleAttribute) as? String
            let subrole = environment.attribute(element, kAXSubroleAttribute) as? String
            let editable = environment.attribute(element, "AXEditable") as? Bool
            let isEditable = environment.attribute(element, kAXIsEditableAttribute) as? Bool
            // An explicit read-only answer wins over a conflicting positive hint.
            let hint: Bool? = editable == false || isEditable == false ? false : editable ?? isEditable
            let textRole = role == kAXTextFieldRole || role == kAXTextAreaRole || role == kAXComboBoxRole
            let secure = role == kAXSecureTextFieldSubrole || subrole == kAXSecureTextFieldSubrole
            // Chromium exposes readonly web text controls through the setter
            // capability, not an AXEditable Boolean. Its AXDOMIdentifier getter
            // returns a string even without an HTML id. Limit this fallback to
            // those web text roles without an explicit positive editable hint:
            // native/custom editors and generic rich roots may accept paste
            // without exposing an AXValue setter. DOM ids are never logged.
            // A missing capability is not a denial; no value/selection is read.
            // Chromium152 AXPlatformNodeCocoa::isAccessibilitySelectorAllowed
            // rejects setters when its delegate IsReadOnlyOrDisabled is true.
            let roleOnlyWebText = textRole && !secure && hint == nil &&
                environment.attribute(element, "AXDOMIdentifier") is String
            let settable = roleOnlyWebText ? environment.valueSettable(element) : nil
            DirectPasteDiagnostics.log.debug("Field role=\(role ?? "missing", privacy: .public) subrole=\(subrole ?? "missing", privacy: .public) editable=\(String(describing: hint), privacy: .public) valueSettable=\(String(describing: settable), privacy: .public)")
            return Capabilities(textRole: textRole,
                focusContainer: [kAXGroupRole, "AXWebArea", kAXScrollAreaRole, kAXWindowRole, kAXSplitGroupRole].contains(role ?? ""),
                editable: hint, enabled: (environment.attribute(element, kAXEnabledAttribute) as? Bool) != false,
                secure: secure, readOnlyTextRole: settable == false)
        }
        func field(_ element: AnyObject, _ facts: Capabilities, ancestor: Bool = false) -> DirectPasteCoordinator.FocusedField {
            .init(identity: element, editable: !facts.blocked && (ancestor || facts.textRole || facts.editable == true), secure: facts.secure,
                awaitingAccessibility: !ancestor && !facts.blocked && facts.focusContainer && !facts.textRole && facts.editable != true)
        }

        guard let (leaf, leafFacts) = focusedLeaf(from: focused, environment: environment, capabilities: capabilities) else { return nil }
        // A secure, disabled or explicitly read-only descendant cannot be made
        // eligible by walking up to an ordinary contenteditable container.
        guard !leafFacts.blocked else { return field(leaf, leafFacts) }
        var ancestors = [(AnyObject, Capabilities)]()
        // Query the public AX attribute names as strings so source builds with
        // older SDKs whose headers omit these web-editor constants. Unsupported
        // attributes return nil through the same ordinary AX query.
        for name in ["AXHighestEditableAncestor", "AXEditableAncestor"] {
            guard let ancestor = environment.attribute(leaf, name), environment.isElement(ancestor) else { continue }
            let facts = capabilities(ancestor)
            guard !facts.blocked else { return field(ancestor, facts) }
            ancestors.append((ancestor, facts))
        }
        // The editable-ancestor relation is positive evidence for custom rich
        // editor roles. Prefer the highest root so focused DOM descendants
        // resolve to the same identity when the browser restores focus.
        if let (ancestor, facts) = ancestors.first { return field(ancestor, facts, ancestor: true) }
        // The application vends this element. Its AX owner may be a remote
        // WebContent process; activation and keyboard events still target pid.
        return field(leaf, leafFacts)
    }

    /// WKWebView can vend a remote focus proxy before its actual editor. Follow
    /// only that explicit focus relation, never arbitrary children or text.
    /// Keep the terminal identity for the coordinator's exact-field checks.
    private static func focusedLeaf(from element: AnyObject, environment: Environment,
                                    capabilities: (AnyObject) -> Capabilities) -> (AnyObject, Capabilities)? {
        var current = element
        var visited = [element]
        while true {
            let facts = capabilities(current)
            // A text editor's generic WebKit focus getter may return itself.
            // Resolve only containers; ordinary fields and static descendants
            // retain their existing role/ancestor checks. A secure or disabled
            // proxy must not expose an eligible field through another link.
            guard facts.focusContainer, !facts.textRole, facts.editable != true,
                  facts.enabled, !facts.secure else { return (current, facts) }
            guard let next = environment.attribute(current, kAXFocusedUIElementAttribute) else { return (current, facts) }
            guard environment.isElement(next), visited.count < 8,
                  !visited.contains(where: { CFEqual($0, next) }) else {
                DirectPasteDiagnostics.log.debug("Focused AX chain rejected depth=\(visited.count, privacy: .public)")
                return nil
            }
            visited.append(next)
            current = next
        }
    }
}
