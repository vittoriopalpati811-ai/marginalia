import SwiftUI
import WebKit

// Vista che mostra il login Amazon in un WKWebView.
// L'utente si autentica direttamente su Amazon — Marginalia non tocca le credenziali.
// Dopo il login, naviga automaticamente a read.amazon.com/kp/notebook e inietta il JS.
//
// Integrazione in SettingsView:
//   .sheet(isPresented: $showKindleLogin) {
//       AmazonLoginView(onComplete: { highlights in ... })
//   }

public struct AmazonLoginView: View {
    public let onComplete: ([AmazonHighlight]) -> Void
    public let onDismiss: () -> Void

    @State private var phase: Phase = .login
    @State private var error: String?
    @State private var highlightCount: Int = 0

    public enum Phase {
        case login          // utente deve fare login
        case extracting     // JS extraction in corso
        case done           // completato
    }

    public init(onComplete: @escaping ([AmazonHighlight]) -> Void, onDismiss: @escaping () -> Void) {
        self.onComplete = onComplete
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                AmazonWebViewRepresentable(
                    phase: $phase,
                    error: $error,
                    highlightCount: $highlightCount,
                    onComplete: onComplete
                )
                .ignoresSafeArea()

                // Overlay durante extraction
                if phase == .extracting {
                    extractingOverlay
                }

                // Overlay done
                if phase == .done {
                    doneOverlay
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla", action: onDismiss)
                }
            }
        }
        .alert("Errore", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("OK", role: .cancel) { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private var navigationTitle: String {
        switch phase {
        case .login:      return "Accedi ad Amazon"
        case .extracting: return "Importazione..."
        case .done:       return "Completato"
        }
    }

    private var extractingOverlay: some View {
        ZStack {
            Color(hex: "#FAFAF8").opacity(0.95)
            VStack(spacing: 16) {
                ProgressView()
                    .tint(Color(hex: "#8B7355"))
                Text("Leggo i tuoi highlight da Amazon...")
                    .font(.system(.callout, design: .serif))
                    .foregroundStyle(Color(hex: "#1A1A18"))
                Text("Potrebbe richiedere qualche secondo")
                    .font(.caption)
                    .foregroundStyle(Color(hex: "#6B6862"))
            }
        }
    }

    private var doneOverlay: some View {
        ZStack {
            Color(hex: "#FAFAF8").opacity(0.95)
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color(hex: "#8B7355"))
                Text("Trovati \(highlightCount) highlight")
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(Color(hex: "#1A1A18"))
                Button("Chiudi") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#8B7355"))
            }
        }
    }
}

// UIViewRepresentable che gestisce il WKWebView
private struct AmazonWebViewRepresentable: UIViewRepresentable {
    @Binding var phase: AmazonLoginView.Phase
    @Binding var error: String?
    @Binding var highlightCount: Int
    let onComplete: ([AmazonHighlight]) -> Void

    // URL di partenza: notebook Kindle. Amazon redirige al login se non autenticato.
    private static let notebookURL = URL(string: "https://read.amazon.com/kp/notebook")!

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "marginaliaHighlights")
        config.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: Self.notebookURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Nessun aggiornamento necessario dopo la creazione
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let parent: AmazonWebViewRepresentable
        let syncCoordinator = AmazonSyncCoordinator()
        var hasExtracted = false

        init(parent: AmazonWebViewRepresentable) {
            self.parent = parent
            super.init()

            syncCoordinator.onHighlightsExtracted = { [weak self] highlights in
                guard let self, !self.hasExtracted else { return }
                self.hasExtracted = true

                DispatchQueue.main.async {
                    self.parent.highlightCount = highlights.count
                    self.parent.phase = .done
                    self.parent.onComplete(highlights)
                }
            }

            syncCoordinator.onError = { [weak self] err in
                DispatchQueue.main.async {
                    self?.parent.error = err.localizedDescription
                    self?.parent.phase = .login
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url = webView.url else { return }

            // Se siamo sulla pagina notebook → extract
            if url.host == "read.amazon.com" && url.path.contains("notebook") {
                DispatchQueue.main.async { self.parent.phase = .extracting }
                // Piccolo delay per assicurarsi che la pagina sia completamente renderizzata
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self.syncCoordinator.extractFromWebView(webView)
                }
            }
            // Se siamo su una pagina di login Amazon → lascia che l'utente si logga
            // (non facciamo nulla, il WebView gestisce il form nativo)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.error = "Errore di navigazione: \(error.localizedDescription)"
            }
        }

        // WKScriptMessageHandler (path alternativo se usiamo postMessage invece di evaluateJS)
        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            syncCoordinator.userContentController(userContentController, didReceive: message)
        }
    }
}
