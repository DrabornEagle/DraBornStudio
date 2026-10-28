import AppKit
import ApplicationServices
import OSLog

/// Debug-only system log metadata: never field values, selections or payloads.
@MainActor enum DirectPasteDiagnostics {
    static let log = Logger(subsystem: "local.clipboardline.directpaste", category: "focus")
}

/// A user-initiated paste returns to the exact editable field that had focus
/// before ClipboardLine opened. No text, selected text or password is read.
@MainActor final class DirectPasteCoordinator {
    enum Outcome: Equatable {
        case pasted, permissionRequired, noTarget, focusChanged, copyFailed, pasteFailed
    }

    struct FocusedField {
        let identity: AnyObject
        let editable: Bool
        let secure: Bool
        /// Only a noneditable focus container with no negative eligibility
        /// evidence may be retried while its cold web accessibility tree loads.
        var awaitingAccessibility: Bool = false
    }

    /// Tests replace every system interaction, including the clipboard and
    /// event sender, so they never grant permissions or type into user apps.
    @MainActor struct Environment {
        var ownPID: pid_t
        var trusted: @MainActor () -> Bool
        var frontmostPID: @MainActor () -> pid_t?
        var running: @MainActor (pid_t) -> Bool
        var focusedField: @MainActor (pid_t) -> FocusedField?
        var sameField: @MainActor (FocusedField, FocusedField) -> Bool
        var activate: @MainActor (pid_t) -> Bool
        var write: @MainActor ([NSPasteboardItem]) -> Bool
        var sendPaste: @MainActor (pid_t) -> Bool
        var pause: @MainActor () async throws -> Void
        var inputReleased: @MainActor () -> Bool = { true }
        /// Nonactivating panels take key focus without becoming the workspace's
        /// frontmost application. Nil preserves older injected environments.
        var ownsKeyboardFocus: (@MainActor () -> Bool)? = nil
        var prepareAccessibility: @MainActor (pid_t) -> Bool = { _ in false }
        var now: @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
        var focusedFieldBeforeDeadline: (@MainActor (pid_t, TimeInterval) -> FocusedField?)? = nil

        static var system: Environment {
            Environment(ownPID: ProcessInfo.processInfo.processIdentifier,
                trusted: { AXIsProcessTrusted() },
                frontmostPID: { NSWorkspace.shared.frontmostApplication?.processIdentifier },
                running: { NSRunningApplication(processIdentifier: $0).map { !$0.isTerminated } ?? false },
                focusedField: DirectPasteAccessibility.focusedField,
                sameField: { CFEqual($0.identity, $1.identity) },
                activate: { NSRunningApplication(processIdentifier: $0)?.activate(options: []) ?? false },
                write: { ClipboardTransfer.write($0) },
                sendPaste: DirectPasteCoordinator.systemSendPaste,
                pause: { try await Task.sleep(nanoseconds: 20_000_000) },
                inputReleased: {
                    let modifiers = CGEventSource.flagsState(.combinedSessionState)
                    return modifiers.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty &&
                        !CGEventSource.keyState(.combinedSessionState, key: 36) &&
                        !CGEventSource.keyState(.combinedSessionState, key: 76)
                }, ownsKeyboardFocus: { NSApp?.keyWindow != nil },
                prepareAccessibility: { DirectPasteAccessibility.prepareAccessibility($0) },
                focusedFieldBeforeDeadline: { DirectPasteAccessibility.focusedField($0, before: $1) })
        }
    }

    private struct Target {
        let pid: pid_t
        let field: FocusedField?
        var waitingForAccessibility: Bool = false
    }
    private var environment: Environment
    private var target: Target?
    private var previousExternalPID: pid_t?
    private var generation = 0
    private var task: Task<Void, Never>?

    init(environment: Environment? = nil) {
        let environment = environment ?? .system
        self.environment = environment
        if let pid = environment.frontmostPID(), pid != environment.ownPID { previousExternalPID = pid }
    }

    /// Clicking an already open Library or Settings window activates this app
    /// before its button handler runs. Remember app transitions so that path
    /// captures the previous editable field as well as the global-shortcut path.
    /// Callers suppress this during an in-flight paste's own activation.
    func recordActivation(_ pid: pid_t) {
        DirectPasteDiagnostics.log.debug("Activation pid=\(pid) own=\(self.environment.ownPID)")
        if pid != environment.ownPID {
            previousExternalPID = pid
            target = nil
            return
        }
        guard let pid = previousExternalPID else { return }
        cancel(); captureTarget(from: pid, afterDeactivation: true)
    }

    /// Call immediately before taking keyboard focus for the line, Library
    /// or global search. Opening another ClipboardLine view keeps the target.
    func captureTarget() {
        cancel()
        guard let pid = environment.frontmostPID() else { target = nil; return }
        DirectPasteDiagnostics.log.debug("Capture front=\(pid) own=\(self.environment.ownPID)")
        guard pid != environment.ownPID else { return }
        previousExternalPID = pid
        captureTarget(from: pid)
    }
    private func captureTarget(from pid: pid_t, afterDeactivation: Bool = false) {
        guard environment.trusted(), environment.running(pid) else {
            target = nil; return
        }
        if afterDeactivation, let target, target.pid == pid,
           target.waitingForAccessibility || target.field.map({ $0.editable && !$0.secure }) == true {
            // Own activation arrives after the external editor loses key focus.
            // Its AX focus may now be a window/group instead of the captured
            // field. Preserve the original identity and validate it on return.
            return
        }
        var field = environment.focusedField(pid)
        var warmed = false
        if field == nil || field?.editable == false && field?.awaitingAccessibility == true {
            // A single request per capture: Electron currently debounces manual
            // AX enablement for two seconds. Retrying the setter while polling
            // would continually postpone the tree instead of making it ready.
            warmed = environment.prepareAccessibility(pid)
            if warmed { field = environment.focusedField(pid) }
        }
        if let field {
            DirectPasteDiagnostics.log.debug("Captured pid=\(pid) editable=\(field.editable) secure=\(field.secure)")
            if field.editable && !field.secure { target = Target(pid: pid, field: field) }
            else if warmed && field.awaitingAccessibility && !field.secure {
                target = Target(pid: pid, field: nil, waitingForAccessibility: true)
            } else { target = nil }
        } else if warmed {
            target = Target(pid: pid, field: nil, waitingForAccessibility: true)
        } else if afterDeactivation {
            DirectPasteDiagnostics.log.debug("Deferred field pid=\(pid)")
            // Some editors stop exposing focusedUIElement as soon as another
            // app activates. Keep an earlier capture, or resolve their field
            // only after returning to this exact application.
            if target?.pid != pid { target = Target(pid: pid, field: nil) }
        } else { DirectPasteDiagnostics.log.debug("No field pid=\(pid)"); target = nil }
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
    }

    func paste(items: [NSPasteboardItem], dismiss: @escaping () -> Void,
               completion: @escaping (Outcome) -> Void) {
        cancel()
        let token = generation
        guard environment.trusted() else { completion(.permissionRequired); return }
        guard var target = self.target, target.pid != environment.ownPID, environment.running(target.pid) else {
            DirectPasteDiagnostics.log.debug("Paste has no captured target")
            completion(.noTarget); return
        }
        guard !items.isEmpty else { completion(.copyFailed); return }
        let deadline = environment.now() + (target.waitingForAccessibility ? 3.2 : 1.0)
        guard allowedFrontmost(target.pid), validBeforeActivation(&target, before: deadline), allowedFrontmost(target.pid) else { completion(.focusChanged); return }
        guard token == generation else { return }
        guard environment.now() < deadline else { completion(.focusChanged); return }
        // This opening's capture is single-use once the source UI closes,
        // including synchronous dismissal/activation failures below.
        self.target = nil
        dismiss()
        guard token == generation else { return }
        // Dismissal may have activated another app. Do not steal its focus if
        // it differs from both the source UI and the captured destination.
        guard allowedFrontmost(target.pid), validBeforeActivation(&target, afterDismissal: true, before: deadline) else { completion(.focusChanged); return }
        guard environment.now() < deadline else { completion(.focusChanged); return }
        guard environment.activate(target.pid) else { completion(.noTarget); return }
        guard token == generation else { return }
        task = Task { [weak self, target] in
            guard let self else { return }
            var restoredField = target.field
            var stableFocus = 0
            // Ordinary captured fields keep the existing one-second bound.
            // A cold Electron tree can need its two-second enable debounce plus
            // renderer serialization; give only that capture a 3.2-second bound.
            for _ in 0..<(target.waitingForAccessibility ? 160 : 50) {
                guard token == generation, !Task.isCancelled else { return }
                guard environment.now() < deadline else { finish(.focusChanged, token: token, completion: completion); return }
                guard environment.trusted() else { finish(.permissionRequired, token: token, completion: completion); return }
                guard environment.running(target.pid) else { finish(.noTarget, token: token, completion: completion); return }
                let frontmost = environment.frontmostPID()
                if frontmost == target.pid, !ownsKeyboardFocus() {
                    let queriedField = focusedField(target.pid, before: deadline)
                    guard environment.now() < deadline else { finish(.focusChanged, token: token, completion: completion); return }
                    if let field = queriedField {
                        guard !field.secure else {
                            finish(.focusChanged, token: token, completion: completion); return
                        }
                        if field.editable {
                            guard restoredField.map({ self.environment.sameField($0, field) }) ?? true else {
                                finish(.focusChanged, token: token, completion: completion); return
                            }
                            restoredField = field
                            stableFocus += 1
                        } else if target.field != nil || target.waitingForAccessibility && field.awaitingAccessibility {
                            // A known input may briefly be represented by its
                            // noneditable blur container during restoration.
                            // It can never receive a paste: only the original
                            // eligible field below can complete this request.
                            stableFocus = 0
                        } else {
                            finish(.focusChanged, token: token, completion: completion); return
                        }
                    } else {
                        // The frontmost PID often updates before its editor's
                        // AX focus does. Wait for the same captured field.
                        stableFocus = 0
                    }
                    if stableFocus >= 2, environment.inputReleased() {
                        guard token == generation, !Task.isCancelled,
                              environment.frontmostPID() == target.pid, !ownsKeyboardFocus(),
                              let expected = restoredField,
                              let current = focusedField(target.pid, before: deadline), current.editable, !current.secure,
                              environment.sameField(expected, current), environment.now() < deadline else {
                            finish(.focusChanged, token: token, completion: completion); return
                        }
                        // AX callbacks can outlive their opening trust/process
                        // check. Revalidate after the final query, not just at
                        // the beginning of this polling iteration.
                        guard token == generation, !Task.isCancelled else { return }
                        guard environment.trusted() else { finish(.permissionRequired, token: token, completion: completion); return }
                        guard environment.running(target.pid) else { finish(.noTarget, token: token, completion: completion); return }
                        guard environment.frontmostPID() == target.pid, !ownsKeyboardFocus() else { finish(.focusChanged, token: token, completion: completion); return }
                        // Prepare the clipboard only after focus is restored.
                        // Activation delays cannot leave stale data to paste.
                        guard environment.write(items) else { finish(.copyFailed, token: token, completion: completion); return }
                        guard token == generation, !Task.isCancelled else { return }
                        guard environment.frontmostPID() == target.pid, !ownsKeyboardFocus(),
                              let final = focusedField(target.pid, before: deadline), final.editable, !final.secure,
                              environment.sameField(expected, final), environment.now() < deadline else {
                            finish(.focusChanged, token: token, completion: completion); return
                        }
                        guard token == generation, !Task.isCancelled else { return }
                        guard environment.trusted() else { finish(.permissionRequired, token: token, completion: completion); return }
                        guard environment.running(target.pid) else { finish(.noTarget, token: token, completion: completion); return }
                        guard environment.frontmostPID() == target.pid, !ownsKeyboardFocus() else { finish(.focusChanged, token: token, completion: completion); return }
                        // Events remain process-bound even if another app
                        // activates between the last check and dispatch.
                        let result: Outcome = environment.sendPaste(target.pid) ? .pasted : .pasteFailed
                        finish(result, token: token, completion: completion)
                        return
                    }
                } else {
                    stableFocus = 0
                    guard frontmost == nil || frontmost == environment.ownPID || frontmost == target.pid else { finish(.focusChanged, token: token, completion: completion); return }
                }
                do { try await environment.pause() }
                catch { return }
            }
            finish(.focusChanged, token: token, completion: completion)
        }
    }

    private func allowedFrontmost(_ pid: pid_t) -> Bool {
        let front = environment.frontmostPID()
        return front == pid || front == environment.ownPID
    }
    private func ownsKeyboardFocus() -> Bool {
        environment.ownsKeyboardFocus?() ?? (environment.frontmostPID() == environment.ownPID)
    }
    private func focusedField(_ pid: pid_t, before deadline: TimeInterval) -> FocusedField? {
        guard environment.now() < deadline else { return nil }
        if let bounded = environment.focusedFieldBeforeDeadline { return bounded(pid, deadline) }
        return environment.focusedField(pid)
    }
    private func validBeforeActivation(_ target: inout Target, afterDismissal: Bool = false, before deadline: TimeInterval) -> Bool {
        guard let field = focusedField(target.pid, before: deadline) else {
            let front = environment.frontmostPID()
            return ownsKeyboardFocus() || (afterDismissal && (front == target.pid || front == environment.ownPID))
        }
        guard !field.secure else { return false }
        guard field.editable else {
            return (target.field != nil || target.waitingForAccessibility && field.awaitingAccessibility) &&
                (ownsKeyboardFocus() || (afterDismissal && allowedFrontmost(target.pid)))
        }
        if let expected = target.field { return environment.sameField(expected, field) }
        // A cold tree may first expose its editor in either preflight. Latch
        // that positive identity immediately: dismissal/activation must not
        // silently choose a different field of the same application later.
        target = Target(pid: target.pid, field: field, waitingForAccessibility: target.waitingForAccessibility)
        return true
    }
    private func finish(_ outcome: Outcome, token: Int, completion: (Outcome) -> Void) {
        guard token == generation, !Task.isCancelled else { return }
        DirectPasteDiagnostics.log.debug("Paste outcome=\(String(describing: outcome), privacy: .public)")
        task = nil
        target = nil
        completion(outcome)
    }

    private static func systemSendPaste(_ pid: pid_t) -> Bool {
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.postToPid(pid)
        up.postToPid(pid)
        return true
    }
}
