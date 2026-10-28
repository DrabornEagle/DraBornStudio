import Foundation
import Security
import Darwin

/// Headless signed-host fixture. It invokes only the broker's secret-free
/// handshake: no token getter/setter/deleter, Keychain query or UI is used.
@main enum CredentialBrokerIntegrationMain {
    static func main() {
        guard CommandLine.arguments.count == 2 else { exit(64) }
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        let info = Bundle.main.infoDictionary ?? [:]
        guard let service = info["FixtureBrokerService"] as? String,
              let requirement = info["FixtureBrokerRequirement"] as? String else { exit(65) }
        #if CREDENTIAL_BROKER_FIXTURE_B
        let build = "B"
        #else
        let build = "A"
        #endif
        let connection = NSXPCConnection(serviceName: service)
        connection.remoteObjectInterface = NSXPCInterface(with: UpdateCredentialBrokerProtocol.self)
        connection.setCodeSigningRequirement(requirement)
        let lock = NSLock()
        var done = false
        func finish(_ status: String, error: Error? = nil) {
            lock.lock(); defer { lock.unlock() }
            guard !done else { return }; done = true
            var result: [String: Any] = ["status": status, "fixtureBuild": build,
                "hostIdentifier": Bundle.main.bundleIdentifier ?? "", "processID": getpid(),
                "credentialMethodsInvoked": false, "keychainQueriesByHost": 0]
            if let error = error as NSError? {
                // Only nonsecret error metadata is retained. XPC error text can
                // contain paths; it cannot contain credentials in this fixture.
                result["errorDomain"] = error.domain; result["errorCode"] = error.code
            }
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .prettyPrinted]) {
                try? data.write(to: output, options: .atomic)
            }
        }
        connection.invalidationHandler = { finish("invalidated") }
        connection.interruptionHandler = { finish("interrupted") }
        connection.resume()
        if let proxy = connection.remoteObjectProxyWithErrorHandler({ finish("error", error: $0) }) as? UpdateCredentialBrokerProtocol {
            proxy.handshake { error in
                if let error { finish("handshake-error", error: error) }
                else { finish("connected") }
            }
        } else { finish("missing-proxy") }
        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline {
            lock.lock(); let complete = done; lock.unlock()
            if complete { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        finish("timeout"); connection.invalidate()
    }
}
