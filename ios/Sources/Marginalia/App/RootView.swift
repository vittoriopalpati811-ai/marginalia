import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            LibraryView()
                .tabItem {
                    Label("Libreria", systemImage: "books.vertical")
                }

            SearchView()
                .tabItem {
                    Label("Cerca", systemImage: "magnifyingglass")
                }

            SocialView()
                .tabItem {
                    Label("Jam", systemImage: "music.note.list")
                }

            SettingsView()
                .tabItem {
                    Label("Impostazioni", systemImage: "gearshape")
                }
        }
        .tint(Color(hex: "#8B7355"))
    }
}
