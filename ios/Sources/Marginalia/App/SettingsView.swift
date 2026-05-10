import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var showKindleLogin = false
    @State private var syncStatus: SyncStatus = .idle
    @State private var lastSyncDate: Date? = nil
    @State private var importSummary: ImportSummary?

    enum SyncStatus {
        case idle, syncing, done, error(String)
    }

    var body: some View {
        NavigationStack {
            List {
                // ─── Kindle Sync ─────────────────────────────────────
                Section {
                    kindleSyncRow
                } header: {
                    Text("Kindle")
                } footer: {
                    Text("Accedi ad Amazon con il tuo Kindle account. Gli highlight vengono letti direttamente dalla tua libreria Amazon.")
                        .font(.caption)
                }

                // ─── Sync status ──────────────────────────────────────
                if let summary = importSummary {
                    Section("Ultimo import") {
                        Label("\(summary.highlightsAdded) nuovi highlight", systemImage: "text.quote")
                        Label("\(summary.booksAdded) nuovi libri", systemImage: "books.vertical")
                        if summary.duplicatesSkipped > 0 {
                            Label("\(summary.duplicatesSkipped) duplicati saltati", systemImage: "minus.circle")
                                .foregroundStyle(Color(hex: "#6B6862"))
                        }
                    }
                }

                // ─── App info ─────────────────────────────────────────
                Section("App") {
                    HStack {
                        Label("Versione", systemImage: "info.circle")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
                            .font(.caption)
                            .foregroundStyle(Color(hex: "#6B6862"))
                    }
                }
            }
            .navigationTitle("Impostazioni")
        }
        .sheet(isPresented: $showKindleLogin) {
            AmazonLoginView(
                onComplete: { highlights in
                    handleHighlights(highlights)
                },
                onDismiss: {
                    showKindleLogin = false
                }
            )
        }
    }

    // MARK: - Kindle Sync Row

    private var kindleSyncRow: some View {
        HStack {
            Label("Sincronizza Kindle", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(Color(hex: "#1A1A18"))

            Spacer()

            switch syncStatus {
            case .idle:
                Button("Connetti") {
                    showKindleLogin = true
                }
                .font(.callout)
                .foregroundStyle(Color(hex: "#8B7355"))

            case .syncing:
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Sync...")
                        .font(.caption)
                        .foregroundStyle(Color(hex: "#6B6862"))
                }

            case .done:
                Button {
                    showKindleLogin = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color(hex: "#8B7355"))
                        Text("Aggiorna")
                            .font(.caption)
                            .foregroundStyle(Color(hex: "#6B6862"))
                    }
                }

            case .error(let msg):
                Button {
                    showKindleLogin = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                        Text("Riprova")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .help(msg)
            }
        }
    }

    // MARK: - Import

    private func handleHighlights(_ highlights: [AmazonHighlight]) {
        showKindleLogin = false
        syncStatus = .syncing

        Task {
            do {
                let clippings = highlights.map { $0.asParsedClipping() }
                // Usiamo ImportService ricostruendo il contenuto come stringa di clippings
                // (alternativa: estendere ImportService per accettare [ParsedClipping] direttamente)
                let service = ImportService(context: context)
                // Componi stringa My Clippings.txt sintetica da AmazonHighlight
                let syntheticContent = highlights.map { h in
                    """
                    \(h.bookTitle) (\(h.bookAuthor))
                    - Your Highlight | \(h.location ?? "") | Added on

                    \(h.content)
                    ==========
                    """
                }.joined(separator: "\n")

                let summary = try await service.importContent(syntheticContent)

                await MainActor.run {
                    importSummary = summary
                    syncStatus = .done
                    lastSyncDate = Date()
                }
            } catch {
                await MainActor.run {
                    syncStatus = .error(error.localizedDescription)
                }
            }
        }
    }
}
