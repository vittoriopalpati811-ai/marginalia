import SwiftUI
import SwiftData

// Entry point dell'app.
// NOTA BLIND COMPILE: questo file funzionerà correttamente su Xcode.
// Il @main viene usato nel target App (non nel Package.swift library).
// Su Xcode, questo file sarà nel target "MarginaliaApp", non nella libreria.

@main
struct MarginaliaApp: App {

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Book.self, Highlight.self, Tag.self, Jam.self])
    }
}
