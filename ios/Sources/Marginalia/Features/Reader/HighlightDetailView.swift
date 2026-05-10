import SwiftUI

struct HighlightDetailView: View {
    @Bindable var highlight: Highlight
    @State private var editingNote = false
    @State private var noteText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Testo highlight
                Text(highlight.content)
                    .font(.system(.body, design: .serif))
                    .lineSpacing(8)
                    .foregroundStyle(Color(hex: "#1A1A18"))

                Divider()
                    .background(Color(hex: "#E8E4DF"))

                // Metadata
                VStack(alignment: .leading, spacing: 6) {
                    Text(highlight.book.title)
                        .font(.caption)
                        .foregroundStyle(Color(hex: "#8B7355"))
                    Text(highlight.book.author)
                        .font(.caption)
                        .foregroundStyle(Color(hex: "#6B6862"))

                    HStack(spacing: 12) {
                        if let location = highlight.location {
                            Label(location, systemImage: "mappin")
                                .font(.caption2)
                                .foregroundStyle(Color(hex: "#6B6862"))
                        }
                        if let date = highlight.addedAt {
                            Label(date.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                                .font(.caption2)
                                .foregroundStyle(Color(hex: "#6B6862"))
                        }
                    }
                }

                Divider()
                    .background(Color(hex: "#E8E4DF"))

                // Nota personale
                VStack(alignment: .leading, spacing: 8) {
                    Text("La mia nota")
                        .font(.caption)
                        .foregroundStyle(Color(hex: "#6B6862"))

                    if editingNote {
                        TextEditor(text: $noteText)
                            .font(.system(.body, design: .serif))
                            .frame(minHeight: 80)
                            .padding(8)
                            .background(Color(hex: "#F2F0EC"))
                            .cornerRadius(4)
                            .onDisappear {
                                highlight.personalNote = noteText.isEmpty ? nil : noteText
                            }
                    } else {
                        Button {
                            noteText = highlight.personalNote ?? ""
                            editingNote = true
                        } label: {
                            Text(highlight.personalNote ?? "Aggiungi nota...")
                                .font(.system(.body, design: .serif))
                                .foregroundStyle(
                                    highlight.personalNote == nil
                                    ? Color(hex: "#C4A882")
                                    : Color(hex: "#1A1A18")
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                // Azioni
                HStack(spacing: 16) {
                    ShareLink(item: highlight.content) {
                        Label("Condividi", systemImage: "square.and.arrow.up")
                            .font(.caption)
                    }
                    Button {
                        UIPasteboard.general.string = highlight.content
                    } label: {
                        Label("Copia", systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                }
                .foregroundStyle(Color(hex: "#8B7355"))
            }
            .padding(24)
        }
        .background(Color(hex: "#FAFAF8"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if editingNote {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fine") {
                        highlight.personalNote = noteText.isEmpty ? nil : noteText
                        editingNote = false
                    }
                }
            }
        }
    }
}
