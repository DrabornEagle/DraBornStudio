import Foundation
import UserNotifications

/// Notifications carry only a build number. An action must still pass through
/// the controller's verified candidate and the existing signed installer.
@MainActor
final class UpdateNotifications: NSObject, UNUserNotificationCenterDelegate {
    nonisolated static let category = "local.clipboardline.update"
    nonisolated static let installAction = "local.clipboardline.update.install"
    nonisolated static let identifierPrefix = "clipboardline.update."
    enum Response: Equatable { case show(Int), install(Int) }

    private var center: UNUserNotificationCenter?
    private var delivery: Task<Void, Never>?
    private var enabled = false
    var onResponse: ((Response) -> Void)?

    func start() {
        // SwiftPM and the isolated UI harness must never request system consent.
        guard Bundle.main.bundleIdentifier == "local.clipboardline.review" else { return }
        let center = UNUserNotificationCenter.current()
        self.center = center
        center.delegate = self
        let install = UNNotificationAction(identifier: Self.installAction,
            title: L("Install and reopen"), options: [.foreground])
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.category,
            actions: [install], intentIdentifiers: [], options: [])])
        if let build = Int(AppIdentity.build) {
            Task {
                let delivered = await center.deliveredNotifications()
                let stale = delivered.compactMap { notification -> String? in
                    let request = notification.request
                    guard request.content.categoryIdentifier == Self.category,
                          let old = request.content.userInfo["build"] as? Int, old <= build else { return nil }
                    return request.identifier
                }
                center.removeDeliveredNotifications(withIdentifiers: stale)
            }
        }
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        if !value { delivery?.cancel(); delivery = nil }
    }

    func announce(_ update: AppUpdateController.AvailableUpdate, completion: @escaping (Bool) -> Void) {
        announce(version: update.manifest.version, build: update.manifest.build, completion: completion)
    }

    func announce(version: String, build: Int, completion: @escaping (Bool) -> Void) {
        guard enabled, let center else { completion(false); return }
        delivery?.cancel()
        let request = Self.request(version: version, build: build)
        delivery = Task { [weak self] in
            var acknowledged = false
            defer { completion(acknowledged) }
            let settings = await center.notificationSettings()
            guard let self, self.enabled, !Task.isCancelled else { return }
            var allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            if settings.authorizationStatus == .notDetermined {
                allowed = (try? await center.requestAuthorization(options: [.alert])) ?? false
            }
            guard self.enabled, !Task.isCancelled else { return }
            guard allowed else { acknowledged = true; return }
            // Denied or unavailable system notifications leave the persistent
            // menu/About action available, without repeatedly requesting consent.
            do { try await center.add(request) } catch { return }
            if !self.enabled || Task.isCancelled {
                center.removeDeliveredNotifications(withIdentifiers: [request.identifier])
                center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
                return
            }
            acknowledged = true
        }
    }

    static func request(version: String, build: Int) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = L("Update available")
        content.body = String(format: L("ClipboardLine %@ is ready to install."), version)
        content.categoryIdentifier = category
        content.userInfo = ["build": build]
        return UNNotificationRequest(identifier: identifierPrefix + String(build), content: content, trigger: nil)
    }

    nonisolated static func response(identifier: String, category: String, action: String,
                                     build: Any?) -> Response? {
        guard category == Self.category, let number = build as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
              number.doubleValue == Double(number.intValue), number.intValue > 0,
              identifier == identifierPrefix + String(number.intValue) else { return nil }
        switch action {
        case UNNotificationDefaultActionIdentifier: return .show(number.intValue)
        case installAction: return .install(number.intValue)
        default: return nil
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        await presentation(category: notification.request.content.categoryIdentifier)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse) async {
        let request = response.notification.request
        guard let action = Self.response(identifier: request.identifier,
            category: request.content.categoryIdentifier, action: response.actionIdentifier,
            build: request.content.userInfo["build"]) else { return }
        await deliver(action)
    }

    private func deliver(_ response: Response) { onResponse?(response) }
    private func presentation(category: String) -> UNNotificationPresentationOptions {
        enabled && category == Self.category ? [.banner, .list] : []
    }
}
