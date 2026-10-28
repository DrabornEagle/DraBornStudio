import Foundation

enum Shelf: String, Codable, CaseIterable {
    case images, texts, links
    var title: String { switch self { case .images: L("Images"); case .texts: L("Texts"); case .links: L("Links") } }
    var icon: String { switch self { case .images: "photo"; case .texts: "text.alignleft"; case .links: "link" } }
    var libraryKind: LibraryKind { switch self { case .images: .image; case .texts: .text; case .links: .link } }
    var presentation: ShelfPresentation { switch self { case .images: .images; case .texts: .texts; case .links: .links } }
}
enum ShelfPresentation: String, Codable, CaseIterable {
    case images, texts, both, links, imagesLinks, textsLinks, all
    var shelves: [Shelf] {
        switch self { case .images: [.images]; case .texts: [.texts]; case .both: [.images, .texts]; case .links: [.links]
        case .imagesLinks: [.images, .links]; case .textsLinks: [.texts, .links]; case .all: [.images, .texts, .links] }
    }
    var title: String { shelves.map(\.title).joined(separator: " + ") }
    static func containing(_ shelves: Set<Shelf>) -> Self? { allCases.first { Set($0.shelves) == shelves } }
}
