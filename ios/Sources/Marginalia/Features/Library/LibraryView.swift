import SwiftUI
import SwiftData

struct LibraryView: View {

    @Query(sort: \Book.importedAt, order: .reverse)
    private var books: [Book]

    @State private var showImportPicker = false
    @State private var importError: String?
    @State private var importSummary: ImportSummary?
    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack {
            Group {
                if books.isEmpty {
                    emptyState
                } else {
                    bookList
                }
            }
            .navigationTitle("Libreria")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showImportPicker = true
                    } label: {
                        Image(systemName: "arrow.down.doc")
                    }
                }
            }
            .fileImporter(
                isPresented: $showImportPicker,
                allowedContentTypes: [.plainText],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result: result)
            }
            .alert("Import completato", isPresented: Binding(
                get: { importSummary != nil },
                set: { if !$0 { importSummary = nil } }
            )) {
                Button("OK", role: .cancel) { importSummary = nil }
            } message: {
                if let s = importSummary {
                    Text("\(s.highlightsAdded) nuovi highlight da \(s.booksAdded) libri. \(s.duplicatesSkipped) duplicati saltati.")
                }
            }
            .alert("Errore import", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
    }

    private var bookList: some View {
        List(books) { book in
            NavigationLink(destination: BookDetailView(book: book)) {
                BookRowView(book: book)
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "books.vertical")
                .font(.system(size: 48))
                .foregroundStyle(Color(hex: "#C4A882"))
            Text("La libreria è vuota")
                .font(.system(.title3, design: .serif))
                .foregroundStyle(Color(hex: "#1A1A18"))
            Text("Importa il file My Clippings.txt dal tuo Kindle")
                .font(.caption)
                .foregroundStyle(Color(hex: "#6B6862"))
                .multilineTextAlignment(.center)
            Button("Importa ora") {
                showImportPicker = true
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(hex: "#8B7355"))
        }
        .padding()
    }

    private func handleImport(result: Result<[URL], Error>) {
        Task {
            do {
                let urls = try result.get()
                guard let url = urls.first else { return }
                guard url.startAccessingSecurityScopedResource() else {
                    importError = "Accesso al file negato."
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }

                let service = ImportService(context: context)
                let summary = try await service.importClippings(from: url)
                await MainActor.run { importSummary = summary }
            } catch {
                await MainActor.run { importError = error.localizedDescription }
            }
        }
    }
}
