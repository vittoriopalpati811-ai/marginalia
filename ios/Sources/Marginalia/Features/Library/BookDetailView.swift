import SwiftUI
import SwiftData

struct BookDetailView: View {
    let book: Book

    @Query private var highlights: [Highlight]

    init(book: Book) {
        self.book = book
        let bookId = book.id
        _highlights = Query(
            filter: #Predicate<Highlight> { $0.book.id == bookId },
            sort: \Highlight.addedAt,
            order: .forward
        )
    }

    var body: some View {
        List {
            // Header libro
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(hex: book.coverColor))
                            .frame(width: 48, height: 68)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(book.title)
                                .font(.system(.title3, design: .serif))
                                .foregroundStyle(Color(hex: "#1A1A18"))
                            Text(book.author)
                                .font(.subheadline)
                                .foregroundStyle(Color(hex: "#6B6862"))
                            Text("\(highlights.count) highlight")
                                .font(.caption)
                                .foregroundStyle(Color(hex: "#C4A882"))
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            // Highlights
            Section {
                ForEach(highlights) { highlight in
                    NavigationLink(destination: HighlightDetailView(highlight: highlight)) {
                        HighlightRowView(highlight: highlight)
                    }
                    .listRowBackground(Color(hex: "#F2F0EC"))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
    }
}
