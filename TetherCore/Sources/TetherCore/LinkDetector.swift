import Foundation

/// A web URL detected inside note text.
public struct DetectedLink: Equatable, Sendable {
    /// Range of the URL in the source string (UTF-16 based `NSRange`).
    public var range: NSRange
    public var url: URL

    public init(range: NSRange, url: URL) {
        self.range = range
        self.url = url
    }
}

/// Detects http/https URLs in note text so the UI can render them clickable.
public enum LinkDetector {

    public static func detectLinks(in text: String) -> [DetectedLink] {
        guard !text.isEmpty else { return [] }
        let types = NSTextCheckingResult.CheckingType.link.rawValue
        guard let detector = try? NSDataDetector(types: types) else { return [] }
        let fullRange = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, options: [], range: fullRange).compactMap { match in
            guard let url = match.url,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else { return nil }
            return DetectedLink(range: match.range, url: url)
        }
    }

    /// Note text with `.link` attributes applied to detected web URLs,
    /// ready for SwiftUI `Text` rendering (links become clickable).
    public static func attributedString(for text: String) -> AttributedString {
        var attributed = AttributedString(text)
        for link in detectLinks(in: text) {
            guard let stringRange = Range(link.range, in: text),
                  let attrRange = Range(stringRange, in: attributed) else { continue }
            attributed[attrRange].link = link.url
        }
        return attributed
    }
}
