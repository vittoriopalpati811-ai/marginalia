import Foundation
import SwiftData

public struct ImportSummary {
    public let booksAdded: Int
    public let highlightsAdded: Int
    public let duplicatesSkipped: Int
}

// Importa un file My Clippings.txt nel ModelContext locale (SwiftData).
// Dopo l'import locale, SupabaseSync si occuperà di sincronizzare con il server.
public struct ImportService {

    private let context: ModelContext
    private let parser: MyClippingsParser

    public init(context: ModelContext) {
        self.context = context
        self.parser = MyClippingsParser()
    }

    public func importClippings(from url: URL) async throws -> ImportSummary {
        let rawContent = try String(contentsOf: url, encoding: .utf8)
        return try await importContent(rawContent)
    }

    // Importa da stringa (utile per import da Supabase o per test)
    public func importContent(_ content: String) async throws -> ImportSummary {
        let clippings = parser.parse(content)

        var booksAdded = 0
        var highlightsAdded = 0
        var duplicatesSkipped = 0

        for clipping in clippings {
            guard clipping.type == .highlight || clipping.type == .note else { continue }

            let book = try findOrCreateBook(title: clipping.title, author: clipping.author, wasCreated: &booksAdded)

            let contentHash = Highlight.hash(
                content: clipping.content,
                bookTitle: clipping.title,
                author: clipping.author
            )

            if try highlightExists(hash: contentHash) {
                duplicatesSkipped += 1
                continue
            }

            let highlight = Highlight(
                content: clipping.content,
                book: book,
                location: clipping.location,
                addedAt: clipping.addedAt
            )
            context.insert(highlight)
            highlightsAdded += 1
        }

        try context.save()

        return ImportSummary(
            booksAdded: booksAdded,
            highlightsAdded: highlightsAdded,
            duplicatesSkipped: duplicatesSkipped
        )
    }

    // MARK: - Private

    private func findOrCreateBook(title: String, author: String, wasCreated: inout Int) throws -> Book {
        let fetchDescriptor = FetchDescriptor<Book>(
            predicate: #Predicate { $0.title == title && $0.author == author }
        )
        let existing = try context.fetch(fetchDescriptor)

        if let book = existing.first {
            return book
        }

        let book = Book(title: title, author: author)
        context.insert(book)
        wasCreated += 1
        return book
    }

    private func highlightExists(hash: String) throws -> Bool {
        let fetchDescriptor = FetchDescriptor<Highlight>(
            predicate: #Predicate { $0.contentHash == hash }
        )
        fetchDescriptor.fetchLimit = 1
        return try !context.fetch(fetchDescriptor).isEmpty
    }
}
