import Foundation
import SwiftData

@Model
final class Book {
    var id: UUID
    var remoteId: String?         // Supabase UUID, nil finché non sincronizzato
    var title: String
    var author: String
    var importedAt: Date
    var coverColor: String        // hex, generato da hash(title+author)

    @Relationship(deleteRule: .cascade, inverse: \Highlight.book)
    var highlights: [Highlight] = []

    init(title: String, author: String) {
        self.id = UUID()
        self.title = title
        self.author = author
        self.importedAt = Date()
        self.coverColor = Self.colorForTitle(title, author: author)
    }

    // Genera un colore deterministico caldo da titolo+autore
    static func colorForTitle(_ title: String, author: String) -> String {
        let palette: [String] = [
            "#8B7355", "#7A6248", "#9E8B6F", "#6B5A42",
            "#A0906E", "#C4A882", "#7D6B50", "#B5997A",
        ]
        let hash = abs((title + author).hashValue)
        return palette[hash % palette.count]
    }
}
