import Foundation

// MARK: - String Utilities

extension String {
    /// Returns `self` if non-empty, otherwise `nil`.
    /// Unlike the trimmed variant, this preserves whitespace.
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    /// Returns `self` after trimming whitespace, or `nil` if the result is empty.
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Lowercased string with only letters and digits retained.
    /// Useful for ASCII-level text comparison ignoring punctuation and case.
    var asciiNormalized: String {
        lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Returns a string containing only CJK characters.
    var cjkOnly: String {
        String(filter(\.isCJK))
    }
}

// MARK: - Character Utilities

extension Character {
    /// Whether the character is in the CJK Unified Ideographs range
    /// (U+4E00–U+9FFF) or the CJK Extension A range (U+3400–U+4DBF).
    var isCJK: Bool {
        unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value)
        }
    }
}

// MARK: - Edit Distance

/// Classic Levenshtein edit distance between two strings.
func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
    editDistance(Array(lhs), Array(rhs))
}

/// Levenshtein edit distance between two character arrays.
func editDistance(_ lhs: [Character], _ rhs: [Character]) -> Int {
    if lhs.isEmpty { return rhs.count }
    if rhs.isEmpty { return lhs.count }

    var previous = Array(0...rhs.count)
    for (i, left) in lhs.enumerated() {
        var current = [i + 1] + Array(repeating: 0, count: rhs.count)
        for (j, right) in rhs.enumerated() {
            let substitutionCost = left == right ? 0 : 1
            current[j + 1] = min(
                previous[j + 1] + 1,
                current[j] + 1,
                previous[j] + substitutionCost
            )
        }
        previous = current
    }
    return previous[rhs.count]
}
