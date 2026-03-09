import Foundation

enum ReplacementMode: String, Sendable {
    case candidate
    case reject
}

struct ReRecognitionEvaluator {
    struct Configuration: Sendable {
        let minimumPromotionScore: Int
        let severePenaltyThreshold: Int
        let chinesePreservationReward: Int
        let mixedLanguagePenaltyThreshold: Int
        let traditionalVariantPenaltyThreshold: Int

        static let `default` = Configuration(
            minimumPromotionScore: 2,
            severePenaltyThreshold: -3,
            chinesePreservationReward: 1,
            mixedLanguagePenaltyThreshold: 2,
            traditionalVariantPenaltyThreshold: 2
        )
    }

    private let correctionPipeline: TextCorrectionPipeline
    private let configuration: Configuration
    private let asciiPriorityPhrases: [String]
    private let uppercasePriorityPhrases: [String]
    private let chineseReferencePhrases: [String]
    private let lowNaturalnessChineseFragments: [String: Int]
    private let chineseConfusableVariants: [ChineseConfusableVariant]
    private let weakChinesePrefixes: Set<String>

    private struct ChineseConfusableVariant: Sendable {
        let variant: String
        let expected: String
        let penalty: Int
    }

    init(
        correctionPipeline: TextCorrectionPipeline,
        configuration: Configuration = .default
    ) {
        self.correctionPipeline = correctionPipeline
        self.configuration = configuration
        self.asciiPriorityPhrases = correctionPipeline.customPhrases.filter {
            $0.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil
        }
        self.uppercasePriorityPhrases = asciiPriorityPhrases.filter {
            $0 != $0.lowercased() && $0 != $0.uppercased()
                || $0 == $0.uppercased()
        }
        self.chineseReferencePhrases = [
            "语音转写成文字",
            "转写成文字",
            "部署系统",
            "转写效果",
            "先不要",
            "先不用",
            "开放给外部用户",
            "改主链路"
        ]
        self.lowNaturalnessChineseFragments = [
            "已音": 2,
            "已转": 1,
            "已轉": 1,
            "不数": 1,
            "不属": 1,
            "不屬": 1,
            "传写": 2,
            "傳寫": 2,
            "專寫": 2,
            "已專": 2,
            "已應": 2,
            "已經轉": 1,
            "心不要": 2,
            "新不要": 2,
            "心不用": 2,
            "新不用": 2
        ]
        self.chineseConfusableVariants = [
            .init(variant: "已音", expected: "语音", penalty: 2),
            .init(variant: "已转", expected: "语音转", penalty: 2),
            .init(variant: "已轉", expected: "语音转", penalty: 2),
            .init(variant: "傳寫", expected: "转写", penalty: 2),
            .init(variant: "传写", expected: "转写", penalty: 2),
            .init(variant: "專寫", expected: "转写", penalty: 2),
            .init(variant: "已專", expected: "已转", penalty: 1),
            .init(variant: "已應", expected: "语音", penalty: 2),
            .init(variant: "已經轉", expected: "语音转", penalty: 1),
            .init(variant: "不属", expected: "部署", penalty: 1),
            .init(variant: "不屬", expected: "部署", penalty: 1),
            .init(variant: "不数", expected: "部署", penalty: 1)
        ]
        self.weakChinesePrefixes = [
            "已",
            "已经",
            "已經",
            "已转",
            "已轉",
            "已应",
            "已應",
            "就",
            "都",
            "又",
            "也"
        ]
    }

    func evaluate(
        plan: ReRecognitionPlan,
        originalWindowText: String,
        rerecognizedText: String,
        triggerFlags: [SuspicionFlag],
        backend: String,
        sessionID: UUID?
    ) -> ReRecognitionCandidateRecord {
        var score = 0
        var reasons: [String] = []

        let originalTrimmed = originalWindowText.trimmingCharacters(in: .whitespacesAndNewlines)
        let rerecognizedTrimmed = rerecognizedText.trimmingCharacters(in: .whitespacesAndNewlines)

        let originalCorrection = correctionPipeline.analyzeCorrections(for: originalTrimmed)
        let rerecognizedCorrection = correctionPipeline.analyzeCorrections(for: rerecognizedTrimmed)

        let triggerCodes = Set(triggerFlags.map(\.code))

        if triggerCodes.contains("hotword_miss") {
            let originalHotwordHits = matchedHotwordCount(in: originalTrimmed)
            let rerecognizedHotwordHits = matchedHotwordCount(in: rerecognizedTrimmed)

            if rerecognizedHotwordHits > originalHotwordHits {
                score += 3
                reasons.append("热词命中改善")
            } else {
                score -= 2
                reasons.append("热词命中没有改善")
            }
        }

        if triggerCodes.contains("english_abbreviation") {
            let originalAnomaly = englishAbbreviationPenalty(in: originalTrimmed)
            let rerecognizedAnomaly = englishAbbreviationPenalty(in: rerecognizedTrimmed)

            if rerecognizedAnomaly < originalAnomaly {
                score += 2
                reasons.append("英文缩写结构更稳定")
            } else if rerecognizedAnomaly > originalAnomaly {
                score -= 2
                reasons.append("英文缩写结构退化")
            }
        }

        if triggerCodes.contains("number_unit_format") {
            let originalAnomaly = hasNumberUnitAnomaly(originalTrimmed)
            let rerecognizedAnomaly = hasNumberUnitAnomaly(rerecognizedTrimmed)

            if originalAnomaly && !rerecognizedAnomaly {
                score += 2
                reasons.append("数字/单位格式改善")
            } else if !originalAnomaly && rerecognizedAnomaly {
                score -= 2
                reasons.append("数字/单位格式退化")
            }
        }

        if triggerCodes.contains("heavy_local_correction") || triggerCodes.contains("hotword_miss") {
            if rerecognizedCorrection.matchedRuleCount < originalCorrection.matchedRuleCount {
                score += 2
                reasons.append("对本地修正规则的依赖下降")
            } else if rerecognizedCorrection.matchedRuleCount > originalCorrection.matchedRuleCount {
                score -= 1
                reasons.append("对本地修正规则的依赖上升")
            }
        }

        if isLikelyChineseWindow(originalTrimmed) {
            let originalEnglishSeverity = englishIntrusionSeverity(in: originalTrimmed)
            let rerecognizedEnglishSeverity = englishIntrusionSeverity(in: rerecognizedTrimmed)
            if rerecognizedEnglishSeverity > originalEnglishSeverity {
                let delta = rerecognizedEnglishSeverity - originalEnglishSeverity
                score -= delta
                reasons.append(englishIntrusionReason(for: rerecognizedEnglishSeverity))
            }

            let originalMixedPenalty = mixedLanguageNaturalnessPenalty(in: originalTrimmed)
            let rerecognizedMixedPenalty = mixedLanguageNaturalnessPenalty(in: rerecognizedTrimmed)
            if rerecognizedMixedPenalty > originalMixedPenalty {
                let delta = rerecognizedMixedPenalty - originalMixedPenalty
                score -= delta
                reasons.append(mixedLanguagePenaltyReason(for: rerecognizedMixedPenalty))
            }

            if rerecognizedEnglishSeverity == 0, rerecognizedMixedPenalty == 0, containsEnoughChineseContent(rerecognizedTrimmed) {
                score += configuration.chinesePreservationReward
                reasons.append("候选保持了稳定中文表达")
            }

            let lowNaturalness = lowNaturalnessChinesePenalty(in: rerecognizedTrimmed)
            if lowNaturalness.penalty > 0 {
                score -= lowNaturalness.penalty
                reasons.append(lowNaturalness.reason)
            }

            let nearMiss = chineseReferenceNearMissPenalty(
                originalText: originalTrimmed,
                candidateText: rerecognizedTrimmed
            )
            if nearMiss.penalty > 0 {
                score -= nearMiss.penalty
                reasons.append(nearMiss.reason)
            }

            let confusablePenalty = chineseConfusableVariantPenalty(
                originalText: originalTrimmed,
                candidateText: rerecognizedTrimmed
            )
            if confusablePenalty.penalty > 0 {
                score -= confusablePenalty.penalty
                reasons.append(confusablePenalty.reason)
            }

            let scriptPenalty = traditionalVariantPenalty(
                originalText: originalTrimmed,
                candidateText: rerecognizedTrimmed
            )
            if scriptPenalty.penalty > 0 {
                score -= scriptPenalty.penalty
                reasons.append(scriptPenalty.reason)
            }

            let fullPhraseReward = completeChinesePhraseRetentionReward(
                originalText: originalTrimmed,
                candidateText: rerecognizedTrimmed
            )
            if fullPhraseReward.reward > 0 {
                score += fullPhraseReward.reward
                reasons.append(fullPhraseReward.reason)
            }

            let weakenedCandidatePenalty = weakenedChineseCandidatePenalty(
                originalText: originalTrimmed,
                candidateText: rerecognizedTrimmed
            )
            if weakenedCandidatePenalty.penalty > 0 {
                score -= weakenedCandidatePenalty.penalty
                reasons.append(weakenedCandidatePenalty.reason)
            }
        }

        if rerecognizedTrimmed.isEmpty {
            score -= 4
            reasons.append("重识别结果为空")
        }

        let originalLength = originalTrimmed.count
        let rerecognizedLength = rerecognizedTrimmed.count
        if originalLength >= 6 && rerecognizedLength <= max(2, Int(Double(originalLength) * 0.6)) {
            score -= 3
            reasons.append("重识别文本明显变短，可能丢信息")
        }

        let originalInfoDensity = informationDensity(originalTrimmed)
        let rerecognizedInfoDensity = informationDensity(rerecognizedTrimmed)
        if rerecognizedInfoDensity + 0.15 < originalInfoDensity {
            score -= 2
            reasons.append("重识别文本信息密度下降")
        }

        if fragmentationPenalty(in: rerecognizedTrimmed) > fragmentationPenalty(in: originalTrimmed) {
            score -= 1
            reasons.append("重识别文本更碎")
        }

        if reasons.isEmpty {
            reasons.append("未观察到明确改善")
        }

        let shouldPromoteCandidate = score >= configuration.minimumPromotionScore
            && score > configuration.severePenaltyThreshold
        return ReRecognitionCandidateRecord(
            id: UUID(),
            sessionID: sessionID,
            segmentIDs: plan.segmentIDs,
            originalText: originalTrimmed,
            candidateText: rerecognizedTrimmed,
            score: score,
            decisionReasons: reasons,
            triggerFlags: triggerFlags,
            startTime: plan.startTime,
            endTime: plan.endTime,
            backend: backend,
            shouldPromoteCandidate: shouldPromoteCandidate,
            replacementMode: shouldPromoteCandidate ? .candidate : .reject,
            createdAt: Date()
        )
    }

    private func matchedHotwordCount(in text: String) -> Int {
        let normalized = normalizedASCII(text)
        guard !normalized.isEmpty else { return 0 }
        return asciiPriorityPhrases.reduce(into: 0) { partialResult, phrase in
            let normalizedPhrase = normalizedASCII(phrase)
            if !normalizedPhrase.isEmpty, normalized.contains(normalizedPhrase) {
                partialResult += 1
            }
        }
    }

    private func englishAbbreviationPenalty(in text: String) -> Int {
        var penalty = 0
        if text.range(of: #"\b(?:[A-Za-z]\s+){2,}[A-Za-z]\b"#, options: .regularExpression) != nil {
            penalty += 2
        }

        let tokens = text.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).map(String.init)
        if tokens.contains(where: hasAcronymCaseDrop(token:)) {
            penalty += 1
        }
        return penalty
    }

    private func hasAcronymCaseDrop(token: String) -> Bool {
        let normalized = normalizedASCII(token)
        guard normalized.count >= 2, normalized.count <= 5 else { return false }
        return uppercasePriorityPhrases.contains(where: { normalizedASCII($0) == normalized && $0 != token })
    }

    private func hasNumberUnitAnomaly(_ text: String) -> Bool {
        if text.range(of: #"\b\d(?:\s+\d){1,}\b"#, options: .regularExpression) != nil {
            return true
        }
        if text.range(of: #"(?:\d+[零一二三四五六七八九十百千万]|[零一二三四五六七八九十百千万]+\d+)"#, options: .regularExpression) != nil {
            return true
        }
        if text.range(of: #"\b\d+\s+(?:gb|mb|tb|kg|km|hz|mhz|ghz|%)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        return false
    }

    private func informationDensity(_ text: String) -> Double {
        guard !text.isEmpty else { return 0 }
        let informativeCount = text.filter { $0.isLetter || $0.isNumber || isCJK($0) }.count
        return Double(informativeCount) / Double(text.count)
    }

    private func fragmentationPenalty(in text: String) -> Int {
        let tokens = text.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return 0 }
        return tokens.reduce(into: 0) { partialResult, token in
            if token.count <= 1 {
                partialResult += 1
            }
        }
    }

    private func normalizedASCII(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private func isLikelyChineseWindow(_ text: String) -> Bool {
        let cjkCount = text.filter(isCJK).count
        guard cjkCount >= 3 else { return false }
        return cjkRatio(in: text) >= 0.35
    }

    private func containsEnoughChineseContent(_ text: String) -> Bool {
        text.filter(isCJK).count >= 3 && cjkRatio(in: text) >= 0.5
    }

    private func cjkRatio(in text: String) -> Double {
        guard !text.isEmpty else { return 0 }
        let cjkCount = text.filter(isCJK).count
        return Double(cjkCount) / Double(text.count)
    }

    private func englishIntrusionSeverity(in text: String) -> Int {
        let asciiTokens = englishWordTokens(in: text)
        guard !asciiTokens.isEmpty else { return 0 }

        let lowerTokens = asciiTokens.map { $0.lowercased() }
        let cjkRatio = cjkRatio(in: text)
        let containsCJK = text.contains(where: isCJK)
        let suspiciousEnglishWords = Set(["you", "your", "and", "then", "write", "written", "translated", "translation", "in", "it"])
        let suspiciousHitCount = lowerTokens.filter { suspiciousEnglishWords.contains($0) }.count

        if asciiTokens.count >= 4 && (!containsCJK || cjkRatio < 0.3) {
            return 4
        }
        if asciiTokens.count == 1,
           let token = lowerTokens.first,
           suspiciousEnglishWords.contains(token) {
            return 3
        }
        if asciiTokens.count == 1 && !containsCJK {
            return 2
        }
        if suspiciousHitCount >= 2 {
            return 3
        }
        if containsCJK && asciiTokens.count >= 2 {
            return 2
        }
        return 1
    }

    private func mixedLanguageNaturalnessPenalty(in text: String) -> Int {
        let asciiTokens = englishWordTokens(in: text)
        let containsCJK = text.contains(where: isCJK)
        guard containsCJK, !asciiTokens.isEmpty else { return 0 }

        if text.range(of: #"[A-Za-z]{2,}[^\s，。！？；,!?]*[\u4E00-\u9FFF]"#, options: .regularExpression) != nil {
            return 3
        }
        if text.range(of: #"[\u4E00-\u9FFF][A-Za-z]{2,}"#, options: .regularExpression) != nil {
            return 2
        }
        if asciiTokens.count >= configuration.mixedLanguagePenaltyThreshold {
            return 2
        }
        return 1
    }

    private func englishIntrusionReason(for severity: Int) -> String {
        switch severity {
        case 4:
            return "候选明显跑偏成英文句子"
        case 3:
            return "候选出现明显英文语句侵入"
        case 2:
            return "候选出现不自然英文混入"
        default:
            return "候选出现少量英文侵入"
        }
    }

    private func mixedLanguagePenaltyReason(for severity: Int) -> String {
        switch severity {
        case 3:
            return "候选中英混杂且结构明显不自然"
        case 2:
            return "候选中英混杂语序不自然"
        default:
            return "候选存在轻微中英混杂"
        }
    }

    private func englishWordTokens(in text: String) -> [String] {
        text.split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil }
    }

    private func lowNaturalnessChinesePenalty(in text: String) -> (penalty: Int, reason: String) {
        let normalized = normalizedChinese(text)
        guard normalized.count >= 2 else { return (0, "") }

        var matched: [(String, Int)] = []
        for (fragment, penalty) in lowNaturalnessChineseFragments {
            if normalized.contains(fragment) {
                matched.append((fragment, penalty))
            }
        }

        guard let strongest = matched.max(by: { $0.1 < $1.1 }) else {
            return (0, "")
        }

        return (
            strongest.1,
            "候选出现低自然度中文片段：\(strongest.0)"
        )
    }

    private func chineseReferenceNearMissPenalty(
        originalText: String,
        candidateText: String
    ) -> (penalty: Int, reason: String) {
        let candidate = normalizedChinese(candidateText)
        guard candidate.count >= 4 else { return (0, "") }

        let dynamicReferences = candidateReferencePhrases(from: originalText)
        let references = Array(Set(chineseReferencePhrases + dynamicReferences)).filter { $0.count >= 4 }

        var bestMatch: (phrase: String, distance: Int)?
        for phrase in references {
            let normalizedPhrase = normalizedChinese(phrase)
            guard !normalizedPhrase.isEmpty, !candidate.contains(normalizedPhrase) else { continue }

            let distance = nearestEditDistance(
                source: candidate,
                target: normalizedPhrase,
                maxDistance: 2
            )

            guard let distance, distance > 0 else { continue }
            if bestMatch == nil || distance < bestMatch!.distance {
                bestMatch = (phrase, distance)
            }
        }

        guard let bestMatch else { return (0, "") }

        switch bestMatch.distance {
        case 1:
            return (2, "候选接近常见中文短语但局部错写：\(bestMatch.phrase)")
        case 2:
            return (1, "候选与常见中文短语接近但自然度不足：\(bestMatch.phrase)")
        default:
            return (0, "")
        }
    }

    private func chineseConfusableVariantPenalty(
        originalText: String,
        candidateText: String
    ) -> (penalty: Int, reason: String) {
        let candidate = normalizedChinese(candidateText)
        let original = normalizedChinese(originalText)
        guard !candidate.isEmpty else { return (0, "") }

        for variant in chineseConfusableVariants {
            guard candidate.contains(variant.variant) else { continue }
            if original.contains(variant.expected) || chineseReferencePhrases.contains(where: { normalizedChinese($0).contains(variant.expected) }) {
                return (
                    variant.penalty,
                    "候选包含接近目标短语的较差变体：\(variant.variant)"
                )
            }
        }

        return (0, "")
    }

    private func traditionalVariantPenalty(
        originalText: String,
        candidateText: String
    ) -> (penalty: Int, reason: String) {
        let originalTraditionalCount = traditionalCharacterCount(in: originalText)
        let candidateTraditionalCount = traditionalCharacterCount(in: candidateText)

        guard candidateTraditionalCount >= configuration.traditionalVariantPenaltyThreshold,
              originalTraditionalCount == 0 else {
            return (0, "")
        }

        return (
            candidateTraditionalCount >= 3 ? 2 : 1,
            "候选混入较多繁体/异体字，降低中文一致性"
        )
    }

    private func completeChinesePhraseRetentionReward(
        originalText: String,
        candidateText: String
    ) -> (reward: Int, reason: String) {
        let candidate = normalizedChinese(candidateText)
        let foldedCandidate = foldedChinese(candidate)
        guard candidate.count >= 5, !foldedCandidate.isEmpty else { return (0, "") }

        let original = normalizedChinese(originalText)
        let references = Array(Set(chineseReferencePhrases + candidateReferencePhrases(from: originalText)))
            .map(normalizedChinese)
            .filter { !$0.isEmpty }

        for reference in references {
            let foldedReference = foldedChinese(reference)
            guard foldedReference.count >= 5,
                  foldedCandidate.contains(foldedReference),
                  !foldedChinese(original).contains(foldedReference) else {
                continue
            }

            return (
                1,
                "候选保留了更完整的中文核心短语：\(reference)"
            )
        }

        return (0, "")
    }

    private func weakenedChineseCandidatePenalty(
        originalText: String,
        candidateText: String
    ) -> (penalty: Int, reason: String) {
        let original = normalizedChinese(originalText)
        let candidate = normalizedChinese(candidateText)
        guard original.count >= 6, candidate.count >= 5, original != candidate else {
            return (0, "")
        }

        let references = Array(Set(chineseReferencePhrases + candidateReferencePhrases(from: originalText)))
            .map(normalizedChinese)
            .filter { !$0.isEmpty }

        for reference in references {
            guard reference.count >= 6 else { continue }

            let sharedSuffixLength = longestCommonSuffixLength(candidate, reference)
            guard sharedSuffixLength >= 4 else { continue }

            let referencePrefixLength = reference.count - sharedSuffixLength
            let candidatePrefixLength = candidate.count - sharedSuffixLength
            guard (1...3).contains(referencePrefixLength),
                  (1...3).contains(candidatePrefixLength) else {
                continue
            }

            let referencePrefix = String(reference.prefix(referencePrefixLength))
            let candidatePrefix = String(candidate.prefix(candidatePrefixLength))
            guard weakChinesePrefixes.contains(candidatePrefix),
                  !weakChinesePrefixes.contains(referencePrefix),
                  referencePrefix != candidatePrefix else {
                continue
            }

            let penalty = candidatePrefixLength == 1 && referencePrefixLength >= 2 && sharedSuffixLength >= 5 ? 3 : 2
            return (
                penalty,
                "候选丢失了关键中文成分，退化为较弱表达：\(reference)"
            )
        }

        return (0, "")
    }

    private func candidateReferencePhrases(from text: String) -> [String] {
        let normalized = normalizedChinese(text)
        guard normalized.count >= 4 else { return [] }

        var phrases: [String] = [normalized]
        if normalized.count > 8 {
            let start = normalized.index(normalized.startIndex, offsetBy: max(0, normalized.count - 8))
            phrases.append(String(normalized[start...]))
        }
        return Array(Set(phrases))
    }

    private func nearestEditDistance(source: String, target: String, maxDistance: Int) -> Int? {
        let sourceChars = Array(source)
        let targetChars = Array(target)
        guard !targetChars.isEmpty else { return nil }

        let candidateLengths = Array(Set([
            targetChars.count - 1,
            targetChars.count,
            targetChars.count + 1
        ].filter { $0 > 0 && $0 <= sourceChars.count }))

        var best: Int?
        for length in candidateLengths {
            if sourceChars.count == length {
                let distance = editDistance(sourceChars, targetChars)
                if distance <= maxDistance {
                    best = min(best ?? distance, distance)
                }
                continue
            }

            for start in 0...(sourceChars.count - length) {
                let window = Array(sourceChars[start..<(start + length)])
                let distance = editDistance(window, targetChars)
                if distance <= maxDistance {
                    best = min(best ?? distance, distance)
                }
            }
        }
        return best
    }

    private func editDistance(_ lhs: [Character], _ rhs: [Character]) -> Int {
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

    private func normalizedChinese(_ text: String) -> String {
        String(text.filter(isCJK))
    }

    private func foldedChinese(_ text: String) -> String {
        let mapping: [Character: Character] = [
            "轉": "转",
            "寫": "写",
            "專": "专",
            "應": "应",
            "經": "经",
            "屬": "属",
            "傳": "传",
            "體": "体",
        ]

        return String(text.map { mapping[$0] ?? $0 })
    }

    private func longestCommonSuffixLength(_ lhs: String, _ rhs: String) -> Int {
        let lhsCharacters = Array(lhs)
        let rhsCharacters = Array(rhs)
        var matchedLength = 0

        while matchedLength < lhsCharacters.count, matchedLength < rhsCharacters.count {
            let left = lhsCharacters[lhsCharacters.count - 1 - matchedLength]
            let right = rhsCharacters[rhsCharacters.count - 1 - matchedLength]
            guard left == right else { break }
            matchedLength += 1
        }

        return matchedLength
    }

    private func traditionalCharacterCount(in text: String) -> Int {
        let traditionalCharacters = Set("轉寫專應經屬傳體")
        return text.reduce(into: 0) { count, character in
            if traditionalCharacters.contains(character) {
                count += 1
            }
        }
    }

    private func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3400...0x4DBF).contains(scalar.value)
        }
    }
}
