import SwiftUI
import SwiftData

struct SearchView: View {
    @State private var query = ""
    @State private var debouncedQuery = ""
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SearchBar(text: $query, onTextChange: handleQueryChange)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                ResultList(query: debouncedQuery)
            }
            .navigationTitle("Cerca")
            .background(Color(hex: "#FAFAF8"))
        }
    }

    private func handleQueryChange(_ newValue: String) {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await MainActor.run { debouncedQuery = newValue }
        }
    }
}

private struct ResultList: View {
    let query: String

    @Query private var highlights: [Highlight]

    init(query: String) {
        if query.isEmpty {
            _highlights = Query(sort: \Highlight.addedAt, order: .reverse)
        } else {
            _highlights = Query(
                filter: #Predicate<Highlight> {
                    $0.content.localizedStandardContains(query)
                },
                sort: \Highlight.addedAt,
                order: .reverse
            )
        }
    }

    var body: some View {
        if highlights.isEmpty && !query.isEmpty {
            VStack(spacing: 8) {
                Text("Nessun risultato per "\(query)"")
                    .font(.system(.callout, design: .serif))
                    .foregroundStyle(Color(hex: "#6B6862"))
            }
            .frame(maxHeight: .infinity)
        } else {
            List(highlights) { highlight in
                NavigationLink(destination: HighlightDetailView(highlight: highlight)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(highlight.content)
                            .font(.system(.callout, design: .serif))
                            .lineLimit(3)
                            .foregroundStyle(Color(hex: "#1A1A18"))
                        Text(highlight.book.title)
                            .font(.caption)
                            .foregroundStyle(Color(hex: "#8B7355"))
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color(hex: "#F2F0EC"))
            }
            .listStyle(.plain)
        }
    }
}

private struct SearchBar: View {
    @Binding var text: String
    let onTextChange: (String) -> Void

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color(hex: "#C4A882"))
            TextField("Cerca nei tuoi highlight...", text: $text)
                .font(.system(.callout, design: .serif))
                .onChange(of: text, perform: onTextChange)
            if !text.isEmpty {
                Button {
                    text = ""
                    onTextChange("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color(hex: "#C4A882"))
                }
            }
        }
        .padding(10)
        .background(Color(hex: "#F2F0EC"))
        .cornerRadius(8)
    }
}
