import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    Label("Accedi / Registrati", systemImage: "person.circle")
                        .foregroundStyle(Color(hex: "#8B7355"))
                }

                Section("Sync") {
                    HStack {
                        Label("Ultimo sync", systemImage: "arrow.clockwise")
                        Spacer()
                        Text("—")
                            .font(.caption)
                            .foregroundStyle(Color(hex: "#6B6862"))
                    }
                }

                Section("App") {
                    HStack {
                        Label("Versione", systemImage: "info.circle")
                        Spacer()
                        Text("0.1.0")
                            .font(.caption)
                            .foregroundStyle(Color(hex: "#6B6862"))
                    }
                }
            }
            .navigationTitle("Impostazioni")
        }
    }
}
