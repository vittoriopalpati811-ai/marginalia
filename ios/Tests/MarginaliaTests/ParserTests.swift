import XCTest
@testable import Marginalia

final class ParserTests: XCTestCase {

    var parser: MyClippingsParser!

    override func setUp() {
        super.setUp()
        parser = MyClippingsParser()
    }

    // MARK: - Fixture file

    func testParseSampleFixture() throws {
        let fixtureURL = Bundle.module.url(forResource: "sample_clippings", withExtension: "txt", subdirectory: "Fixtures")!
        let content = try String(contentsOf: fixtureURL, encoding: .utf8)

        let results = parser.parse(content)

        // Bookmark filtrati, duplicati rimossi, bookmark = 0
        XCTAssertFalse(results.isEmpty)

        let bookmarks = results.filter { $0.type == .bookmark }
        XCTAssertEqual(bookmarks.count, 0, "I bookmark non devono essere restituiti")

        let highlights = results.filter { $0.type == .highlight }
        let notes = results.filter { $0.type == .note }
        XCTAssertTrue(highlights.count > 0)
        XCTAssertTrue(notes.count > 0)
    }

    // MARK: - Deduplicazione

    func testDeduplicationKeepsLonger() {
        let input = """
        Thinking, Fast and Slow (Daniel Kahneman)
        - Your Highlight on page 88 | location 1340-1344 | Added on Monday, March 4, 2019 8:15:00 PM

        Short version of the highlight.
        ==========
        Thinking, Fast and Slow (Daniel Kahneman)
        - Your Highlight on page 88 | location 1340-1348 | Added on Monday, March 4, 2019 8:16:00 PM

        Short version of the highlight, with more content added at the end.
        ==========
        """

        let results = parser.parse(input)
        XCTAssertEqual(results.count, 1, "Il dedup deve mantenere un solo highlight")
        XCTAssertTrue(results[0].content.contains("with more content"), "Deve mantenere la versione più lunga")
    }

    // MARK: - Lingua

    func testItalianHeader() {
        let input = """
        Se una notte d'inverno un viaggiatore (Italo Calvino)
        - La tua evidenziazione a pagina 12 | posizione 178-181 | Aggiunto giovedì 3 gennaio 2019 09:14:00

        Stai per cominciare a leggere.
        ==========
        """

        let results = parser.parse(input)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].type, .highlight)
        XCTAssertEqual(results[0].title, "Se una notte d'inverno un viaggiatore")
        XCTAssertEqual(results[0].author, "Italo Calvino")
        XCTAssertEqual(results[0].location, "Location 178-181")
        XCTAssertFalse(results[0].content.isEmpty)
    }

    func testEnglishHeader() {
        let input = """
        The Name of the Rose (Umberto Eco)
        - Your Highlight on page 22 | location 315-318 | Added on Saturday, February 2, 2019 3:00:00 PM

        The library is testimony to truth and to error.
        ==========
        """

        let results = parser.parse(input)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].type, .highlight)
        XCTAssertEqual(results[0].title, "The Name of the Rose")
        XCTAssertEqual(results[0].author, "Umberto Eco")
    }

    // MARK: - Tipi

    func testNoteType() {
        let input = """
        Qualsiasi libro (Qualsiasi Autore)
        - Your Note on page 10 | location 150 | Added on Monday, January 7, 2019 10:00:00 AM

        Questa è una nota personale.
        ==========
        """

        let results = parser.parse(input)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].type, .note)
    }

    func testBookmarkFiltered() {
        let input = """
        Qualsiasi libro (Qualsiasi Autore)
        - Your Bookmark on page 10 | location 150 | Added on Monday, January 7, 2019 10:00:00 AM

        ==========
        """

        let results = parser.parse(input)
        XCTAssertEqual(results.count, 0, "I bookmark devono essere filtrati")
    }

    // MARK: - Edge case

    func testBOMStripped() {
        let input = "\u{FEFF}Book (Author)\n- Your Highlight on location 1 | Added on Monday, January 7, 2019\n\nContent.\n=========="
        let results = parser.parse(input)
        XCTAssertFalse(results.isEmpty, "Il BOM non deve rompere il parsing")
    }

    func testEmptyContent() {
        let results = parser.parse("")
        XCTAssertEqual(results.count, 0)
    }

    func testTitleWithParenthesesInName() {
        // Autori con parentesi nel nome (raro ma possibile)
        let input = """
        A Book Title (Author Name (PhD))
        - Your Highlight on location 100-102 | Added on Monday, January 7, 2019

        Highlight content here.
        ==========
        """
        let results = parser.parse(input)
        // Non deve crashare; l'autore potrebbe non essere perfetto ma il titolo sì
        XCTAssertFalse(results.isEmpty)
    }

    func testMultipleBooks() {
        let input = """
        Book One (Author A)
        - Your Highlight on location 10-12 | Added on Monday, January 7, 2019

        Content of highlight one.
        ==========
        Book Two (Author B)
        - Your Highlight on location 20-22 | Added on Tuesday, January 8, 2019

        Content of highlight two.
        ==========
        """

        let results = parser.parse(input)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(Set(results.map(\.title)), ["Book One", "Book Two"])
    }
}
