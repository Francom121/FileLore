import XCTest
@testable import TetherCore

final class NoteCodecTests: XCTestCase {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        return e
    }()

    func testEnvelopeVersionIsOne() throws {
        let envelope = NoteEnvelope(note: Note(body: "hi"))
        let data = try encoder.encode(envelope)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 1)
        XCTAssertNotNil(json["note"])
    }

    func testEncodeDecodeRoundTripIsStable() throws {
        let link = LinkedFile(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            bookmark: Data([0x01, 0x02, 0x03, 0xFF]),
            displayName: "ref photo.png",
            relativePathHint: "refs/ref photo.png"
        )
        let note = Note(
            body: "Prompt: neon fox",
            tags: ["project-a", "fox"],
            links: [link],
            created: Date(timeIntervalSince1970: 1_700_000_000.25),
            modified: Date(timeIntervalSince1970: 1_700_000_100.5)
        )
        let envelope = NoteEnvelope(note: note)

        let data1 = try encoder.encode(envelope)
        let decoded = try JSONDecoder().decode(NoteEnvelope.self, from: data1)
        XCTAssertEqual(decoded, envelope)

        // Encoding the decoded value again must produce byte-identical JSON.
        let data2 = try encoder.encode(decoded)
        XCTAssertEqual(data1, data2)
    }

    func testDecodesKnownLiteralJSON() throws {
        let json = """
        {
          "version": 1,
          "note": {
            "body": "cafe\\u0301 body",
            "tags": ["t1"],
            "links": [],
            "created": 410248800,
            "modified": 410248800
          }
        }
        """.data(using: .utf8)!

        let envelope = try JSONDecoder().decode(NoteEnvelope.self, from: json)
        XCTAssertEqual(envelope.version, 1)
        XCTAssertEqual(envelope.note.body, "cafe\u{301} body")
        XCTAssertEqual(envelope.note.tags, ["t1"])
        XCTAssertEqual(envelope.note.created, Date(timeIntervalSinceReferenceDate: 410248800))
    }

    func testBookmarkDataEncodesAsBase64() throws {
        let raw = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let note = Note(links: [LinkedFile(bookmark: raw, displayName: "x", relativePathHint: "x")])
        let data = try encoder.encode(NoteEnvelope(note: note))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains(raw.base64EncodedString()), "bookmark Data should be base64 in JSON")

        let decoded = try JSONDecoder().decode(NoteEnvelope.self, from: data)
        XCTAssertEqual(decoded.note.links.first?.bookmark, raw)
    }
}
