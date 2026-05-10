import SwiftUI

struct BookRowView: View {
    let book: Book

    var body: some View {
        HStack(spacing: 12) {
            // Cover colorata
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: book.coverColor))
                .frame(width: 36, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(Color(hex: "#1A1A18"))
                    .lineLimit(2)

                Text(book.author)
                    .font(.caption)
                    .foregroundStyle(Color(hex: "#6B6862"))

                Text("\(book.highlights.count) highlight")
                    .font(.caption2)
                    .foregroundStyle(Color(hex: "#C4A882"))
            }
        }
        .padding(.vertical, 4)
    }
}
