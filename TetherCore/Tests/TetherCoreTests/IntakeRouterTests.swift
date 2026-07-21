import Foundation
import XCTest
@testable import TetherCore

final class IntakeRouterTests: XCTestCase {

    func testEmptyInputRoutesToNone() {
        XCTAssertEqual(IntakeRouter.decide(paths: []), .none)
        XCTAssertEqual(IntakeRouter.decide(urls: []), .none)
    }

    func testBlankPathsAreDropped() {
        XCTAssertEqual(IntakeRouter.decide(paths: [""]), .none)
        XCTAssertEqual(
            IntakeRouter.decide(paths: ["", "/tmp/a.txt"]),
            .single(URL(fileURLWithPath: "/tmp/a.txt"))
        )
    }

    func testOneFileRoutesToSingle() {
        let url = URL(fileURLWithPath: "/tmp/one.txt")
        XCTAssertEqual(IntakeRouter.decide(paths: ["/tmp/one.txt"]), .single(url))
        XCTAssertEqual(IntakeRouter.decide(urls: [url]), .single(url))
    }

    func testMultipleDistinctFilesRouteToBatchOrderPreserved() {
        XCTAssertEqual(
            IntakeRouter.decide(paths: ["/tmp/b.txt", "/tmp/a.txt", "/tmp/c.txt"]),
            .batch([
                URL(fileURLWithPath: "/tmp/b.txt"),
                URL(fileURLWithPath: "/tmp/a.txt"),
                URL(fileURLWithPath: "/tmp/c.txt"),
            ])
        )
    }

    func testDuplicatePathsCollapseToSingle() {
        let url = URL(fileURLWithPath: "/tmp/dup.txt")
        XCTAssertEqual(IntakeRouter.decide(paths: ["/tmp/dup.txt", "/tmp/dup.txt"]), .single(url))
        // Non-normalized spellings of the same path also collapse.
        XCTAssertEqual(IntakeRouter.decide(paths: ["/tmp/dup.txt", "/tmp/./dup.txt"]), .single(url))
        XCTAssertEqual(IntakeRouter.decide(paths: ["/tmp//dup.txt", "/tmp/dup.txt"]), .single(url))
    }

    func testCaseInsensitiveDedupeKeepsFirstSpelling() {
        XCTAssertEqual(
            IntakeRouter.decide(paths: ["/tmp/ReadMe.md", "/tmp/README.md"]),
            .single(URL(fileURLWithPath: "/tmp/ReadMe.md"))
        )
    }

    func testDuplicatesCollapsingToTwoDistinctFilesStillRouteToBatch() {
        XCTAssertEqual(
            IntakeRouter.decide(paths: ["/tmp/a.txt", "/tmp/b.txt", "/tmp/a.txt"]),
            .batch([
                URL(fileURLWithPath: "/tmp/a.txt"),
                URL(fileURLWithPath: "/tmp/b.txt"),
            ])
        )
    }

    func testURLIntakeComparesByPathNotIdentity() {
        let urls = [
            URL(fileURLWithPath: "/tmp/x.txt"),
            URL(fileURLWithPath: "/tmp/x.txt"),
            URL(fileURLWithPath: "/tmp/y.txt"),
        ]
        XCTAssertEqual(
            IntakeRouter.decide(urls: urls),
            .batch([
                URL(fileURLWithPath: "/tmp/x.txt"),
                URL(fileURLWithPath: "/tmp/y.txt"),
            ])
        )
    }
}
