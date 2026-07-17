import XCTest
@testable import TetherCore

final class SearchEngineTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func candidate(
        name: String,
        body: String = "",
        tags: [String] = [],
        modifiedDaysAgo: Double = 0,
        includeNote: Bool = true
    ) -> SearchCandidate {
        let url = URL(fileURLWithPath: "/tmp/\(name)")
        guard includeNote else {
            return SearchCandidate(fileURL: url, displayName: name, note: nil, updatedAt: base)
        }
        let note = Note(
            body: body,
            tags: tags,
            created: base,
            modified: base.addingTimeInterval(-modifiedDaysAgo * 86_400)
        )
        return SearchCandidate(fileURL: url, note: note)
    }

    func testNameMatchOutranksTagMatchOutranksBodyMatch() {
        let candidates = [
            candidate(name: "clip.mp4", body: "generated with aurora model"),        // body
            candidate(name: "photo.png", tags: ["aurora"]),                          // tag
            candidate(name: "aurora-final.mov", body: "nothing here"),               // name
        ]
        let results = SearchEngine.search("aurora", in: candidates)
        XCTAssertEqual(results.map(\.candidate.displayName), ["aurora-final.mov", "photo.png", "clip.mp4"])
        XCTAssertEqual(results.map(\.match), [.name, .tag, .body] as [SearchResult.MatchKind?])
    }

    func testWithinTierMostRecentFirst() {
        let candidates = [
            candidate(name: "a.mp4", tags: ["render"], modifiedDaysAgo: 10),
            candidate(name: "b.mp4", tags: ["render"], modifiedDaysAgo: 1),
            candidate(name: "c.mp4", tags: ["render"], modifiedDaysAgo: 5),
        ]
        let results = SearchEngine.search("render", in: candidates)
        XCTAssertEqual(results.map(\.candidate.displayName), ["b.mp4", "c.mp4", "a.mp4"])
    }

    func testTagMatchDoesNotFallThroughToBodyTier() {
        // A file matching both tag and body ranks in the tag tier.
        let candidates = [
            candidate(name: "x.mp4", body: "sunset vibes"),                          // body only
            candidate(name: "y.mp4", body: "sunset vibes", tags: ["sunset"]),        // tag tier
        ]
        let results = SearchEngine.search("sunset", in: candidates)
        XCTAssertEqual(results.map(\.match) as [SearchResult.MatchKind?], [.tag, .body])
        XCTAssertEqual(results.first?.candidate.displayName, "y.mp4")
    }

    func testCaseAndDiacriticInsensitiveMatching() {
        let candidates = [
            candidate(name: "B-Roll.MP4", body: "naïve façade study", tags: ["CAFÉ"]),
        ]
        XCTAssertEqual(SearchEngine.search("b-roll", in: candidates).count, 1)
        XCTAssertEqual(SearchEngine.search("cafe", in: candidates).count, 1)
        XCTAssertEqual(SearchEngine.search("CAFÉ", in: candidates).count, 1)
        let bodyHits = SearchEngine.search("NAIVE", in: candidates)
        XCTAssertEqual(bodyHits.count, 1)
        XCTAssertEqual(bodyHits.first?.match, .body)
    }

    func testBodySnippetIsWindowedAndEllipsized() {
        let padding = String(repeating: "lorem ipsum dolor sit amet ", count: 20)
        let body = padding + "SECRETTOKEN" + padding
        let results = SearchEngine.search("secrettoken", in: [candidate(name: "f.mp4", body: body)])
        let snippet = try? XCTUnwrap(results.first?.snippet)
        XCTAssertNotNil(snippet)
        XCTAssertTrue(snippet?.localizedCaseInsensitiveContains("SECRETTOKEN") ?? false)
        XCTAssertTrue(snippet?.hasPrefix("…") ?? false)
        XCTAssertTrue(snippet?.hasSuffix("…") ?? false)
        XCTAssertLessThanOrEqual(snippet?.count ?? .max, 100)
    }

    func testShortBodySnippetHasNoEllipses() {
        let results = SearchEngine.search("cat", in: [candidate(name: "f.mp4", body: "the cat sat")])
        XCTAssertEqual(results.first?.snippet, "the cat sat")
    }

    func testEmptyQueryReturnsAllMostRecentFirst() {
        let candidates = [
            candidate(name: "old.mp4", modifiedDaysAgo: 30),
            candidate(name: "new.mp4", modifiedDaysAgo: 0),
            candidate(name: "mid.mp4", modifiedDaysAgo: 10),
        ]
        for query in ["", "   ", "\n"] {
            let results = SearchEngine.search(query, in: candidates)
            XCTAssertEqual(results.map(\.candidate.displayName), ["new.mp4", "mid.mp4", "old.mp4"])
            XCTAssertTrue(results.allSatisfy { $0.match == nil })
        }
    }

    func testEmptyQueryIsCapped() {
        let candidates = (0..<80).map { candidate(name: "file\($0).mp4") }
        XCTAssertEqual(SearchEngine.search("", in: candidates).count, SearchEngine.defaultLimit)
        XCTAssertEqual(SearchEngine.search("", in: candidates, limit: 5).count, 5)
    }

    func testFileWithoutNoteStillMatchesByNameOnly() {
        let candidates = [candidate(name: "ghost.mp4", body: "ignored", tags: ["ignored"], includeNote: false)]
        XCTAssertEqual(SearchEngine.search("ghost", in: candidates).count, 1)
        XCTAssertEqual(SearchEngine.search("ignored", in: candidates).count, 0)
        XCTAssertTrue(SearchEngine.search("ghost", in: candidates).first?.candidate.noteMissing ?? false)
    }

    func testNoMatchReturnsEmpty() {
        XCTAssertTrue(SearchEngine.search("zzz", in: [candidate(name: "a.mp4", body: "b", tags: ["c"])]).isEmpty)
    }
}
