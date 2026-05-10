import Foundation

// Parsa il file My Clippings.txt di Kindle.
//
// Formato del file:
//   TITOLO (Autore)
//   - Your Highlight on page X | location Y-Z | Added on ...
//
//   Testo dell'highlight.
//   ==========
//
// Edge case gestiti:
// - Header in italiano, inglese, francese
// - Encoding BOM UTF-8
// - Separatori ==========  (esattamente 10 =) su riga propria
// - Bookmark ignorati
// - Dedup: highlight sovrapposti → tieni il più lungo
// - Contenuto che contiene ========== nel mezzo del testo

public struct ParsedClipping: Equatable {
    public let title: String
    public let author: String
    public let type: ClippingType
    public let location: String?
    public let addedAt: Date?
    public let content: String

    public enum ClippingType: Equatable {
        case highlight, note, bookmark
    }
}

public struct MyClippingsParser {

    public init() {}

    public func parse(_ rawContent: String) -> [ParsedClipping] {
        let normalized = rawContent
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .init(charactersIn: "\u{FEFF}")) // strip BOM

        // Separa i blocchi usando il pattern "==========\n" o "==========" a fine file.
        // Usiamo un separatore che è esattamente 10 = su riga propria.
        let separatorPattern = "\n=========="
        let blocks = normalized
            .components(separatedBy: separatorPattern)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var clippings: [ParsedClipping] = []

        for block in blocks {
            guard let clipping = parseBlock(block) else { continue }
            clippings.append(clipping)
        }

        return deduplicate(clippings)
    }

    // MARK: - Private

    private func parseBlock(_ block: String) -> ParsedClipping? {
        let lines = block.components(separatedBy: "\n")
        guard lines.count >= 2 else { return nil }

        let titleLine = lines[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let metaLine = lines[1].trimmingCharacters(in: .whitespacesAndNewlines)

        // Il contenuto inizia dalla terza riga (lines[2] potrebbe essere vuota, poi il testo)
        let contentLines = lines.dropFirst(2).drop(while: { $0.trimmingCharacters(in: .whitespaces).isEmpty })
        let content = contentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        let (title, author) = parseTitleLine(titleLine)
        guard !title.isEmpty else { return nil }

        let type = parseType(from: metaLine)
        let location = parseLocation(from: metaLine)
        let addedAt = parseDate(from: metaLine)

        return ParsedClipping(
            title: title,
            author: author,
            type: type,
            location: location,
            addedAt: addedAt,
            content: content
        )
    }

    private func parseTitleLine(_ line: String) -> (title: String, author: String) {
        // "Book Title (Author Name)" — autore nell'ultima coppia di parentesi
        guard let lastOpen = line.lastIndex(of: "("),
              let lastClose = line.lastIndex(of: ")"),
              lastClose > lastOpen else {
            return (line, "")
        }
        let authorStart = line.index(after: lastOpen)
        let author = String(line[authorStart..<lastClose]).trimmingCharacters(in: .whitespaces)
        let title = String(line[..<lastOpen]).trimmingCharacters(in: .whitespaces)
        return (title, author)
    }

    private func parseType(from meta: String) -> ParsedClipping.ClippingType {
        let lower = meta.lowercased()
        if lower.contains("your note") || lower.contains("la tua nota") || lower.contains("votre note") {
            return .note
        }
        if lower.contains("bookmark") || lower.contains("segnalibro") || lower.contains("signet") {
            return .bookmark
        }
        return .highlight
    }

    private func parseLocation(from meta: String) -> String? {
        // Cerca "location NNN" o "posizione NNN" o "emplacement NNN"
        let pattern = #"(?:location|posizione|emplacement)\s+([\d\-]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: meta, range: NSRange(meta.startIndex..., in: meta)),
              let range = Range(match.range(at: 1), in: meta) else {
            return nil
        }
        return "Location " + String(meta[range])
    }

    private func parseDate(from meta: String) -> Date? {
        // Cerca la data dopo "Added on" / "Aggiunto" / "Ajouté le"
        // EN: "Saturday, January 2, 2021 3:00:00 PM"
        // IT: "mercoledì 4 gennaio 2021 14:30:00"
        let dateFormatters: [DateFormatter] = Self.makeDateFormatters()
        let pattern = #"(?:added on|aggiunto|ajouté le)[^\d]+([\w, :0-9APMapm]+)"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: meta, range: NSRange(meta.startIndex..., in: meta)),
              let range = Range(match.range(at: 1), in: meta) else {
            return nil
        }

        let dateString = String(meta[range]).trimmingCharacters(in: .whitespaces)
        for formatter in dateFormatters {
            if let date = formatter.date(from: dateString) {
                return date
            }
        }
        return nil
    }

    // Kindle a volte salva lo stesso highlight più volte man mano che si estende la selezione.
    // Per ogni (titolo, autore, location), teniamo la versione con il contenuto più lungo.
    private func deduplicate(_ clippings: [ParsedClipping]) -> [ParsedClipping] {
        var seen: [String: ParsedClipping] = [:]
        for clipping in clippings {
            let key = "\(clipping.title)||||\(clipping.author)||||\(clipping.location ?? "")"
            if let existing = seen[key] {
                if clipping.content.count > existing.content.count {
                    seen[key] = clipping
                }
            } else {
                seen[key] = clipping
            }
        }
        return clippings.filter { c in
            let key = "\(c.title)||||\(c.author)||||\(c.location ?? "")"
            return seen[key] == c
        }
    }

    private static func makeDateFormatters() -> [DateFormatter] {
        let formats = [
            "EEEE, MMMM d, yyyy h:mm:ss a",   // EN: Saturday, January 2, 2021 3:00:00 PM
            "EEEE, MMMM d, yyyy",               // EN senza ora
            "EEEE d MMMM yyyy HH:mm:ss",        // IT: mercoledì 4 gennaio 2021 14:30:00
            "EEEE d MMMM yyyy",                 // IT senza ora
        ]
        let locales = ["en_US_POSIX", "it_IT", "fr_FR"]

        return formats.flatMap { format in
            locales.map { locale -> DateFormatter in
                let f = DateFormatter()
                f.dateFormat = format
                f.locale = Locale(identifier: locale)
                return f
            }
        }
    }
}
