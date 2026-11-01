import Foundation

/// Matches switcher items against what the user types.
enum SearchFilter {
    /// Every word of `query` must appear somewhere in `fields`, ignoring case and accents
    /// ("code ser" matches "Code — SwitcherController.swift"). An empty query matches everything.
    static func matches(_ query: String, fields: [String]) -> Bool {
        let words = normalized(query).split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let haystack = normalized(fields.joined(separator: " "))
        return words.allSatisfy { haystack.contains($0) }
    }

    static func filter(_ items: [SwitcherItem], query: String) -> [SwitcherItem] {
        items.filter { item in
            matches(query, fields: [item.primary.appName] + item.windows.map(\.title))
        }
    }

    /// Where each query word first appears in `text`, for highlighting.
    static func highlightRanges(_ query: String, in text: String) -> [NSRange] {
        query.split(whereSeparator: \.isWhitespace).compactMap { word in
            text.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]).map { NSRange($0, in: text) }
        }
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
