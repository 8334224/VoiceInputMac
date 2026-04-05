import Foundation

struct SuspicionDetector {
    private struct State {
        var lastSnapshot: RecognitionResultSnapshot?
    }

    private struct FunctionWordConfusionRule {
        let suspiciousPhrase: String
        let expectedPhrase: String
        let severity: Int
    }

    private struct LowFluencyPattern {
        let phrase: String
        let detail: String
        let severity: Int
    }

    private struct ContentWordConfusionRule {
        let suspiciousPhrase: String
        let expectedPhrase: String
        let contextKeywords: [String]
        let severity: Int
    }

    private struct SplitPhraseRule {
        let left: String
        let right: String
        let expectedPhrase: String
        let severity: Int
    }

    private struct HotwordSplitPhraseRule {
        let left: String
        let right: String
        let expectedPhrase: String
        let severity: Int
    }

    private struct SuffixSplitRule {
        let leadingToken: String
        let suffix: String
        let expectedPhrase: String
        let severity: Int
    }

    private struct SegmentContext {
        let previousText: String
        let currentText: String
        let nextText: String

        var previousCurrentWindow: String {
            previousText + currentText
        }

        var currentNextWindow: String {
            currentText + nextText
        }

        var nearbyWindow: String {
            previousText + currentText + nextText
        }
    }

    private let correctionPipeline: TextCorrectionPipeline
    private var state = State()
    private let asciiPriorityPhrases: [String]
    private let uppercasePriorityPhrases: [String]
    private let functionWordConfusionRules: [FunctionWordConfusionRule]
    private let lowFluencyPatterns: [LowFluencyPattern]
    private let contentWordConfusionRules: [ContentWordConfusionRule]
    private let splitPhraseRules: [SplitPhraseRule]
    private let hotwordSplitPhraseRules: [HotwordSplitPhraseRule]
    private let suffixSplitRules: [SuffixSplitRule]
    private let knownTechHotwords: [String]

    init(correctionPipeline: TextCorrectionPipeline) {
        self.correctionPipeline = correctionPipeline
        self.asciiPriorityPhrases = correctionPipeline.customPhrases.filter {
            $0.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil
        }
        self.uppercasePriorityPhrases = asciiPriorityPhrases.filter {
            $0 != $0.lowercased() && $0 != $0.uppercased()
                || $0 == $0.uppercased()
        }
        self.functionWordConfusionRules = [
            .init(suspiciousPhrase: "新不要", expectedPhrase: "先不要", severity: 2),
            .init(suspiciousPhrase: "心不要", expectedPhrase: "先不要", severity: 2),
            .init(suspiciousPhrase: "新不用", expectedPhrase: "先不用", severity: 2),
            .init(suspiciousPhrase: "心不用", expectedPhrase: "先不用", severity: 2),
            .init(suspiciousPhrase: "新可以", expectedPhrase: "先可以", severity: 1),
            .init(suspiciousPhrase: "心可以", expectedPhrase: "先可以", severity: 1),
            .init(suspiciousPhrase: "新应该", expectedPhrase: "先应该", severity: 1),
            .init(suspiciousPhrase: "心应该", expectedPhrase: "先应该", severity: 1),
            .init(suspiciousPhrase: "新看看", expectedPhrase: "先看看", severity: 1),
            .init(suspiciousPhrase: "心看看", expectedPhrase: "先看看", severity: 1)
        ]
        self.lowFluencyPatterns = [
            .init(phrase: "新不要", detail: "短窗口出现不自然搭配“新不要”", severity: 2),
            .init(phrase: "心不要", detail: "短窗口出现不自然搭配“心不要”", severity: 2),
            .init(phrase: "新不用", detail: "短窗口出现不自然搭配“新不用”", severity: 2),
            .init(phrase: "心不用", detail: "短窗口出现不自然搭配“心不用”", severity: 2),
            .init(phrase: "新可以", detail: "短窗口出现不自然搭配“新可以”", severity: 1),
            .init(phrase: "心可以", detail: "短窗口出现不自然搭配“心可以”", severity: 1),
            .init(phrase: "新应该", detail: "短窗口出现不自然搭配“新应该”", severity: 1),
            .init(phrase: "心应该", detail: "短窗口出现不自然搭配“心应该”", severity: 1)
        ]
        self.contentWordConfusionRules = [
            .init(
                suspiciousPhrase: "不属",
                expectedPhrase: "部署",
                contextKeywords: ["系统", "功能", "服务", "环境", "流程", "代码", "应用", "版本", "发布", "上线"],
                severity: 2
            ),
            .init(
                suspiciousPhrase: "上县",
                expectedPhrase: "上线",
                contextKeywords: ["功能", "服务", "版本", "发布", "流程", "环境", "接口"],
                severity: 2
            ),
            .init(
                suspiciousPhrase: "转成",
                expectedPhrase: "转写",
                contextKeywords: ["语音", "文字", "文本", "识别", "字幕"],
                severity: 1
            ),
            .init(
                suspiciousPhrase: "撰写",
                expectedPhrase: "转写",
                contextKeywords: ["语音", "文字", "文本", "识别", "实时"],
                severity: 1
            ),
            .init(
                suspiciousPhrase: "母型",
                expectedPhrase: "模型",
                contextKeywords: ["训练", "推理", "参数", "部署", "微调", "语言"],
                severity: 1
            ),
            .init(
                suspiciousPhrase: "木型",
                expectedPhrase: "模型",
                contextKeywords: ["训练", "推理", "参数", "部署", "微调", "语言"],
                severity: 1
            )
        ]
        self.splitPhraseRules = [
            .init(left: "转", right: "写成", expectedPhrase: "转写成", severity: 2),
            .init(left: "开", right: "放给", expectedPhrase: "开放给", severity: 1),
            .init(left: "部", right: "署系统", expectedPhrase: "部署系统", severity: 2),
            .init(left: "转", right: "写效果", expectedPhrase: "转写效果", severity: 2)
        ]
        self.hotwordSplitPhraseRules = [
            .init(left: "开", right: "放给", expectedPhrase: "开放给", severity: 2),
            .init(left: "部", right: "署系统", expectedPhrase: "部署系统", severity: 2),
            .init(left: "转", right: "写效果", expectedPhrase: "转写效果", severity: 2)
        ]
        self.suffixSplitRules = [
            .init(leadingToken: "转", suffix: "写成", expectedPhrase: "转写成", severity: 2),
            .init(leadingToken: "转", suffix: "写效果", expectedPhrase: "转写效果", severity: 2),
            .init(leadingToken: "开", suffix: "放给", expectedPhrase: "开放给", severity: 1),
            .init(leadingToken: "部", suffix: "署系统", expectedPhrase: "部署系统", severity: 2)
        ]
        let builtInHotwords = ["API", "SDK", "LLM", "WhisperKit", "OpenClaw", "OpenAI", "CPU", "GPU"]
        self.knownTechHotwords = Array(NSOrderedSet(array: asciiPriorityPhrases + builtInHotwords)) as? [String] ?? (asciiPriorityPhrases + builtInHotwords)
    }

    mutating func reset() {
        state = State()
    }

    mutating func evaluate(
        rawSnapshot: RecognitionResultSnapshot,
        processedSnapshot: RecognitionResultSnapshot
    ) -> RecognitionResultSnapshot {
        let previousSnapshot = state.lastSnapshot
        let finalRewriteMap = buildFinalRewriteMap(previous: previousSnapshot, current: processedSnapshot)

        let processedSegments = processedSnapshot.segments.enumerated().map { index, segment in
            let rawSegment = rawSnapshot.segments.first(where: { $0.id == segment.id })
            let context = makeContext(for: index, segments: processedSnapshot.segments)
            let flags = detectFlags(
                rawSegment: rawSegment,
                processedSegment: segment,
                context: context,
                finalRewriteFlag: finalRewriteMap[segment.id]
            )

            return TranscriptSegment(
                id: segment.id,
                text: segment.text,
                startTime: segment.startTime,
                endTime: segment.endTime,
                isFinal: segment.isFinal,
                source: segment.source,
                suspicionFlags: flags
            )
        }

        let updatedSnapshot = RecognitionResultSnapshot(
            rawText: processedSnapshot.rawText,
            displayText: processedSnapshot.displayText,
            segments: processedSegments,
            isFinal: processedSnapshot.isFinal,
            source: processedSnapshot.source
        )

        state.lastSnapshot = updatedSnapshot
        return updatedSnapshot
    }

    private func detectFlags(
        rawSegment: TranscriptSegment?,
        processedSegment: TranscriptSegment,
        context: SegmentContext,
        finalRewriteFlag: SuspicionFlag?
    ) -> [SuspicionFlag] {
        var flags: [SuspicionFlag] = []
        let rawText = rawSegment?.text ?? processedSegment.text
        let duration = max(0, processedSegment.endTime - processedSegment.startTime)
        let trimmedText = processedSegment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let correction = correctionPipeline.analyzeCorrections(for: rawText)

        if duration < 0.22 || trimmedText.count <= 1 {
            flags.append(
                SuspicionFlag(
                    code: "segment_fragment",
                    detail: "segment 时长过短或文本过碎，边界可能不稳定",
                    severity: 1
                )
            )
        }

        if looksLikeSplitAcronym(trimmedText) || hasAcronymCaseDrop(trimmedText) {
            flags.append(
                SuspicionFlag(
                    code: "english_abbreviation",
                    detail: "英文缩写形态异常，可能需要人工确认",
                    severity: 1
                )
            )
        }

        if hasNumberUnitAnomaly(trimmedText) {
            flags.append(
                SuspicionFlag(
                    code: "number_unit_format",
                    detail: "数字与单位格式异常，可能是首轮识别格式错误",
                    severity: 1
                )
            )
        }

        if correction.matchedRuleCount >= 2 || correction.removedSentenceFinalFiller {
            flags.append(
                SuspicionFlag(
                    code: "heavy_local_correction",
                    detail: "本地纠错命中过多，说明首轮识别质量不稳定",
                    severity: correction.matchedRuleCount >= 3 ? 2 : 1
                )
            )
        }

        if let hotwordFlag = detectHotwordMiss(rawText: rawText, correctedText: correction.correctedText) {
            flags.append(hotwordFlag)
        }

        if let functionWordFlag = detectFunctionWordConfusion(in: context) {
            flags.append(functionWordFlag)
        }

        if let hotwordContextFlag = detectHotwordContextAnomaly(in: context) {
            flags.append(hotwordContextFlag)
        }

        if let lowFluencyFlag = detectLowFluencyWindow(in: context) {
            flags.append(lowFluencyFlag)
        }

        if let contentWordFlag = detectContentWordConfusion(in: context) {
            flags.append(contentWordFlag)
        }

        if let splitPhraseFlag = detectSplitPhraseAnomaly(in: context) {
            flags.append(splitPhraseFlag)
        }

        if let hotwordSplitFlag = detectHotwordSplitPhraseAnomaly(in: context) {
            flags.append(hotwordSplitFlag)
        }

        if let suffixSplitFlag = detectSuffixSplitAnomaly(in: context) {
            flags.append(suffixSplitFlag)
        }

        if let finalRewriteFlag {
            flags.append(finalRewriteFlag)
        }

        return deduplicated(flags)
    }

    private func detectHotwordMiss(rawText: String, correctedText: String) -> SuspicionFlag? {
        let normalizedRaw = rawText.asciiNormalized
        let normalizedCorrected = correctedText.asciiNormalized

        for phrase in asciiPriorityPhrases {
            let normalizedPhrase = phrase.asciiNormalized
            if normalizedPhrase.isEmpty { continue }

            if normalizedCorrected.contains(normalizedPhrase) && !normalizedRaw.contains(normalizedPhrase) {
                return SuspicionFlag(
                    code: "hotword_miss",
                    detail: "热词未被首轮直接命中，依赖后处理才恢复",
                    severity: 2
                )
            }
        }

        return nil
    }

    private func detectContentWordConfusion(in context: SegmentContext) -> SuspicionFlag? {
        let windows = [context.previousCurrentWindow, context.currentText, context.currentNextWindow, context.nearbyWindow]

        for rule in contentWordConfusionRules {
            let hasSuspiciousPhrase = windows.contains { $0.contains(rule.suspiciousPhrase) }
            guard hasSuspiciousPhrase else { continue }

            let hasContextKeyword = rule.contextKeywords.contains { keyword in
                context.nearbyWindow.contains(keyword)
            }
            guard hasContextKeyword else { continue }

            return SuspicionFlag(
                code: "cn_content_word_confusion",
                detail: "中文实词疑似近音误识别，可能将“\(rule.expectedPhrase)”识别成“\(rule.suspiciousPhrase)”",
                severity: rule.severity
            )
        }

        return nil
    }

    private func detectSplitPhraseAnomaly(in context: SegmentContext) -> SuspicionFlag? {
        for rule in splitPhraseRules {
            if matchesSplit(rule.left, rule.right, in: context) {
                return SuspicionFlag(
                    code: "cn_phrase_split_anomaly",
                    detail: "固定短语拆分异常，疑似将“\(rule.expectedPhrase)”识别成“\(rule.left)” + “\(rule.right)”",
                    severity: rule.severity
                )
            }
        }

        return nil
    }

    private func detectHotwordSplitPhraseAnomaly(in context: SegmentContext) -> SuspicionFlag? {
        let normalizedWindow = context.nearbyWindow.asciiNormalized
        let hasHotwordNearby = knownTechHotwords.contains { hotword in
            let normalizedHotword = hotword.asciiNormalized
            return !normalizedHotword.isEmpty && normalizedWindow.contains(normalizedHotword)
        }
        guard hasHotwordNearby else { return nil }

        for rule in hotwordSplitPhraseRules {
            if matchesSplit(rule.left, rule.right, in: context) {
                return SuspicionFlag(
                    code: "hotword_phrase_split_anomaly",
                    detail: "热词附近短语拆分异常，疑似将“\(rule.expectedPhrase)”识别成“\(rule.left)” + “\(rule.right)”",
                    severity: rule.severity
                )
            }
        }

        return nil
    }

    private func detectSuffixSplitAnomaly(in context: SegmentContext) -> SuspicionFlag? {
        for rule in suffixSplitRules {
            if matchesSplit(rule.leadingToken, rule.suffix, in: context) {
                return SuspicionFlag(
                    code: "cn_suffix_split_anomaly",
                    detail: "单字与常见后缀拼接异常，疑似将“\(rule.expectedPhrase)”拆成“\(rule.leadingToken)” + “\(rule.suffix)”",
                    severity: rule.severity
                )
            }
        }

        return nil
    }

    private func detectFunctionWordConfusion(in context: SegmentContext) -> SuspicionFlag? {
        let windows = [context.previousCurrentWindow, context.currentText, context.currentNextWindow, context.nearbyWindow]

        for rule in functionWordConfusionRules {
            if windows.contains(where: { $0.contains(rule.suspiciousPhrase) }) {
                return SuspicionFlag(
                    code: "cn_function_word_confusion",
                    detail: "中文高频小词搭配异常，疑似将“\(rule.expectedPhrase)”识别成“\(rule.suspiciousPhrase)”",
                    severity: rule.severity
                )
            }
        }

        return nil
    }

    private func detectHotwordContextAnomaly(in context: SegmentContext) -> SuspicionFlag? {
        let normalizedWindow = context.nearbyWindow.asciiNormalized
        guard knownTechHotwords.contains(where: {
            let normalizedHotword = $0.asciiNormalized
            return !normalizedHotword.isEmpty && normalizedWindow.contains(normalizedHotword)
        }) else {
            return nil
        }

        if let rule = functionWordConfusionRules.first(where: { context.nearbyWindow.contains($0.suspiciousPhrase) }) {
            return SuspicionFlag(
                code: "hotword_context_anomaly",
                detail: "热词附近出现不自然中文搭配“\(rule.suspiciousPhrase)”，建议局部重识别",
                severity: 2
            )
        }

        if let pattern = lowFluencyPatterns.first(where: { context.nearbyWindow.contains($0.phrase) }) {
            return SuspicionFlag(
                code: "hotword_context_anomaly",
                detail: "热词附近出现低自然度短语“\(pattern.phrase)”，建议局部重识别",
                severity: max(1, pattern.severity)
            )
        }

        return nil
    }

    private func detectLowFluencyWindow(in context: SegmentContext) -> SuspicionFlag? {
        let windows = [context.previousCurrentWindow, context.currentText, context.currentNextWindow]

        for pattern in lowFluencyPatterns {
            if windows.contains(where: { window in
                let count = window.count
                return count >= 2 && count <= 5 && window.contains(pattern.phrase)
            }) {
                return SuspicionFlag(
                    code: "short_window_low_fluency",
                    detail: pattern.detail,
                    severity: pattern.severity
                )
            }
        }

        return nil
    }

    private func buildFinalRewriteMap(
        previous: RecognitionResultSnapshot?,
        current: RecognitionResultSnapshot
    ) -> [String: SuspicionFlag] {
        guard current.isFinal, let previous, !previous.isFinal else { return [:] }

        var flags: [String: SuspicionFlag] = [:]

        for currentSegment in current.segments {
            guard let previousSegment = previous.segments.first(where: {
                timeRangesOverlap(
                    lhsStart: $0.startTime,
                    lhsEnd: $0.endTime,
                    rhsStart: currentSegment.startTime,
                    rhsEnd: currentSegment.endTime
                )
            }) else {
                continue
            }

            let similarity = textSimilarity(previousSegment.text, currentSegment.text)
            let lengthDelta = abs(previousSegment.text.count - currentSegment.text.count)

            if similarity < 0.45 || lengthDelta >= 5 {
                flags[currentSegment.id] = SuspicionFlag(
                    code: "partial_final_jump",
                    detail: "partial 到 final 差异较大，建议优先人工确认",
                    severity: 2
                )
            }
        }

        return flags
    }

    private func makeContext(
        for index: Int,
        segments: [TranscriptSegment]
    ) -> SegmentContext {
        SegmentContext(
            previousText: index > 0 ? segments[index - 1].text : "",
            currentText: segments[index].text,
            nextText: index + 1 < segments.count ? segments[index + 1].text : ""
        )
    }

    private func matchesSplit(
        _ left: String,
        _ right: String,
        in context: SegmentContext
    ) -> Bool {
        (context.previousText == left && context.currentText == right)
            || (context.currentText == left && context.nextText == right)
    }

    private func looksLikeSplitAcronym(_ text: String) -> Bool {
        text.range(
            of: #"\b(?:[A-Za-z]\s+){2,}[A-Za-z]\b"#,
            options: .regularExpression
        ) != nil
    }

    private func hasAcronymCaseDrop(_ text: String) -> Bool {
        let tokens = text.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).map(String.init)
        return tokens.contains { token in
            let normalized = token.asciiNormalized
            guard normalized.count >= 2, normalized.count <= 5 else { return false }
            return uppercasePriorityPhrases.contains(where: { $0.asciiNormalized == normalized && $0 != token })
        }
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

    private func timeRangesOverlap(
        lhsStart: TimeInterval,
        lhsEnd: TimeInterval,
        rhsStart: TimeInterval,
        rhsEnd: TimeInterval
    ) -> Bool {
        max(lhsStart, rhsStart) <= min(lhsEnd, rhsEnd)
    }

    private func textSimilarity(_ lhs: String, _ rhs: String) -> Double {
        let distance = levenshteinDistance(lhs, rhs)
        let base = max(lhs.count, rhs.count)
        guard base > 0 else { return 1 }
        return 1 - Double(distance) / Double(base)
    }

    private func deduplicated(_ flags: [SuspicionFlag]) -> [SuspicionFlag] {
        var seen: Set<String> = []
        return flags.filter { flag in
            let key = "\(flag.code)|\(flag.detail)|\(flag.severity)"
            return seen.insert(key).inserted
        }
    }

}
