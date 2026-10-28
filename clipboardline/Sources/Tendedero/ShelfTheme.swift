import SwiftUI

enum ShelfTheme: String, CaseIterable { case soft, neutral
    var title: String { self == .soft ? L("Soft colors") : L("Neutral glass") }
    func accent(_ shelf: Shelf) -> Color {
        guard self == .soft else { return .accentColor }
        return switch shelf { case .images: Color(red: 0.32, green: 0.57, blue: 0.84)
        case .texts: Color(red: 0.70, green: 0.49, blue: 0.25)
        case .links: Color(red: 0.31, green: 0.58, blue: 0.46) }
    }
    func wash(_ shelf: Shelf) -> Color { self == .soft ? accent(shelf).opacity(0.12) : .clear }
}
