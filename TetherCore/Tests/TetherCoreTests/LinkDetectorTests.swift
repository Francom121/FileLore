import XCTest
@testable import TetherCore

final class LinkDetectorTests: XCTestCase {

    func testNoLinks() {
        XCTAssertTrue(LinkDetector.detectLinks(in: "").isEmpty)
        XCTAssertTrue(LinkDetector.detectLinks(in: "just some plain text, no links").isEmpty)
    }

    func testSingleURL() {
        let text = "Model page: https://example.com/models/flux is great"
        let links = LinkDetector.detectLinks(in: text)
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first?.url.host, "example.com")
        XCTAssertEqual(links.first?.url.path, "/models/flux")
        // The detected range must map back to the URL substring.
        if let r = links.first.flatMap({ Range($0.range, in: text) }) {
            XCTAssertEqual(String(text[r]), "https://example.com/models/flux")
        } else {
            XCTFail("range did not convert")
        }
    }

    func testTrailingPunctuationIsExcluded() {
        let text = "See https://example.com/page."
        let links = LinkDetector.detectLinks(in: text)
        XCTAssertEqual(links.count, 1)
        XCTAssertFalse(links.first?.url.absoluteString.hasSuffix(".") ?? true,
                       "trailing sentence punctuation should not be part of the URL")
    }

    func testMultipleURLs() {
        let text = "refs: https://a.example/1 and https://b.example/2?q=swift done"
        let links = LinkDetector.detectLinks(in: text)
        XCTAssertEqual(links.count, 2)
        XCTAssertEqual(links[0].url.host, "a.example")
        XCTAssertEqual(links[1].url.host, "b.example")
        XCTAssertEqual(links[1].url.query, "q=swift")
    }

    func testNonWebSchemesAreIgnored() {
        XCTAssertTrue(LinkDetector.detectLinks(in: "ftp://files.example/x").isEmpty)
        XCTAssertTrue(LinkDetector.detectLinks(in: "mail me at fox@example.com").isEmpty)
    }

    func testAttributedStringMarksLinksClickable() {
        let text = "open https://example.com/docs for details"
        let attributed = LinkDetector.attributedString(for: text)
        var foundLink: URL?
        for run in attributed.runs {
            if let url = run.link { foundLink = url }
        }
        XCTAssertEqual(foundLink?.host, "example.com")
    }
}
