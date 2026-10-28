import AppKit
#if !STANDALONE_TESTS
import XCTest
@testable import Tendedero
#endif

@MainActor private final class DirectPasteFixture {
    let ownPID: pid_t = 900
    let targetPID: pid_t = 101
    let field = NSObject()
    var frontmost: pid_t? = 101
    var trusted = true
    var running = true
    var currentField: DirectPasteCoordinator.FocusedField?
    var writeSucceeds = true
    var activateSucceeds = true
    var sendSucceeds = true
    var activatesImmediately = true
    var writes = [[String]]()
    var activated = [pid_t]()
    var events = [pid_t]()
    var dismissals = 0
    var pauseCount = 0
    var inputReleased = true
    var ownsKeyboardFocusOverride: Bool?
    var fieldReads = 0
    var onPause: (() -> Void)?
    var onWrite: (() -> Void)?
    var onDismiss: (() -> Void)?
    init() { currentField = .init(identity: field, editable: true, secure: false) }
    var environment: DirectPasteCoordinator.Environment {
        .init(ownPID: ownPID, trusted: { self.trusted }, frontmostPID: { self.frontmost },
            running: { $0 == self.targetPID && self.running },
            focusedField: { self.fieldReads += 1; return $0 == self.targetPID ? self.currentField : nil },
            sameField: { $0.identity === $1.identity },
            activate: { pid in
                self.activated.append(pid)
                if self.activatesImmediately { self.frontmost = pid }
                return self.activateSucceeds
            },
            write: { items in
                self.writes.append(items.compactMap { $0.string(forType: .string) })
                self.onWrite?()
                return self.writeSucceeds
            },
            sendPaste: { pid in self.events.append(pid); return self.sendSucceeds },
            pause: { await Task.yield(); self.pauseCount += 1; self.onPause?() },
            inputReleased: { self.inputReleased },
            ownsKeyboardFocus: { self.ownsKeyboardFocusOverride ?? (self.frontmost == self.ownPID) })
    }
    func dismiss() { dismissals += 1; onDismiss?() }
    func prepare(_ service: DirectPasteCoordinator) { service.captureTarget(); frontmost = ownPID }
}

@MainActor final class DirectPasteCoordinatorTests: HistoryTestCase {
    private func wait(_ predicate: () -> Bool) {
        let end = Date().addingTimeInterval(5)
        while !predicate() && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
        XCTAssertTrue(predicate(), "Direct paste did not finish")
    }
    private func paste(_ service: DirectPasteCoordinator, fixture: DirectPasteFixture) -> DirectPasteCoordinator.Outcome? {
        var result: DirectPasteCoordinator.Outcome?
        service.paste(items: ClipboardTransfer.textItems(["First", "Second"]), dismiss: fixture.dismiss) { result = $0 }
        wait { result != nil }
        return result
    }

    func testDirectPasteKeepsOriginalFieldAcrossOwnViewsAndSendsOnlyToCapturedProcess() throws {
        let f = DirectPasteFixture(), service = DirectPasteCoordinator(environment: f.environment)
        f.prepare(service)
        service.captureTarget() // Line → Library → preview must not erase it.
        XCTAssertEqual(paste(service, fixture: f), .pasted)
        XCTAssertEqual(f.writes, [["First\n\nSecond"]])
        XCTAssertEqual(f.dismissals, 1)
        XCTAssertEqual(f.activated, [f.targetPID])
        XCTAssertEqual(f.events, [f.targetPID])
    }

    func testOwnActivationCapturesLatestFieldWhenReturningToAlreadyOpenWindow() throws {
        for hadPreviousCapture in [false, true] {
            let f = DirectPasteFixture()
            if !hadPreviousCapture { f.frontmost = f.ownPID }
            let service = DirectPasteCoordinator(environment: f.environment)
            if hadPreviousCapture { f.prepare(service) }
            // The external app activates before its text field gains focus.
            // Recording that transition must not snapshot a missing/old field.
            f.frontmost = f.targetPID; f.currentField = nil
            service.recordActivation(f.targetPID)
            let latestField = NSObject()
            f.currentField = .init(identity: latestField, editable: true, secure: false)
            // Clicking an already visible Library/Settings window activates
            // ClipboardLine before an explicit open/search handler can run.
            f.frontmost = f.ownPID; service.recordActivation(f.ownPID)
            service.captureTarget() // A subsequent own-view transition preserves it.
            XCTAssertEqual(paste(service, fixture: f), .pasted)
            XCTAssertEqual(f.writes, [["First\n\nSecond"]])
            XCTAssertEqual(f.activated, [f.targetPID]); XCTAssertEqual(f.events, [f.targetPID])
        }
    }

    func testLatestExternalActivationRejectsInvalidTargetInsteadOfReusingOlderApp() throws {
        for invalidTarget in 0..<4 {
            let f = DirectPasteFixture(), latestPID: pid_t = 202, latestField = NSObject()
            var fields: [pid_t: DirectPasteCoordinator.FocusedField] = [
                f.targetPID: .init(identity: f.field, editable: true, secure: false),
                latestPID: .init(identity: latestField, editable: true, secure: false)]
            var latestRunning = true
            var environment = f.environment
            environment.running = { $0 == f.targetPID || ($0 == latestPID && latestRunning) }
            environment.focusedField = { fields[$0] }
            let service = DirectPasteCoordinator(environment: environment)
            f.prepare(service) // Keep a valid old target to catch unsafe fallback.
            f.frontmost = latestPID; service.recordActivation(latestPID)
            switch invalidTarget {
            case 0: fields[latestPID] = nil
            case 1: fields[latestPID] = .init(identity: latestField, editable: false, secure: false)
            case 2: fields[latestPID] = .init(identity: latestField, editable: true, secure: true)
            default: latestRunning = false
            }
            f.frontmost = f.ownPID; service.recordActivation(f.ownPID)
            XCTAssertEqual(paste(service, fixture: f), invalidTarget == 0 ? .focusChanged : .noTarget)
            XCTAssertTrue(f.writes.isEmpty); XCTAssertTrue(f.events.isEmpty)
            XCTAssertEqual(f.activated, invalidTarget == 0 ? [latestPID] : [])
            // A valid retry goes only to the latest external app; the older
            // editable app remains available but must never receive a paste.
            latestRunning = true
            fields[latestPID] = .init(identity: latestField, editable: true, secure: false)
            f.frontmost = latestPID; service.recordActivation(latestPID)
            f.frontmost = f.ownPID; service.recordActivation(f.ownPID)
            XCTAssertEqual(paste(service, fixture: f), .pasted)
            XCTAssertEqual(f.events, [latestPID]); XCTAssertEqual(f.activated, invalidTarget == 0 ? [latestPID, latestPID] : [latestPID])
        }
    }

    func testDirectPasteMissingPermissionTargetAndSecureFieldsNeverChangeClipboardOrSend() throws {
        let untrusted = DirectPasteFixture(); untrusted.trusted = false
        let denied = DirectPasteCoordinator(environment: untrusted.environment); untrusted.prepare(denied)
        XCTAssertEqual(paste(denied, fixture: untrusted), .permissionRequired)
        XCTAssertTrue(untrusted.writes.isEmpty); XCTAssertTrue(untrusted.events.isEmpty); XCTAssertEqual(untrusted.dismissals, 0)
        for field in [nil, DirectPasteCoordinator.FocusedField(identity: NSObject(), editable: false, secure: false),
                      DirectPasteCoordinator.FocusedField(identity: NSObject(), editable: true, secure: true)] {
            let f = DirectPasteFixture(); f.currentField = field
            let service = DirectPasteCoordinator(environment: f.environment); f.prepare(service)
            XCTAssertEqual(paste(service, fixture: f), .noTarget)
            XCTAssertTrue(f.writes.isEmpty); XCTAssertTrue(f.events.isEmpty); XCTAssertEqual(f.dismissals, 0)
        }
        let f = DirectPasteFixture(), service = DirectPasteCoordinator(environment: f.environment)
        f.prepare(service); f.frontmost = 202; service.captureTarget(); f.frontmost = f.ownPID
        XCTAssertEqual(paste(service, fixture: f), .noTarget, "A later external app without an editable target replaces the old capture")
        XCTAssertTrue(f.writes.isEmpty)
    }

    func testDirectPasteChangedFieldAppAndTerminatedTargetAbortBeforeClipboardWrite() throws {
        for mutation in 0..<5 {
            let f = DirectPasteFixture(), service = DirectPasteCoordinator(environment: f.environment)
            f.prepare(service)
            switch mutation {
            case 0: f.currentField = .init(identity: NSObject(), editable: true, secure: false)
            case 1: f.currentField = .init(identity: f.field, editable: true, secure: true)
            case 2: f.frontmost = 202
            case 3: f.running = false
            default: f.trusted = false
            }
            let expected: DirectPasteCoordinator.Outcome = mutation == 3 ? .noTarget : mutation == 4 ? .permissionRequired : .focusChanged
            XCTAssertEqual(paste(service, fixture: f), expected)
            XCTAssertTrue(f.writes.isEmpty); XCTAssertTrue(f.events.isEmpty); XCTAssertEqual(f.dismissals, 0)
        }
    }

    func testDirectPasteWaitsForActivationAndRevalidatesFieldBeforeSending() throws {
        let f = DirectPasteFixture(); f.activatesImmediately = false
        f.onPause = { f.frontmost = f.pauseCount < 3 ? nil : f.targetPID }
        let service = DirectPasteCoordinator(environment: f.environment); f.prepare(service)
        XCTAssertEqual(paste(service, fixture: f), .pasted)
        XCTAssertEqual(f.pauseCount, 4); XCTAssertEqual(f.events, [f.targetPID])
        for mutation in 0..<4 {
            let changed = DirectPasteFixture(); changed.activatesImmediately = false
            changed.onPause = {
                changed.frontmost = changed.targetPID
                switch mutation {
                case 0: changed.currentField = .init(identity: NSObject(), editable: true, secure: false)
                case 1: changed.frontmost = 202
                case 2: changed.running = false
                default: changed.trusted = false
                }
            }
            let blocked = DirectPasteCoordinator(environment: changed.environment); changed.prepare(blocked)
            let expected: DirectPasteCoordinator.Outcome = mutation == 2 ? .noTarget : mutation == 3 ? .permissionRequired : .focusChanged
            XCTAssertEqual(paste(blocked, fixture: changed), expected)
            XCTAssertTrue(changed.writes.isEmpty); XCTAssertTrue(changed.events.isEmpty)
        }
    }

    func testDirectPasteCopyFailureTimeoutAndSenderFailureDoNotReportSuccess() throws {
        let f = DirectPasteFixture(); f.writeSucceeds = false
        let failed = DirectPasteCoordinator(environment: f.environment); f.prepare(failed)
        XCTAssertEqual(paste(failed, fixture: f), .copyFailed)
        XCTAssertEqual(f.dismissals, 1); XCTAssertEqual(f.activated, [f.targetPID]); XCTAssertTrue(f.events.isEmpty)
        let timed = DirectPasteFixture(); timed.activatesImmediately = false
        let timeout = DirectPasteCoordinator(environment: timed.environment); timed.prepare(timeout)
        XCTAssertEqual(paste(timeout, fixture: timed), .focusChanged)
        XCTAssertEqual(timed.pauseCount, 50); XCTAssertTrue(timed.events.isEmpty)
        let unsent = DirectPasteFixture(); unsent.sendSucceeds = false
        let sender = DirectPasteCoordinator(environment: unsent.environment); unsent.prepare(sender)
        XCTAssertEqual(paste(sender, fixture: unsent), .pasteFailed)
    }

    func testDirectPasteCancellationDuringDismissalPreventsActivationAndEvents() throws {
        let f = DirectPasteFixture(), service = DirectPasteCoordinator(environment: f.environment)
        f.prepare(service)
        f.onDismiss = { service.cancel() }
        var completed = false
        service.paste(items: ClipboardTransfer.textItems(["Only a copy"]), dismiss: f.dismiss) { _ in completed = true }
        XCTAssertFalse(completed); XCTAssertTrue(f.writes.isEmpty)
        XCTAssertTrue(f.activated.isEmpty); XCTAssertTrue(f.events.isEmpty)
        let pending = DirectPasteFixture(); pending.activatesImmediately = false
        let cancelled = DirectPasteCoordinator(environment: pending.environment); pending.prepare(cancelled)
        pending.onPause = { cancelled.cancel(); pending.frontmost = pending.targetPID }
        cancelled.paste(items: ClipboardTransfer.textItems(["No delayed event"]), dismiss: pending.dismiss) { _ in completed = true }
        wait { pending.pauseCount > 0 }
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        XCTAssertFalse(completed); XCTAssertTrue(pending.events.isEmpty)
    }

    func testDirectPasteRestoresMissingInactiveFocusBeforeWritingClipboard() throws {
        let f = DirectPasteFixture(), service = DirectPasteCoordinator(environment: f.environment)
        f.prepare(service)
        f.currentField = nil // The editor clears AX focus while inactive.
        f.onPause = {
            XCTAssertTrue(f.writes.isEmpty)
            if f.pauseCount == 3 { f.currentField = .init(identity: f.field, editable: true, secure: false) }
        }
        XCTAssertEqual(paste(service, fixture: f), .pasted)
        XCTAssertEqual(f.pauseCount, 4)
        XCTAssertEqual(f.events, [f.targetPID]); XCTAssertEqual(f.writes.count, 1)
    }

    func testDirectPasteCapturesBlurredEditorAfterReturningFromExistingLibrary() throws {
        let f = DirectPasteFixture(), service = DirectPasteCoordinator(environment: f.environment)
        service.recordActivation(f.targetPID)
        f.frontmost = f.ownPID; f.currentField = nil
        service.recordActivation(f.ownPID)
        f.onPause = { f.currentField = .init(identity: f.field, editable: true, secure: false) }
        XCTAssertEqual(paste(service, fixture: f), .pasted)
        XCTAssertEqual(f.events, [f.targetPID])
    }

    func testDirectPasteDeferredFocusStillRejectsSecureOrChangedOriginalField() throws {
        for secure in [false, true] {
            let f = DirectPasteFixture(), service = DirectPasteCoordinator(environment: f.environment)
            if secure {
                f.frontmost = f.ownPID; f.currentField = nil
                service.recordActivation(f.ownPID)
            } else { f.prepare(service); f.currentField = nil }
            f.onPause = { f.currentField = .init(identity: NSObject(), editable: true, secure: secure) }
            XCTAssertEqual(paste(service, fixture: f), .focusChanged)
            XCTAssertTrue(f.writes.isEmpty); XCTAssertTrue(f.events.isEmpty)
        }
    }

    func testDirectPasteWaitsForShortcutReleaseAndStableFocus() throws {
        let f = DirectPasteFixture(); f.inputReleased = false
        let service = DirectPasteCoordinator(environment: f.environment); f.prepare(service)
        f.onPause = {
            XCTAssertTrue(f.events.isEmpty); XCTAssertTrue(f.writes.isEmpty)
            if f.pauseCount == 4 { f.inputReleased = true }
        }
        XCTAssertEqual(paste(service, fixture: f), .pasted)
        XCTAssertEqual(f.pauseCount, 4); XCTAssertEqual(f.events, [f.targetPID])
    }

    func testDirectPasteRechecksFieldAndApplicationAfterClipboardWrite() throws {
        for appChanged in [false, true] {
            let f = DirectPasteFixture(), service = DirectPasteCoordinator(environment: f.environment)
            f.prepare(service)
            f.onWrite = {
                if appChanged { f.frontmost = 202 }
                else { f.currentField = .init(identity: NSObject(), editable: true, secure: false) }
            }
            XCTAssertEqual(paste(service, fixture: f), .focusChanged)
            XCTAssertEqual(f.writes.count, 1); XCTAssertTrue(f.events.isEmpty)
        }
    }

    func testDirectPasteDismissalCanActivateEditorBeforeItsFocusReturns() throws {
        let f = DirectPasteFixture(), service = DirectPasteCoordinator(environment: f.environment)
        f.prepare(service)
        f.onDismiss = { f.frontmost = f.targetPID; f.currentField = nil }
        f.onPause = { f.currentField = .init(identity: f.field, editable: true, secure: false) }
        XCTAssertEqual(paste(service, fixture: f), .pasted)
        XCTAssertEqual(f.events, [f.targetPID])
    }

    func testDirectPasteDoesNotReuseOldFieldOnAnotherVisitToSameApp() throws {
        for failure in ["none", "send", "activation", "dismissalFocus"] {
            let f = DirectPasteFixture(), service = DirectPasteCoordinator(environment: f.environment)
            f.prepare(service)
            f.sendSucceeds = failure != "send"
            f.activateSucceeds = failure != "activation"
            if failure == "dismissalFocus" {
                f.onDismiss = { f.frontmost = f.targetPID; f.currentField = .init(identity: NSObject(), editable: true, secure: false) }
            }
            let expected: DirectPasteCoordinator.Outcome = failure == "send" ? .pasteFailed : failure == "activation" ? .noTarget : failure == "dismissalFocus" ? .focusChanged : .pasted
            XCTAssertEqual(paste(service, fixture: f), expected)
            let oldEventCount = f.events.count, nextField = NSObject()
            // The paste activation was intentionally not recorded by AppDelegate.
            // A later click on Library must resolve this visit's newly focused B.
            f.currentField = nil; f.frontmost = f.ownPID
            f.sendSucceeds = true; f.activateSucceeds = true; f.onDismiss = nil
            service.recordActivation(f.ownPID)
            f.onPause = { f.currentField = .init(identity: nextField, editable: true, secure: false) }
            XCTAssertEqual(paste(service, fixture: f), .pasted)
            XCTAssertEqual(f.events.count, oldEventCount + 1)
            XCTAssertEqual(f.events.last, f.targetPID)
        }
    }

    func testOwnActivationPreservesCapturedFieldThroughNoneditableBlurContainer() throws {
        for restored in ["original", "changed", "secure", "noneditable"] {
            let f = DirectPasteFixture(), service = DirectPasteCoordinator(environment: f.environment)
            f.prepare(service)
            f.currentField = .init(identity: NSObject(), editable: false, secure: false)
            service.recordActivation(f.ownPID)
            f.onPause = {
                XCTAssertTrue(f.writes.isEmpty); XCTAssertTrue(f.events.isEmpty)
                guard f.pauseCount == 2 else { return }
                switch restored {
                case "original": f.currentField = .init(identity: f.field, editable: true, secure: false)
                case "changed": f.currentField = .init(identity: NSObject(), editable: true, secure: false)
                case "secure": f.currentField = .init(identity: f.field, editable: true, secure: true)
                default: break
                }
            }
            XCTAssertEqual(paste(service, fixture: f), restored == "original" ? .pasted : .focusChanged)
            XCTAssertEqual(f.dismissals, 1); XCTAssertEqual(f.activated, [f.targetPID])
            XCTAssertEqual(f.writes.count, restored == "original" ? 1 : 0)
            XCTAssertEqual(f.events, restored == "original" ? [f.targetPID] : [])
        }
    }

    func testDirectPasteWaitsForNonactivatingSourceToReleaseKeyFocus() throws {
        let f = DirectPasteFixture(), service = DirectPasteCoordinator(environment: f.environment)
        service.captureTarget()
        // A floating panel owns key focus, but the workspace never changed PID.
        f.ownsKeyboardFocusOverride = true
        f.onPause = {
            XCTAssertTrue(f.writes.isEmpty); XCTAssertTrue(f.events.isEmpty)
            if f.pauseCount == 2 { f.ownsKeyboardFocusOverride = false }
        }
        XCTAssertEqual(paste(service, fixture: f), .pasted)
        XCTAssertEqual(f.pauseCount, 3); XCTAssertEqual(f.events, [f.targetPID])
    }

    func testAppCapturePolicyRefreshesExternalReentryAndPreservesOwnPanelHandoffs() throws {
        let data = try SyntheticFixture(); defer { data.cleanup() }
        let line = Line(defaults: data.defaults, inbox: data.inbox, now: { data.date }, breeze: false,
            copyImage: { _ in }, copyText: { _ in })
        let f = DirectPasteFixture(), service = DirectPasteCoordinator(environment: f.environment)
        f.ownsKeyboardFocusOverride = false
        let app = AppDelegate(line: line, watchesFiles: false, directPaste: service,
            ownsKeyboardFocus: { f.ownsKeyboardFocusOverride == true })
        // The same capture method is called before line/Library/search/preview/
        // Actions take focus. No app launch, windows, AX or system keys are used.
        app.capturePasteTarget()
        XCTAssertEqual(f.fieldReads, 1)
        f.ownsKeyboardFocusOverride = true
        f.currentField = .init(identity: NSObject(), editable: false, secure: false)
        app.capturePasteTarget()
        XCTAssertEqual(f.fieldReads, 1, "An own-panel handoff must not query the blurred external editor")
        let latest = NSObject()
        f.ownsKeyboardFocusOverride = false
        f.currentField = .init(identity: latest, editable: true, secure: false)
        app.capturePasteTarget()
        XCTAssertEqual(f.fieldReads, 2, "A later field in the same external app must replace the old capture")
        f.ownsKeyboardFocusOverride = true
        f.currentField = .init(identity: NSObject(), editable: false, secure: false)
        app.capturePasteTarget()
        XCTAssertEqual(f.fieldReads, 2)
        f.onDismiss = { f.ownsKeyboardFocusOverride = false }
        f.onPause = { f.currentField = .init(identity: latest, editable: true, secure: false) }
        XCTAssertEqual(paste(service, fixture: f), .pasted)
        XCTAssertEqual(f.events, [f.targetPID]); XCTAssertEqual(f.writes.count, 1)
    }

    func testBrowsingPresentationKeepsPreBlurFieldBeforeOwnKeyWindowExists() throws {
        for missingFocus in [false, true] {
            let data = try SyntheticFixture(); defer { data.cleanup() }
            let line = Line(defaults: data.defaults, inbox: data.inbox, now: { data.date }, breeze: false,
                copyImage: { _ in }, copyText: { _ in })
            let f = DirectPasteFixture(), service = DirectPasteCoordinator(environment: f.environment)
            f.ownsKeyboardFocusOverride = false
            let app = AppDelegate(line: line, watchesFiles: false, directPaste: service,
                ownsKeyboardFocus: { f.ownsKeyboardFocusOverride == true })
            app.withPasteTargetForFocusHandoff {
                XCTAssertEqual(f.fieldReads, 1, "Capture must precede window ordering")
                // orderFrontRegardless can blur a web editor while keyWindow
                // is still nil. Nested refresh/search focus callbacks must
                // preserve the identity captured before that presentation.
                f.currentField = missingFocus ? nil : .init(identity: NSObject(), editable: false, secure: false)
                app.capturePasteTarget()
                app.withPasteTargetForFocusHandoff { app.capturePasteTarget() }
                XCTAssertEqual(f.fieldReads, 1)
            }
            f.ownsKeyboardFocusOverride = true
            service.recordActivation(f.ownPID)
            XCTAssertEqual(f.fieldReads, 1, "Own activation must preserve the early capture too")
            f.onDismiss = { f.ownsKeyboardFocusOverride = false }
            f.onPause = { f.currentField = .init(identity: f.field, editable: true, secure: false) }
            XCTAssertEqual(paste(service, fixture: f), .pasted)
            XCTAssertEqual(f.events, [f.targetPID]); XCTAssertEqual(f.writes.count, 1)
        }
    }

    func testBrowsingPresentationScopeDoesNotRetainStaleFieldOnLaterExternalEntry() throws {
        for destination in ["new", "missing", "readonly", "secure"] {
            let data = try SyntheticFixture(); defer { data.cleanup() }
            let line = Line(defaults: data.defaults, inbox: data.inbox, now: { data.date }, breeze: false,
                copyImage: { _ in }, copyText: { _ in })
            let f = DirectPasteFixture(), service = DirectPasteCoordinator(environment: f.environment)
            f.ownsKeyboardFocusOverride = false
            let app = AppDelegate(line: line, watchesFiles: false, directPaste: service,
                ownsKeyboardFocus: { f.ownsKeyboardFocusOverride == true })
            app.withPasteTargetForFocusHandoff {
                f.currentField = nil
                app.capturePasteTarget()
            }
            let next = NSObject()
            switch destination {
            case "missing": f.currentField = nil
            case "readonly": f.currentField = .init(identity: next, editable: false, secure: false)
            case "secure": f.currentField = .init(identity: next, editable: true, secure: true)
            default: f.currentField = .init(identity: next, editable: true, secure: false)
            }
            app.withPasteTargetForFocusHandoff {}
            XCTAssertEqual(f.fieldReads, 2, "A new visit must query the current external field")
            f.ownsKeyboardFocusOverride = true
            f.onDismiss = { f.ownsKeyboardFocusOverride = false }
            XCTAssertEqual(paste(service, fixture: f), destination == "new" ? .pasted : .noTarget)
            XCTAssertEqual(f.writes.count, destination == "new" ? 1 : 0)
            XCTAssertEqual(f.events, destination == "new" ? [f.targetPID] : [])
        }
    }

    func testBrowsingPresentationStillRejectsFieldChangedAfterCapture() throws {
        let data = try SyntheticFixture(); defer { data.cleanup() }
        let line = Line(defaults: data.defaults, inbox: data.inbox, now: { data.date }, breeze: false,
            copyImage: { _ in }, copyText: { _ in })
        let f = DirectPasteFixture(), service = DirectPasteCoordinator(environment: f.environment)
        f.ownsKeyboardFocusOverride = false
        let app = AppDelegate(line: line, watchesFiles: false, directPaste: service,
            ownsKeyboardFocus: { f.ownsKeyboardFocusOverride == true })
        app.withPasteTargetForFocusHandoff {
            f.currentField = nil; app.capturePasteTarget()
        }
        f.ownsKeyboardFocusOverride = true
        f.onDismiss = { f.ownsKeyboardFocusOverride = false }
        f.onPause = { f.currentField = .init(identity: NSObject(), editable: true, secure: false) }
        XCTAssertEqual(paste(service, fixture: f), .focusChanged)
        XCTAssertTrue(f.writes.isEmpty); XCTAssertTrue(f.events.isEmpty)
    }

    func testNewOwnBrowsingActionCancelsPendingPasteWithoutSendingOrCopying() throws {
        let data = try SyntheticFixture(); defer { data.cleanup() }
        let line = Line(defaults: data.defaults, inbox: data.inbox, now: { data.date }, breeze: false,
            copyImage: { _ in }, copyText: { _ in })
        let f = DirectPasteFixture(); f.activatesImmediately = false
        let service = DirectPasteCoordinator(environment: f.environment)
        let app = AppDelegate(line: line, watchesFiles: false, directPaste: service,
            ownsKeyboardFocus: { true })
        f.prepare(service)
        var completed = false
        f.onPause = {
            // Another own surface opens while the first request is waiting for
            // external focus. It must cancel rather than paste into that app.
            app.capturePasteTarget()
            f.frontmost = f.targetPID
        }
        service.paste(items: ClipboardTransfer.textItems(["Cancelled synthetic paste"]), dismiss: f.dismiss) { _ in completed = true }
        wait { f.pauseCount > 0 }
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        XCTAssertFalse(completed); XCTAssertTrue(f.events.isEmpty); XCTAssertTrue(f.writes.isEmpty)
    }

    func testPreviewMouseReentryCapturesLatestExternalFieldBeforeTakingFocus() throws {
        let data = try SyntheticFixture(); defer { data.cleanup() }
        let line = Line(defaults: data.defaults, inbox: data.inbox, now: { data.date }, breeze: false,
            copyImage: { _ in }, copyText: { _ in })
        let f = DirectPasteFixture(), service = DirectPasteCoordinator(environment: f.environment)
        f.ownsKeyboardFocusOverride = false
        let app = AppDelegate(line: line, watchesFiles: false, directPaste: service,
            ownsKeyboardFocus: { f.ownsKeyboardFocusOverride == true })
        app.capturePasteTarget()
        f.ownsKeyboardFocusOverride = true
        f.currentField = nil
        // Showing or switching our previews preserves A while the editor is
        // blurred. No window or native input is needed to exercise this path.
        app.capturePasteTarget()
        XCTAssertEqual(f.fieldReads, 1)

        let latest = NSObject()
        f.ownsKeyboardFocusOverride = false
        f.currentField = .init(identity: latest, editable: true, secure: false)
        let click = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        // The workspace PID never changes for either nonactivating panel visit.
        // sendEvent uses this helper before super makes the preview key.
        ActionPreviewPanel.prepareForMouseKeyFocus(click, isKeyWindow: false) {
            XCTAssertFalse(f.ownsKeyboardFocusOverride == true)
            app.capturePasteTarget()
        }
        XCTAssertEqual(f.fieldReads, 2)
        f.ownsKeyboardFocusOverride = true
        f.currentField = .init(identity: NSObject(), editable: false, secure: false)
        f.onDismiss = { f.ownsKeyboardFocusOverride = false }
        f.onPause = { f.currentField = .init(identity: latest, editable: true, secure: false) }
        XCTAssertEqual(paste(service, fixture: f), .pasted)
        XCTAssertEqual(f.events, [f.targetPID]); XCTAssertEqual(f.writes.count, 1)
    }

    func testPreviewMouseFocusPreservesOwnHandoffsAndIgnoresNonEntryEvents() throws {
        let data = try SyntheticFixture(); defer { data.cleanup() }
        let line = Line(defaults: data.defaults, inbox: data.inbox, now: { data.date }, breeze: false,
            copyImage: { _ in }, copyText: { _ in })
        let f = DirectPasteFixture(), service = DirectPasteCoordinator(environment: f.environment)
        f.ownsKeyboardFocusOverride = false
        let app = AppDelegate(line: line, watchesFiles: false, directPaste: service,
            ownsKeyboardFocus: { f.ownsKeyboardFocusOverride == true })
        app.capturePasteTarget()
        f.ownsKeyboardFocusOverride = true
        f.currentField = .init(identity: NSObject(), editable: false, secure: false)
        var entries = 0
        let onEntry = { entries += 1; app.capturePasteTarget() }
        func mouse(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        ActionPreviewPanel.prepareForMouseKeyFocus(key, isKeyWindow: false, onEntry: onEntry)
        ActionPreviewPanel.prepareForMouseKeyFocus(mouse(.leftMouseUp), isKeyWindow: false, onEntry: onEntry)
        ActionPreviewPanel.prepareForMouseKeyFocus(mouse(.rightMouseDown), isKeyWindow: false, onEntry: onEntry)
        ActionPreviewPanel.prepareForMouseKeyFocus(mouse(.leftMouseDown), isKeyWindow: true, onEntry: onEntry)
        XCTAssertEqual(entries, 0)
        // A click into a different own preview runs the boundary, but the
        // owning application's key window keeps the original external capture.
        ActionPreviewPanel.prepareForMouseKeyFocus(mouse(.leftMouseDown), isKeyWindow: false, onEntry: onEntry)
        XCTAssertEqual(entries, 1); XCTAssertEqual(f.fieldReads, 1)
        // The programmatic own-view path also leaves this mouse callback idle.
        app.capturePasteTarget()
        XCTAssertEqual(entries, 1); XCTAssertEqual(f.fieldReads, 1)
        f.onDismiss = { f.ownsKeyboardFocusOverride = false }
        f.onPause = { f.currentField = .init(identity: f.field, editable: true, secure: false) }
        XCTAssertEqual(paste(service, fixture: f), .pasted)
        XCTAssertEqual(f.events, [f.targetPID]); XCTAssertEqual(f.writes.count, 1)
    }

    func testPasteDismissalBlocksPointerReopenUntilMenuBarExit() throws {
        let data = try SyntheticFixture(); defer { data.cleanup() }
        let line = Line(defaults: data.defaults, inbox: data.inbox, now: { data.date }, breeze: false,
            copyImage: { _ in }, copyText: { _ in })
        let f = DirectPasteFixture(), service = DirectPasteCoordinator(environment: f.environment)
        f.ownsKeyboardFocusOverride = false
        let app = AppDelegate(line: line, watchesFiles: false, directPaste: service,
            ownsKeyboardFocus: { f.ownsKeyboardFocusOverride == true })
        app.capturePasteTarget()
        XCTAssertTrue(app.pointerRevealIsAllowed(inMenuBar: true))
        f.ownsKeyboardFocusOverride = true
        f.onDismiss = {
            app.dismissBrowsingForPaste()
            f.ownsKeyboardFocusOverride = false
            XCTAssertFalse(app.pointerRevealIsAllowed(inMenuBar: true))
        }
        f.onPause = {
            // This is the same production gate consulted on every mouse timer
            // tick, including while the coordinator restores the editor.
            XCTAssertFalse(app.pointerRevealIsAllowed(inMenuBar: true))
        }
        XCTAssertEqual(paste(service, fixture: f), .pasted)
        XCTAssertEqual(f.activated, [f.targetPID]); XCTAssertEqual(f.events, [f.targetPID])
        XCTAssertFalse(app.pointerRevealIsAllowed(inMenuBar: true), "A resting pointer must not reopen after completion")
        XCTAssertFalse(app.pointerRevealIsAllowed(inMenuBar: false), "Leaving clears suppression without opening the shelf")
        XCTAssertTrue(app.pointerRevealIsAllowed(inMenuBar: true), "A fresh entry can start the normal reveal dwell")
    }

    func testShelfMouseReentryRefreshesTargetBeforeLibraryActionTakesFocus() throws {
        let data = try SyntheticFixture(); defer { data.cleanup() }
        let line = Line(defaults: data.defaults, inbox: data.inbox, now: { data.date }, breeze: false,
            copyImage: { _ in }, copyText: { _ in })
        let f = DirectPasteFixture(), service = DirectPasteCoordinator(environment: f.environment)
        f.ownsKeyboardFocusOverride = false
        let app = AppDelegate(line: line, watchesFiles: false, directPaste: service,
            ownsKeyboardFocus: { f.ownsKeyboardFocusOverride == true })
        app.capturePasteTarget()

        // The line remains visible while a different field in the same app is
        // selected. The workspace PID does not change, so activation cannot
        // refresh this capture for the upcoming shelf -> Library action.
        let latest = NSObject()
        f.currentField = .init(identity: latest, editable: true, secure: false)
        let panel = LinePanel(content: NSView())
        panel.onBeforeMouseKeyFocus = {
            XCTAssertFalse(f.ownsKeyboardFocusOverride == true)
            app.capturePasteTarget()
        }
        let click = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        // sendEvent invokes this boundary before search focus, child controls
        // and super. Do not post events or show a window in this regression.
        panel.prepareForMouseKeyFocus(click, isFocused: false)
        XCTAssertEqual(f.fieldReads, 2)
        f.ownsKeyboardFocusOverride = true
        f.currentField = .init(identity: NSObject(), editable: false, secure: false)
        app.capturePasteTarget() // Library action now runs with our panel key.
        XCTAssertEqual(f.fieldReads, 2)
        f.onDismiss = { f.ownsKeyboardFocusOverride = false }
        f.onPause = { f.currentField = .init(identity: latest, editable: true, secure: false) }
        XCTAssertEqual(paste(service, fixture: f), .pasted)
        XCTAssertEqual(f.events, [f.targetPID]); XCTAssertEqual(f.writes.count, 1)
    }

    func testShelfMouseCapturePreservesOwnHandoffsAndIgnoresNonEntryEvents() throws {
        let data = try SyntheticFixture(); defer { data.cleanup() }
        let line = Line(defaults: data.defaults, inbox: data.inbox, now: { data.date }, breeze: false,
            copyImage: { _ in }, copyText: { _ in })
        let f = DirectPasteFixture(), service = DirectPasteCoordinator(environment: f.environment)
        f.ownsKeyboardFocusOverride = false
        let app = AppDelegate(line: line, watchesFiles: false, directPaste: service,
            ownsKeyboardFocus: { f.ownsKeyboardFocusOverride == true })
        app.capturePasteTarget()
        f.ownsKeyboardFocusOverride = true
        f.currentField = .init(identity: NSObject(), editable: false, secure: false)
        let panel = LinePanel(content: NSView())
        var entries = 0
        panel.onBeforeMouseKeyFocus = { entries += 1; app.capturePasteTarget() }
        func mouse(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
        panel.prepareForMouseKeyFocus(key, isFocused: false)
        panel.prepareForMouseKeyFocus(mouse(.leftMouseUp), isFocused: false)
        panel.prepareForMouseKeyFocus(mouse(.rightMouseDown), isFocused: false)
        panel.prepareForMouseKeyFocus(mouse(.leftMouseDown), isFocused: true)
        XCTAssertEqual(entries, 0)
        // An own-preview -> shelf mouse handoff runs the boundary, but our
        // existing key window protects the original external field capture.
        panel.prepareForMouseKeyFocus(mouse(.leftMouseDown), isFocused: false)
        XCTAssertEqual(entries, 1); XCTAssertEqual(f.fieldReads, 1)
        f.onDismiss = { f.ownsKeyboardFocusOverride = false }
        f.onPause = { f.currentField = .init(identity: f.field, editable: true, secure: false) }
        XCTAssertEqual(paste(service, fixture: f), .pasted)
        XCTAssertEqual(f.events, [f.targetPID]); XCTAssertEqual(f.writes.count, 1)
    }
}

@MainActor final class DirectPasteColdTreeTests: HistoryTestCase {
    private func wait(_ predicate: () -> Bool) {
        let end = Date().addingTimeInterval(5)
        while !predicate() && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
        XCTAssertTrue(predicate(), "Cold-tree paste did not finish")
    }
    private func paste(_ service: DirectPasteCoordinator, fixture f: DirectPasteFixture) -> DirectPasteCoordinator.Outcome? {
        var result: DirectPasteCoordinator.Outcome?
        service.paste(items: ClipboardTransfer.textItems(["Cold-tree exact payload"]), dismiss: f.dismiss) { result = $0 }
        wait { result != nil }; return result
    }
    private func placeholder() -> DirectPasteCoordinator.FocusedField {
        .init(identity: NSObject(), editable: false, secure: false, awaitingAccessibility: true)
    }
    func testOneShotWarmupOutlastsElectronDebounceAndPreservesPendingCaptureAcrossOwnActivation() {
        let f = DirectPasteFixture(); f.currentField = nil; var requests = [pid_t]()
        var environment = f.environment; environment.prepareAccessibility = { requests.append($0); return true }
        let service = DirectPasteCoordinator(environment: environment)
        f.prepare(service); f.currentField = placeholder()
        service.recordActivation(f.ownPID); service.captureTarget()
        f.onPause = { if f.pauseCount == 110 { f.currentField = .init(identity: f.field, editable: true, secure: false) } }
        XCTAssertEqual(paste(service, fixture: f), .pasted)
        XCTAssertEqual(requests, [f.targetPID], "Per-poll setters would restart Electron's two-second debounce")
        XCTAssertGreaterThan(f.pauseCount, 100); XCTAssertLessThan(f.pauseCount, 160)
        XCTAssertEqual(f.writes, [["Cold-tree exact payload"]]); XCTAssertEqual(f.events, [f.targetPID])
    }
    func testColdEditorResolvedBeforeDismissalCannotBeReplacedByAnotherFieldOfTheSameProcess() {
        let f = DirectPasteFixture(); f.currentField = nil
        var environment = f.environment; environment.prepareAccessibility = { _ in true }
        let service = DirectPasteCoordinator(environment: environment); f.prepare(service)
        f.currentField = .init(identity: f.field, editable: true, secure: false)
        f.onDismiss = { f.currentField = .init(identity: NSObject(), editable: true, secure: false) }
        XCTAssertEqual(paste(service, fixture: f), .focusChanged)
        XCTAssertEqual(f.dismissals, 1); XCTAssertTrue(f.activated.isEmpty)
        XCTAssertTrue(f.writes.isEmpty); XCTAssertTrue(f.events.isEmpty)
    }
    func testColdEditorFirstResolvedAfterDismissalIsPinnedBeforeActivatingTheApplication() {
        let f = DirectPasteFixture(); f.currentField = nil
        var environment = f.environment; environment.prepareAccessibility = { _ in true }
        environment.activate = { pid in
            f.activated.append(pid); f.frontmost = pid
            f.currentField = .init(identity: NSObject(), editable: true, secure: false)
            return true
        }
        let service = DirectPasteCoordinator(environment: environment); f.prepare(service)
        f.currentField = placeholder()
        f.onDismiss = { f.currentField = .init(identity: f.field, editable: true, secure: false) }
        XCTAssertEqual(paste(service, fixture: f), .focusChanged)
        XCTAssertEqual(f.activated, [f.targetPID]); XCTAssertTrue(f.writes.isEmpty); XCTAssertTrue(f.events.isEmpty)
    }
    func testColdEditorResolvedBeforeDismissalMayBlurButMustRestoreThatExactIdentity() {
        let f = DirectPasteFixture(); f.currentField = nil
        var environment = f.environment; environment.prepareAccessibility = { _ in true }
        let service = DirectPasteCoordinator(environment: environment); f.prepare(service)
        f.currentField = .init(identity: f.field, editable: true, secure: false)
        f.onDismiss = { f.currentField = self.placeholder() }
        f.onPause = { f.currentField = .init(identity: f.field, editable: true, secure: false) }
        XCTAssertEqual(paste(service, fixture: f), .pasted)
        XCTAssertEqual(f.events, [f.targetPID]); XCTAssertEqual(f.writes, [["Cold-tree exact payload"]])
    }
    func testImmediateWarmupCanExposeTheOriginalEditorWithoutExtendingItsPasteWait() {
        let f = DirectPasteFixture(); f.currentField = nil; var requests = 0
        var environment = f.environment; environment.prepareAccessibility = { _ in requests += 1; f.currentField = .init(identity: f.field, editable: true, secure: false); return true }
        let service = DirectPasteCoordinator(environment: environment); f.prepare(service)
        XCTAssertEqual(paste(service, fixture: f), .pasted); XCTAssertEqual(requests, 1); XCTAssertEqual(f.pauseCount, 1)
    }
    func testWarmupNeverTurnsIneligibleOrSecureFocusIntoAnEditableFallback() {
        for secure in [false, true] {
            let f = DirectPasteFixture(); f.currentField = nil
            var environment = f.environment; environment.prepareAccessibility = { _ in true }
            let service = DirectPasteCoordinator(environment: environment); f.prepare(service)
            f.currentField = placeholder()
            f.onPause = { if f.pauseCount == 110 { f.currentField = .init(identity: f.field, editable: false, secure: secure) } }
            XCTAssertEqual(paste(service, fixture: f), .focusChanged)
            XCTAssertTrue(f.writes.isEmpty); XCTAssertTrue(f.events.isEmpty)
        }
    }
    func testColdTreeTimeoutIsBoundedAndNeverWritesOrSendsToAnUnknownContainer() {
        for absent in [false, true] {
            let f = DirectPasteFixture(); f.currentField = nil; var requests = 0
            var environment = f.environment; environment.prepareAccessibility = { _ in requests += 1; return true }
            let service = DirectPasteCoordinator(environment: environment); f.prepare(service)
            f.currentField = absent ? nil : placeholder()
            XCTAssertEqual(paste(service, fixture: f), .focusChanged); XCTAssertEqual(f.pauseCount, 160); XCTAssertEqual(requests, 1)
            XCTAssertTrue(f.writes.isEmpty); XCTAssertTrue(f.events.isEmpty)
        }
    }
    func testWarmupStopsWhenThirdAppTakesFocusOrPermissionAndProcessDisappear() {
        for mutation in 0..<3 {
            let f = DirectPasteFixture(); f.currentField = nil
            var environment = f.environment; environment.prepareAccessibility = { _ in true }
            let service = DirectPasteCoordinator(environment: environment); f.prepare(service); f.currentField = placeholder()
            f.onPause = { if f.pauseCount == 30 { if mutation == 0 { f.frontmost = 202 } else if mutation == 1 { f.trusted = false } else { f.running = false } } }
            XCTAssertEqual(paste(service, fixture: f), mutation == 0 ? .focusChanged : mutation == 1 ? .permissionRequired : .noTarget)
            XCTAssertEqual(f.pauseCount, 30); XCTAssertTrue(f.writes.isEmpty); XCTAssertTrue(f.events.isEmpty)
        }
    }
    func testCancelDuringWarmupCannotLaterWriteOrPasteIntoTheOldField() {
        let f = DirectPasteFixture(); f.currentField = nil
        var environment = f.environment; environment.prepareAccessibility = { _ in true }
        let service = DirectPasteCoordinator(environment: environment); f.prepare(service); f.currentField = placeholder()
        var completed = false
        f.onPause = { if f.pauseCount == 30 { service.cancel(); f.currentField = .init(identity: f.field, editable: true, secure: false) } }
        service.paste(items: ClipboardTransfer.textItems(["Must never paste"]), dismiss: f.dismiss) { _ in completed = true }
        wait { f.pauseCount >= 30 }; RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        XCTAssertFalse(completed); XCTAssertTrue(f.writes.isEmpty); XCTAssertTrue(f.events.isEmpty)
    }
    func testFirstResolvedColdEditorStillRequiresStableExactIdentityAndPostWriteRevalidation() {
        for changeDuringWrite in [false, true] {
            let f = DirectPasteFixture(); f.currentField = nil
            var environment = f.environment; environment.prepareAccessibility = { _ in true }
            let service = DirectPasteCoordinator(environment: environment); f.prepare(service); f.currentField = placeholder()
            f.onPause = { if f.pauseCount == 110 { f.currentField = .init(identity: f.field, editable: true, secure: false) }
                if !changeDuringWrite && f.pauseCount == 111 { f.currentField = .init(identity: NSObject(), editable: true, secure: false) } }
            if changeDuringWrite { f.onWrite = { f.currentField = .init(identity: NSObject(), editable: true, secure: false) } }
            XCTAssertEqual(paste(service, fixture: f), .focusChanged); XCTAssertTrue(f.events.isEmpty)
            XCTAssertEqual(f.writes.count, changeDuringWrite ? 1 : 0)
        }
    }
    func testColdTreeDeadlineIncludesSlowAXQueriesInsteadOfOnlyCountingPollingPauses() {
        let f = DirectPasteFixture(); f.currentField = nil
        var clock: TimeInterval = 0, queryCost: TimeInterval = 0, reads = 0
        var environment = f.environment
        environment.now = { clock }
        environment.prepareAccessibility = { _ in true }
        environment.focusedField = { _ in reads += 1; clock += queryCost; return f.currentField }
        let service = DirectPasteCoordinator(environment: environment); f.prepare(service)
        f.currentField = placeholder(); queryCost = 0.8; reads = 0
        XCTAssertEqual(paste(service, fixture: f), .focusChanged)
        XCTAssertLessThanOrEqual(reads, 5); XCTAssertLessThan(f.pauseCount, 160)
        XCTAssertTrue(f.writes.isEmpty); XCTAssertTrue(f.events.isEmpty)
    }
    func testDeadlineAwareResolverOwnsEveryPasteQueryIncludingMissingResultsWithoutUnboundedFallback() {
        let f = DirectPasteFixture(); var unboundedReads = 0, boundedReads = 0
        var environment = f.environment; environment.now = { 123 }
        environment.focusedField = { _ in unboundedReads += 1; return f.currentField }
        environment.focusedFieldBeforeDeadline = { pid, deadline in
            XCTAssertEqual(pid, f.targetPID); XCTAssertEqual(deadline, 124)
            boundedReads += 1
            return boundedReads <= 3 ? nil : f.currentField
        }
        let service = DirectPasteCoordinator(environment: environment); f.prepare(service)
        XCTAssertEqual(paste(service, fixture: f), .pasted)
        XCTAssertEqual(unboundedReads, 1, "Only capture may use the ordinary resolver; nil from the bounded resolver is final")
        XCTAssertGreaterThan(boundedReads, 3); XCTAssertEqual(f.events, [f.targetPID])
    }
    func testDeadlineExpiredByFinalAXReadNeverDispatchesPaste() {
        let f = DirectPasteFixture(); var clock: TimeInterval = 0, slowFinal = false
        var environment = f.environment; environment.now = { clock }
        environment.focusedField = { _ in if slowFinal { clock += 2 }; return f.currentField }
        f.onWrite = { slowFinal = true }
        let service = DirectPasteCoordinator(environment: environment); f.prepare(service)
        XCTAssertEqual(paste(service, fixture: f), .focusChanged)
        XCTAssertEqual(f.writes.count, 1); XCTAssertTrue(f.events.isEmpty)
    }
    func testPermissionOrProcessLossDuringFinalEligibilityQueryCannotWriteClipboard() {
        for losesPermission in [false, true] {
            let f = DirectPasteFixture(); var queriesAfterPause = 0
            var environment = f.environment
            environment.focusedField = { _ in
                if f.pauseCount > 0 {
                    queriesAfterPause += 1
                    // The second eligible poll reaches its final pre-write
                    // validation after two stable-focus observations.
                    if queriesAfterPause == 2 { if losesPermission { f.trusted = false } else { f.running = false } }
                }
                return f.currentField
            }
            let service = DirectPasteCoordinator(environment: environment); f.prepare(service)
            XCTAssertEqual(paste(service, fixture: f), losesPermission ? .permissionRequired : .noTarget)
            XCTAssertTrue(f.writes.isEmpty); XCTAssertTrue(f.events.isEmpty)
        }
    }
    func testPermissionOrProcessLossDuringClipboardWriteCannotDispatchPaste() {
        for losesPermission in [false, true] {
            let f = DirectPasteFixture()
            f.onWrite = { if losesPermission { f.trusted = false } else { f.running = false } }
            let service = DirectPasteCoordinator(environment: f.environment); f.prepare(service)
            XCTAssertEqual(paste(service, fixture: f), losesPermission ? .permissionRequired : .noTarget)
            XCTAssertEqual(f.writes.count, 1); XCTAssertTrue(f.events.isEmpty)
        }
    }
    func testCancellationDuringFinalEligibilityQueryCannotWriteClipboard() {
        let f = DirectPasteFixture(); var queriesAfterPause = 0, service: DirectPasteCoordinator!
        var environment = f.environment
        environment.focusedField = { _ in
            if f.pauseCount > 0 { queriesAfterPause += 1; if queriesAfterPause == 2 { service.cancel() } }
            return f.currentField
        }
        service = DirectPasteCoordinator(environment: environment); f.prepare(service)
        var completed = false
        service.paste(items: ClipboardTransfer.textItems(["Must never paste"]), dismiss: f.dismiss) { _ in completed = true }
        wait { queriesAfterPause >= 2 }; RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        XCTAssertFalse(completed); XCTAssertTrue(f.writes.isEmpty); XCTAssertTrue(f.events.isEmpty)
    }
    func testForegroundOrOwnKeyboardFocusChangingDuringFinalEligibilityQueryCannotWriteClipboard() {
        for mutation in 0..<3 {
            let f = DirectPasteFixture(); var queriesAfterPause = 0
            var environment = f.environment
            environment.focusedField = { _ in
                if f.pauseCount > 0 {
                    queriesAfterPause += 1
                    if queriesAfterPause == 2 {
                        if mutation == 0 { f.frontmost = 202 }
                        else if mutation == 1 { f.frontmost = f.ownPID }
                        else { f.ownsKeyboardFocusOverride = true }
                    }
                }
                return f.currentField
            }
            let service = DirectPasteCoordinator(environment: environment); f.prepare(service)
            XCTAssertEqual(paste(service, fixture: f), .focusChanged)
            XCTAssertTrue(f.writes.isEmpty); XCTAssertTrue(f.events.isEmpty)
        }
    }
    func testForegroundOrOwnKeyboardFocusChangingDuringFinalPostWriteQueryCannotDispatchPaste() {
        for mutation in 0..<3 {
            let f = DirectPasteFixture()
            var environment = f.environment
            environment.focusedField = { _ in
                if !f.writes.isEmpty {
                    if mutation == 0 { f.frontmost = 202 }
                    else if mutation == 1 { f.frontmost = f.ownPID }
                    else { f.ownsKeyboardFocusOverride = true }
                }
                return f.currentField
            }
            let service = DirectPasteCoordinator(environment: environment); f.prepare(service)
            XCTAssertEqual(paste(service, fixture: f), .focusChanged)
            XCTAssertEqual(f.writes.count, 1); XCTAssertTrue(f.events.isEmpty)
        }
    }
    func testKnownFieldAndIneligibleCaptureDoNotWarmOrReplaceAnEarlierIdentity() {
        for secure in [false, true] {
            let f = DirectPasteFixture(); var requests = 0
            if secure { f.currentField = .init(identity: f.field, editable: true, secure: true) }
            var environment = f.environment; environment.prepareAccessibility = { _ in requests += 1; return true }
            let service = DirectPasteCoordinator(environment: environment); f.prepare(service)
            XCTAssertEqual(paste(service, fixture: f), secure ? .noTarget : .pasted); XCTAssertEqual(requests, 0)
        }
    }
}
