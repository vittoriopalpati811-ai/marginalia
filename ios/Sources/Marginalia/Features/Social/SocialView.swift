import SwiftUI
import SwiftData

// Vista Jam — stub funzionale.
// L'implementazione completa delle Jam (join, condivisione highlights) avviene via web.
// Su iOS: visualizzazione read-only degli highlight condivisi + navigazione al web per azioni avanzate.
struct SocialView: View {
    @Query(sort: \Jam.syncedAt, order: .reverse)
    private var jams: [Jam]

    var body: some View {
        NavigationStack {
            Group {
                if jams.isEmpty {
                    emptyState
                } else {
                    jamList
                }
            }
            .navigationTitle("Jam")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Link(destination: URL(string: "https://app.marginalia.io/jam")!) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }

    private var jamList: some View {
        List(jams) { jam in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(jam.title)
                        .font(.system(.body, design: .serif))
                        .foregroundStyle(Color(hex: "#1A1A18"))
                    Spacer()
                    if jam.isOwner {
                        Text("Owner")
                            .font(.caption2)
                            .foregroundStyle(Color(hex: "#8B7355"))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: "#8B7355").opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                if let desc = jam.jamDescription {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(Color(hex: "#6B6862"))
                        .lineLimit(1)
                }
                Text("#\(jam.inviteCode)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Color(hex: "#C4A882"))
            }
            .padding(.vertical, 4)
            .listRowBackground(Color(hex: "#F2F0EC"))
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note.list")
                .font(.system(size: 44))
                .foregroundStyle(Color(hex: "#C4A882"))
            Text("Nessuna Jam")
                .font(.system(.title3, design: .serif))
                .foregroundStyle(Color(hex: "#1A1A18"))
            Text("Crea o unisciti a una cerchia di lettura")
                .font(.caption)
                .foregroundStyle(Color(hex: "#6B6862"))
                .multilineTextAlignment(.center)
            Link("Apri Marginalia Web", destination: URL(string: "https://app.marginalia.io/jam")!)
                .font(.callout)
                .foregroundStyle(Color(hex: "#8B7355"))
        }
        .padding()
    }
}
