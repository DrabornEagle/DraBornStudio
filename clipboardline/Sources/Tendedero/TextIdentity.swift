import Foundation

/// Clipboard selection can add a final paragraph break or use a different
/// Unicode composition. Compare those representations without editing the
/// captured body. Spaces, indentation, case and internal blank lines matter.
enum TextIdentity {
    static let version: Int64 = 2

    static func key(_ text: String) -> String {
        let normalized = text.precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let trimmed = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
        // Whitespace-only captures must not all become the empty identity.
        return trimmed.isEmpty ? normalized : trimmed
    }
}
