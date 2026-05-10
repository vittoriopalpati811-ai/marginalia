import Foundation
import WebKit

// Sincronizza gli highlight Kindle direttamente da read.amazon.com/kp/notebook.
//
// Come funziona:
//   1. L'utente fa login ad Amazon tramite WKWebView (sulla pagina Amazon — Marginalia
//      non vede mai le credenziali).
//   2. Dopo il login, il WebView ha una sessione Amazon valida.
//   3. Iniettiamo JavaScript nella pagina read.amazon.com/kp/notebook per estrarre
//      gli highlight direttamente dal DOM.
//   4. I dati tornano via WKScriptMessageHandler e vengono importati.
//
// Note ToS: l'utente accede a dati che gli appartengono, usando le sue credenziali,
// sulla pagina Amazon autentica. Marginalia non vede le credenziali e non accede
// ad API non autorizzate. È lo stesso approccio di Readwise e Obsidian.
//
// Fragilità nota: Amazon può cambiare il markup di read.amazon.com senza preavviso.
// Se il sync smette di funzionare, controllare prima il selettore JS in
// AmazonHighlightExtractor.js e aggiornare i selettori.

public struct AmazonHighlight {
    public let bookTitle: String
    public let bookAuthor: String
    public let content: String
    public let location: String?
    public let color: String?       // "yellow", "blue", "pink", "orange"
}

public enum AmazonSyncError: Error, LocalizedError {
    case notLoggedIn
    case extractionFailed(String)
    case noHighlightsFound
    case networkError(Error)

    public var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "Non sei loggato ad Amazon. Collega il tuo account Kindle."
        case .extractionFailed(let detail):
            return "Estrazione highlight fallita: \(detail)"
        case .noHighlightsFound:
            return "Nessun highlight trovato. Hai highlight su Kindle?"
        case .networkError(let err):
            return "Errore di rete: \(err.localizedDescription)"
        }
    }
}

// Il JS da iniettare in read.amazon.com/kp/notebook per estrarre gli highlight.
// Separato in una costante per facilitare aggiornamenti quando Amazon cambia il markup.
private let amazonExtractorJS = """
(function() {
    const results = [];

    // Ogni libro è in un contenitore con classe kp-notebook-library-each-book
    // (nome classe stabile da anni, ma potrebbe cambiare)
    const bookContainers = document.querySelectorAll('#kp-notebook-annotations .a-section');

    bookContainers.forEach(section => {
        // Titolo e autore del libro
        const titleEl  = section.querySelector('h2, .kp-notebook-searchable');
        const authorEl = section.querySelector('.kp-notebook-metadata span:first-child');

        if (!titleEl) return;

        const bookTitle  = titleEl.textContent.trim();
        const bookAuthor = authorEl ? authorEl.textContent.trim() : '';

        // Ogni highlight ha id che inizia con "highlight-"
        const highlightEls = section.querySelectorAll('[id^="highlight-"]');

        highlightEls.forEach(hlEl => {
            const contentEl  = hlEl.querySelector('.kp-notebook-highlight');
            const locationEl = hlEl.querySelector('.kp-notebook-highlight-location');
            const colorEl    = hlEl.querySelector('[class*="kp-notebook-highlight-"]');

            if (!contentEl || !contentEl.textContent.trim()) return;

            // Estrai il colore dal nome della classe (es. "kp-notebook-highlight-yellow")
            let color = null;
            if (colorEl) {
                const match = colorEl.className.match(/kp-notebook-highlight-(yellow|blue|pink|orange)/);
                if (match) color = match[1];
            }

            results.push({
                bookTitle:  bookTitle,
                bookAuthor: bookAuthor,
                content:    contentEl.textContent.trim(),
                location:   locationEl ? locationEl.textContent.trim() : null,
                color:      color
            });
        });
    });

    return JSON.stringify(results);
})();
"""

// Coordinator che gestisce la comunicazione WebView → Swift
public final class AmazonSyncCoordinator: NSObject, WKScriptMessageHandler {

    public var onHighlightsExtracted: (([AmazonHighlight]) -> Void)?
    public var onError: ((AmazonSyncError) -> Void)?

    // WKScriptMessageHandler: riceve il JSON dal JS iniettato
    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "marginaliaHighlights",
              let jsonString = message.body as? String else { return }

        parseAndDeliver(jsonString)
    }

    // Chiamato dopo che il WebView ha navigato su read.amazon.com/kp/notebook
    public func extractFromWebView(_ webView: WKWebView) {
        webView.evaluateJavaScript(amazonExtractorJS) { [weak self] result, error in
            if let error {
                self?.onError?(.extractionFailed(error.localizedDescription))
                return
            }
            guard let jsonString = result as? String else {
                self?.onError?(.extractionFailed("JavaScript non ha restituito una stringa"))
                return
            }
            self?.parseAndDeliver(jsonString)
        }
    }

    private func parseAndDeliver(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            onError?(.extractionFailed("JSON non parsabile"))
            return
        }

        if raw.isEmpty {
            onError?(.noHighlightsFound)
            return
        }

        let highlights: [AmazonHighlight] = raw.compactMap { dict in
            guard let content = dict["content"] as? String,
                  let bookTitle = dict["bookTitle"] as? String,
                  !content.isEmpty, !bookTitle.isEmpty else { return nil }

            return AmazonHighlight(
                bookTitle:  bookTitle,
                bookAuthor: dict["bookAuthor"] as? String ?? "",
                content:    content,
                location:   dict["location"] as? String,
                color:      dict["color"] as? String
            )
        }

        onHighlightsExtracted?(highlights)
    }
}

// Converte AmazonHighlight → ParsedClipping per riutilizzare ImportService
public extension AmazonHighlight {
    func asParsedClipping() -> ParsedClipping {
        ParsedClipping(
            title:    bookTitle,
            author:   bookAuthor,
            type:     .highlight,
            location: location,
            addedAt:  nil,   // Amazon non espone la data di sottolineatura nel notebook
            content:  content
        )
    }
}
