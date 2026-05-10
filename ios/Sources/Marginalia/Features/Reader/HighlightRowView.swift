import SwiftUI

struct HighlightRowView: View {
    let highlight: Highlight

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(highlight.content)
                .font(.system(.callout, design: .serif))
                .lineSpacing(4)
                .lineLimit(4)
                .foregroundStyle(Color(hex: "#1A1A18"))

            HStack(spacing: 8) {
                if let location = highlight.location {
                    Text(location)
                        .font(.caption2)
                        .foregroundStyle(Color(hex: "#6B6862"))
                }
                if let date = highlight.addedAt {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(Color(hex: "#C4A882"))
                }
            }
        }
        .padding(.vertical, 6)
    }
}
