import Foundation
import SwiftData

@Model
final class Highlight {
    var id: UUID
    var remoteId: String?         // Supabase UUID
    var content: String
    var location: String?         // "Location 1234-1236"
    var addedAt: Date?            // quando l'utente ha sottolineato su Kindle
    var personalNote: String?
    var contentHash: String       // sha256(book.remoteId + content) per dedup
    var lastShownInWidget: Date?
    var createdAt: Date

    var book: Book

    @Relationship(deleteRule: .cascade, inverse: \Tag.highlights)
    var tags: [Tag] = []

    init(content: String, book: Book, location: String? = nil, addedAt: Date? = nil) {
        self.id = UUID()
        self.content = content
        self.book = book
        self.location = location
        self.addedAt = addedAt
        self.createdAt = Date()
        self.contentHash = Self.hash(content: content, bookTitle: book.title, author: book.author)
    }

    static func hash(content: String, bookTitle: String, author: String) -> String {
        // SHA-256 non è disponibile in Foundation senza CryptoKit.
        // Usiamo un hash semplice per ora; verrà allineato con la versione Supabase
        // quando il progetto apre su Mac con CryptoKit disponibile.
        let input = "\(bookTitle)\(author)\(content)"
        var hash: UInt64 = 14695981039346656037
        for byte in input.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(format: "%016llx", hash)
    }
}
