import Foundation

struct ReplacementRule: Sendable {
    let source: String
    let target: String
}

struct CorrectionAnalysis: Sendable {
    let correctedText: String
    let matchedRuleCount: Int
    let matchedRuleTargets: [String]
    let removedSentenceFinalFiller: Bool
}

struct TextCorrectionPipeline: Sendable {
    let customPhrases: [String]
    let replacementRules: [ReplacementRule]

    init(settings: AppSettings) {
        let userPhrases: [String]
        let userRules: [ReplacementRule]

        if settings.enableCustomCorrectionLexicon {
            userPhrases = settings.customPhrasesText
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            userRules = settings.replacementRulesText
                .split(whereSeparator: \.isNewline)
                .compactMap(Self.parseRule)
        } else {
            userPhrases = []
            userRules = []
        }

        if settings.enableBuiltInFujianPack {
            let basePhrases = BuiltInFujianPreset.phrases(for: settings.speechMode)
            let baseRules = BuiltInFujianPreset.replacementRules(for: settings.speechMode)
            customPhrases = Array(NSOrderedSet(array: basePhrases + userPhrases)) as? [String] ?? (basePhrases + userPhrases)
            replacementRules = baseRules + userRules
        } else {
            customPhrases = userPhrases
            replacementRules = userRules
        }
    }

    func applyLocalCorrections(to text: String) -> String {
        analyzeCorrections(for: text).correctedText
    }

    func analyzeCorrections(for text: String) -> CorrectionAnalysis {
        guard !text.isEmpty else {
            return CorrectionAnalysis(
                correctedText: "",
                matchedRuleCount: 0,
                matchedRuleTargets: [],
                removedSentenceFinalFiller: false
            )
        }

        var output = text
        var matchedRuleCount = 0
        var matchedRuleTargets: [String] = []
        for rule in replacementRules {
            if output.contains(rule.source) {
                matchedRuleCount += output.components(separatedBy: rule.source).count - 1
                matchedRuleTargets.append(rule.target)
                output = output.replacingOccurrences(of: rule.source, with: rule.target)
            }
        }
        let withoutFillers = Self.removeSentenceFinalFillers(in: output)
        return CorrectionAnalysis(
            correctedText: withoutFillers.trimmingCharacters(in: .whitespacesAndNewlines),
            matchedRuleCount: matchedRuleCount,
            matchedRuleTargets: matchedRuleTargets,
            removedSentenceFinalFiller: withoutFillers != output
        )
    }

    private static func parseRule(from rawLine: Substring) -> ReplacementRule? {
        let text = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        for separator in ["=>", "->", "→"] {
            let parts = text.components(separatedBy: separator)
            if parts.count == 2 {
                let source = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let target = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !source.isEmpty, !target.isEmpty else { return nil }
                return ReplacementRule(source: source, target: target)
            }
        }

        return nil
    }

    private static func removeSentenceFinalFillers(in text: String) -> String {
        guard !text.isEmpty else { return text }

        let pattern = #"的话(?=\s*[，。！？；,.!?…]|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }
}
