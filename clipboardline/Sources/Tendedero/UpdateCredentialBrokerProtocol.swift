import Foundation

/// Shared verbatim by the app and its frozen, mutually authenticated XPC
/// service. Credentials have no command-line or standard-output interface.
@objc(ClipboardLineUpdateCredentialBrokerProtocol)
protocol UpdateCredentialBrokerProtocol {
    func handshake(withReply reply: @escaping (NSError?) -> Void)
    func readToken(allowInteraction: Bool, withReply reply: @escaping (String?, NSError?) -> Void)
    func writeToken(_ token: String, withReply reply: @escaping (NSError?) -> Void)
    func deleteToken(withReply reply: @escaping (NSError?) -> Void)
}
