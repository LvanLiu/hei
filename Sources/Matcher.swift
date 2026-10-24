import Foundation

struct Match {
    let score: Int
    let titleSpans: [Range<Int>]
    let appSpans: [Range<Int>]
}

/// Tiered fuzzy matcher, modelled on AltTab's `SearchTestable` (tiers 1-5 simplified, subsequence added).
/// Spans are indices into the *original* string's character array, used for highlighting.
enum Matcher {
    static func match(query: String, app: String, title: String) -> Match? {
        let q = normalize(query)
        guard !q.chars.isEmpty else { return Match(score: 0, titleSpans: [], appSpans: []) }

        let titleNorm = normalize(title)
        let appNorm = normalize(app)
        let titleResult = score(query: q, text: titleNorm)
        let appResult = score(query: q, text: appNorm)

        let appScore = appResult.map { Int(Double($0.score) * 1.04) } ?? 0
        let titleScore = titleResult?.score ?? 0
        if appScore == 0 && titleScore == 0 { return nil }
        if appScore >= titleScore {
            return Match(score: appScore, titleSpans: [], appSpans: mapSpans(appResult?.spans ?? [], appNorm))
        }
        return Match(score: titleScore, titleSpans: mapSpans(titleResult?.spans ?? [], titleNorm), appSpans: [])
    }

    /// Converts normalized character indices back to indices in the original string.
    private static func mapSpans(_ spans: [Range<Int>], _ norm: Norm) -> [Range<Int>] {
        spans.compactMap { span in
            guard !span.isEmpty, span.upperBound <= norm.toOriginal.count else { return nil }
            let start = norm.toOriginal[span.lowerBound]
            let end = norm.toOriginal[span.upperBound - 1] + 1
            return start..<end
        }
    }

    struct Norm {
        var chars: [Character]
        var toOriginal: [Int]
        var isWordStart: [Bool]
    }

    private struct Scored {
        let score: Int
        let spans: [Range<Int>]
    }

    static func normalize(_ text: String) -> Norm {
        let original = Array(text)
        var chars: [Character] = []
        var map: [Int] = []
        var starts: [Bool] = []
        chars.reserveCapacity(original.count)
        map.reserveCapacity(original.count)
        starts.reserveCapacity(original.count)

        for (index, character) in original.enumerated() {
            if character.isWhitespace { continue }
            let folded = String(character).folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
                                                  locale: Locale(identifier: "en_US"))
            let start = isWordStart(original, index)
            var first = true
            for foldedChar in folded {
                chars.append(foldedChar)
                map.append(index)
                starts.append(first && start)
                first = false
            }
        }
        return Norm(chars: chars, toOriginal: map, isWordStart: starts)
    }

    private static func isWordStart(_ chars: [Character], _ index: Int) -> Bool {
        let character = chars[index]
        guard character.isLetter || character.isNumber else { return false }
        if index == 0 { return true }
        let previous = chars[index - 1]
        if !(previous.isLetter || previous.isNumber) { return true }
        if previous.isLowercase && character.isUppercase { return true }
        return false
    }

    private static func score(query: Norm, text: Norm) -> Scored? {
        let q = query.chars
        let t = text.chars
        guard !q.isEmpty, !t.isEmpty else { return nil }
        guard q.count <= t.count else { return nil }

        if q == t {
            return Scored(score: 1000 + positionBonus(0), spans: [0..<t.count])
        }
        if Array(t[0..<q.count]) == q {
            return Scored(score: 860 + positionBonus(0), spans: [0..<q.count])
        }
        for index in 0..<t.count where text.isWordStart[index] && index + q.count <= t.count {
            if Array(t[index..<index + q.count]) == q {
                return Scored(score: 700 + positionBonus(index), spans: [index..<index + q.count])
            }
        }
        if let start = firstSubstring(q, in: t) {
            return Scored(score: 540 + positionBonus(start), spans: [start..<start + q.count])
        }
        if let spans = acronym(q, t, text.isWordStart) {
            return Scored(score: 320 + positionBonus(spans[0].lowerBound), spans: spans)
        }
        if let spans = subsequence(q, t) {
            let width = spans[spans.count - 1].upperBound - spans[0].lowerBound
            let gaps = max(0, width - q.count)
            return Scored(score: 160 - min(120, gaps * 3), spans: spans)
        }
        return nil
    }

    private static func positionBonus(_ index: Int) -> Int {
        max(0, 30 - index)
    }

    private static func firstSubstring(_ needle: [Character], in haystack: [Character]) -> Int? {
        guard needle.count <= haystack.count else { return nil }
        for start in 0...(haystack.count - needle.count) {
            if Array(haystack[start..<start + needle.count]) == needle { return start }
        }
        return nil
    }

    private static func acronym(_ query: [Character], _ text: [Character], _ isWordStart: [Bool]) -> [Range<Int>]? {
        var queryIndex = 0
        var spans: [Range<Int>] = []
        for index in 0..<text.count {
            guard queryIndex < query.count else { break }
            if isWordStart[index] && text[index] == query[queryIndex] {
                spans.append(index..<(index + 1))
                queryIndex += 1
            }
        }
        return queryIndex == query.count ? spans : nil
    }

    private static func subsequence(_ query: [Character], _ text: [Character]) -> [Range<Int>]? {
        var queryIndex = 0
        var textIndex = 0
        var spans: [Range<Int>] = []
        while queryIndex < query.count && textIndex < text.count {
            if query[queryIndex] == text[textIndex] {
                spans.append(textIndex..<(textIndex + 1))
                queryIndex += 1
            }
            textIndex += 1
        }
        return queryIndex == query.count ? spans : nil
    }
}
