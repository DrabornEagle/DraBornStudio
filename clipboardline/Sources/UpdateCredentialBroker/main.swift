import Foundation
import LocalAuthentication
import Security
import Darwin

/// Every incoming message is authenticated by NSXPC against a requirement
/// compiled into this frozen executable. PID or a caller-provided path is never
/// an identity. UID is an additional boundary, not a substitute for signing.
enum CredentialBrokerConnectionPolicy {
    static func accepts(user: uid_t, expectedUser: uid_t = getuid()) -> Bool { user == expectedUser }
    static var callerRequirement: String { CredentialBrokerBuildIdentity.callerRequirement }
}

enum CredentialBrokerQuery {
    static let service = "local.clipboardline.review.github-updates"
    static let account = "github-token"
    static func make(allowInteraction: Bool = false) -> [String: Any] {
        let context = LAContext(); context.interactionNotAllowed = !allowInteraction
        return [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: false,
            kSecUseAuthenticationContext as String: context,
            kSecUseAuthenticationUI as String: allowInteraction ? kSecUseAuthenticationUIAllow : kSecUseAuthenticationUIFail]
    }
    static func valid(_ token: String) -> Bool {
        (10...512).contains(token.utf8.count) && token.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }
    }
}

final class CredentialBroker: NSObject, UpdateCredentialBrokerProtocol {
    // SecurityAgent's legacy interaction switch is process-global. Serialize
    // operations so an explicit authorization cannot enable UI for background
    // reads/writes. No operation changes an item's ACL or partition list.
    private let queue = DispatchQueue(label: "local.clipboardline.review.credentials.keychain")
    private func error(_ status: OSStatus) -> NSError {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status),
            userInfo: [NSLocalizedDescriptionKey: "GitHub credential access is unavailable. Authorize access from ClipboardLine settings."])
    }
    private func perform(allowInteraction: Bool = false, onFailure: @escaping (NSError) -> Void, _ operation: @escaping () -> Void) {
        queue.async { [self] in
            let status = SecKeychainSetUserInteractionAllowed(allowInteraction)
            guard status == errSecSuccess else { onFailure(error(status)); return }
            defer { if SecKeychainSetUserInteractionAllowed(false) != errSecSuccess { _exit(1) } }
            operation()
        }
    }
    func handshake(withReply reply: @escaping (NSError?) -> Void) { reply(nil) }
    func readToken(allowInteraction: Bool, withReply reply: @escaping (String?, NSError?) -> Void) {
        perform(allowInteraction: allowInteraction, onFailure: { reply(nil, $0) }) { [self] in
            var query = CredentialBrokerQuery.make(allowInteraction: allowInteraction)
            query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
            var value: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &value)
            if status == errSecItemNotFound { reply(nil, nil); return }
            guard status == errSecSuccess, let data = value as? Data, let token = String(data: data, encoding: .utf8),
                  CredentialBrokerQuery.valid(token) else { reply(nil, error(status == errSecSuccess ? errSecDecode : status)); return }
            reply(token, nil)
        }
    }
    func writeToken(_ token: String, withReply reply: @escaping (NSError?) -> Void) {
        guard CredentialBrokerQuery.valid(token) else { reply(error(errSecParam)); return }
        perform(onFailure: reply) { [self] in
            let query = CredentialBrokerQuery.make(), data = Data(token.utf8)
            var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecItemNotFound {
                var item = query; item[kSecValueData as String] = data
                item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                status = SecItemAdd(item as CFDictionary, nil)
            }
            reply(status == errSecSuccess ? nil : error(status))
        }
    }
    func deleteToken(withReply reply: @escaping (NSError?) -> Void) {
        perform(onFailure: reply) { [self] in
            let status = SecItemDelete(CredentialBrokerQuery.make() as CFDictionary)
            reply(status == errSecSuccess || status == errSecItemNotFound ? nil : error(status))
        }
    }
}

final class CredentialBrokerListener: NSObject, NSXPCListenerDelegate {
    private let broker = CredentialBroker()
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard CredentialBrokerConnectionPolicy.accepts(user: connection.effectiveUserIdentifier) else { return false }
        connection.setCodeSigningRequirement(CredentialBrokerConnectionPolicy.callerRequirement)
        connection.exportedInterface = NSXPCInterface(with: UpdateCredentialBrokerProtocol.self)
        connection.exportedObject = broker
        connection.resume()
        return true
    }
}

#if !CREDENTIAL_BROKER_TESTS
@main enum CredentialBrokerMain {
    static func main() {
        guard SecKeychainSetUserInteractionAllowed(false) == errSecSuccess else { exit(1) }
        let delegate = CredentialBrokerListener()
        let listener = NSXPCListener.service()
        listener.delegate = delegate
        listener.resume()
    }
}
#endif
