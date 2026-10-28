import XCTest
@testable import BananaStudio

final class KeyVaultTests: XCTestCase {
    func testKeychainRoundTripUsesAnIsolatedDisposableService() throws {
        let service = "com.bananastudio.tests.\(UUID().uuidString)"
        defer { try? KeyVault.save(.openAI, value: nil, service: service) }
        XCTAssertNil(try KeyVault.read(.openAI, service: service))
        try KeyVault.save(.openAI, value: "synthetic-test-value", service: service)
        XCTAssertEqual(try KeyVault.read(.openAI, service: service), "synthetic-test-value")
        try KeyVault.save(.openAI, value: "replacement-test-value", service: service)
        XCTAssertEqual(try KeyVault.read(.openAI, service: service), "replacement-test-value")
        try KeyVault.save(.openAI, value: nil, service: service)
        XCTAssertNil(try KeyVault.read(.openAI, service: service))
    }
    func testInvalidValuesAreRejectedBeforeWriting() throws {
        let service = "com.bananastudio.tests.\(UUID().uuidString)"
        defer { try? KeyVault.save(.openAI, value: nil, service: service) }
        XCTAssertThrowsError(try KeyVault.save(.openAI, value: "line\nbreak", service: service))
        XCTAssertThrowsError(try KeyVault.save(.openAI, value: String(repeating: "a", count: 4096), service: service))
        XCTAssertNil(try KeyVault.read(.openAI, service: service))
    }
}
