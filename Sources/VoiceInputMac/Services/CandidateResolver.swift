import Foundation

struct CandidateComparisonGroup: Identifiable, Sendable {
    let id: String
    let segmentIDs: [String]
    let originalText: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let triggerFlags: [SuspicionFlag]
    let candidates: [ReRecognitionCandidateRecord]
}

struct CandidateResolution: Identifiable, Sendable {
    let id: String
    let group: CandidateComparisonGroup
    let sortedCandidates: [ReRecognitionCandidateRecord]
    let bestCandidate: ReRecognitionCandidateRecord?
    let selectionReasons: [String]
    let readyForReview: Bool
}

struct RankedStat: Sendable {
    let label: String
    let count: Int
}

struct BackendPriorityEntry: Sendable {
    let backend: String
    let score: Int
    let matchedTriggerFlags: [String]
    let reasons: [String]
}

enum ReRecognitionOrderMode: String, Sendable {
    case fixed
    case session
    case blended
}

enum ReRecognitionOrderStrategySource: String, Sendable {
    case fixedDefault = "fixed/default"
    case sessionDriven = "session-driven"
    case historicalDriven = "historical-driven"
    case blendedDriven = "blended-driven"
}

struct BackendOrderingDecision: Sendable {
    let mode: ReRecognitionOrderMode
    let source: ReRecognitionOrderStrategySource
    let rankedBackends: [BackendPriorityEntry]
}

struct ReRecognitionSessionSummary: Sendable {
    enum HintSource: String, Sendable {
        case session
        case historical
        case blended
    }

    enum HintConfidence: String, Sendable {
        case low
        case medium
        case high
    }

    struct BackendSummary: Sendable {
        let backend: String
        let candidateCount: Int
        let acceptedCount: Int
        let rejectedCount: Int
        let readyForReviewCount: Int
    }

    struct TriggerFlagBackendSummary: Sendable {
        let triggerFlag: String
        let backend: String
        let candidateCount: Int
        let acceptedCount: Int
        let rejectedCount: Int
        let readyForReviewCount: Int
    }

    struct BackendPreferenceHint: Sendable {
        let triggerFlag: String
        let preferredBackend: String
        let source: HintSource
        let score: Int
        let reasons: [String]
        let confidence: HintConfidence
        let sampleCount: Int
        let meetsSampleThreshold: Bool
        let weighting: String
    }

    struct HintEffectivenessSummary: Sendable {
        let groupsWithHints: Int
        let recommendedBecameBestCount: Int
        let recommendedReadyForReviewCount: Int
        let hintMissedCount: Int
    }

    struct BackendCandidateObservation: Sendable {
        let backend: String
        let candidateText: String
        let score: Int
        let shouldPromoteCandidate: Bool
        let replacementMode: String
    }

    struct BackendComparisonSummary: Sendable {
        let planID: String
        let segmentIDs: [String]
        let originalText: String
        let startTime: TimeInterval
        let endTime: TimeInterval
        let triggerFlags: [String]
        let candidates: [BackendCandidateObservation]
        let bestCandidateBackend: String?
        let bestCandidateText: String?
        let hasTextDivergence: Bool
        let hasScoreDivergence: Bool
        let divergenceReasons: [String]
        let suitableForOrderComparison: Bool
    }

    struct BackendDivergenceSummary: Sendable {
        let comparedPlanCount: Int
        let multiBackendPlanCount: Int
        let textDivergenceCount: Int
        let scoreDivergenceCount: Int
        let suitableForOrderComparisonCount: Int
        let suitableForOrderComparisonRatio: Double
    }

    struct BackendAttemptSummary: Sendable {
        let planID: String
        let segmentIDs: [String]
        let backend: String
        let status: String
        let failureReason: String?
        let attemptedAt: Date
        let completedAt: Date?
    }

    struct OrderEffectivenessStats: Sendable {
        let planCount: Int
        let recommendedBecameBestCount: Int
        let recommendedBecameBestRatio: Double
        let recommendedReadyForReviewCount: Int
        let recommendedReadyForReviewRatio: Double
        let firstTriedBecameBestCount: Int
        let firstTriedBecameBestRatio: Double
        let bestFromNonFirstBackendCount: Int
        let bestFromNonFirstBackendRatio: Double
    }

    struct OrderStrategySourceSummary: Sendable {
        let source: ReRecognitionOrderStrategySource
        let stats: OrderEffectivenessStats
    }

    struct OrderModeSummary: Sendable {
        let mode: ReRecognitionOrderMode
        let stats: OrderEffectivenessStats
    }

    struct OrderEffectivenessSummary: Sendable {
        let overall: OrderEffectivenessStats
        let byStrategySource: [OrderStrategySourceSummary]
        let byMode: [OrderModeSummary]
    }

    let sessionID: UUID?
    let currentOrderMode: ReRecognitionOrderMode
    let planCount: Int
    let actualReRecognitionCount: Int
    let acceptedCount: Int
    let rejectedCount: Int
    let commonTriggerFlags: [RankedStat]
    let commonDecisionReasons: [RankedStat]
    let backendSummaries: [BackendSummary]
    let triggerFlagBackendSummaries: [TriggerFlagBackendSummary]
    let sessionBackendPreferenceHints: [BackendPreferenceHint]
    let historicalBackendPreferenceHints: [BackendPreferenceHint]
    let blendedBackendPreferenceHints: [BackendPreferenceHint]
    let hintEffectiveness: HintEffectivenessSummary
    let orderEffectiveness: OrderEffectivenessSummary
    let backendComparisons: [BackendComparisonSummary]
    let backendDivergence: BackendDivergenceSummary
    let backendAttempts: [BackendAttemptSummary]
}

private struct HistoricalScoreDetails: Sendable {
    let score: Int
    let sampleCount: Int
    let meetsSampleThreshold: Bool
    let weighting: String
    let usedRecencyWeighting: Bool
}

struct CandidateResolver {
    struct Configuration: Sendable {
        let minimumReviewScore: Int
        let minimumLeadScore: Int
        let topStatsLimit: Int
        let historicalMinimumSampleCount: Int
        let historicalRecentEventLimit: Int

        static let `default` = Configuration(
            minimumReviewScore: 2,
            minimumLeadScore: 1,
            topStatsLimit: 5,
            historicalMinimumSampleCount: 3,
            historicalRecentEventLimit: 8
        )
    }

    private let configuration: Configuration

    init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    func resolve(group: CandidateComparisonGroup) -> CandidateResolution {
        let sorted = group.candidates.sorted { lhs, rhs in
            if lhs.shouldPromoteCandidate != rhs.shouldPromoteCandidate {
                return lhs.shouldPromoteCandidate && !rhs.shouldPromoteCandidate
            }
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            if lhs.candidateText.count != rhs.candidateText.count {
                return lhs.candidateText.count > rhs.candidateText.count
            }
            return lhs.createdAt < rhs.createdAt
        }

        guard let best = sorted.first else {
            return CandidateResolution(
                id: group.id,
                group: group,
                sortedCandidates: [],
                bestCandidate: nil,
                selectionReasons: ["当前分组没有候选记录"],
                readyForReview: false
            )
        }

        var reasons: [String] = []
        let runnerUp = sorted.dropFirst().first

        if best.shouldPromoteCandidate {
            reasons.append("最佳候选已通过 evaluator")
        } else {
            reasons.append("当前最高分候选仍未通过 evaluator")
        }

        reasons.append("当前分组最高分为 \(best.score)")

        if let runnerUp {
            let lead = best.score - runnerUp.score
            reasons.append("相对次优候选领先 \(lead) 分")
        } else {
            reasons.append("当前分组只有一个候选结果")
        }

        let readyForReview: Bool
        if let runnerUp {
            readyForReview = best.shouldPromoteCandidate
                && best.score >= configuration.minimumReviewScore
                && (best.score - runnerUp.score) >= configuration.minimumLeadScore
        } else {
            readyForReview = best.shouldPromoteCandidate
                && best.score >= configuration.minimumReviewScore
        }

        reasons.append(readyForReview ? "已达到进入后续确认层的门槛" : "尚未达到进入后续确认层的门槛")

        return CandidateResolution(
            id: group.id,
            group: group,
            sortedCandidates: sorted,
            bestCandidate: best,
            selectionReasons: reasons,
            readyForReview: readyForReview
        )
    }

    func summarize(
        sessionID: UUID?,
        currentOrderMode: ReRecognitionOrderMode,
        plans: [ReRecognitionPlan],
        records: [ReRecognitionCandidateRecord],
        resolutions: [CandidateResolution],
        executionTraces: [ReRecognitionExecutionTrace],
        historicalStats: [HistoricalBackendPreferenceStat]
    ) -> ReRecognitionSessionSummary {
        let triggerStats = countStats(records.flatMap { $0.triggerFlags.map(\.code) })
        let reasonStats = countStats(records.flatMap(\.decisionReasons))
        let backendStats = summarizeBackends(records: records, resolutions: resolutions)
        let triggerBackendStats = summarizeTriggerFlagBackends(records: records, resolutions: resolutions)
        let sessionHints = buildSessionBackendPreferenceHints(from: triggerBackendStats)
        let historicalHints = buildHistoricalBackendPreferenceHints(from: historicalStats)
        let blendedHints = buildBlendedBackendPreferenceHints(
            sessionHints: sessionHints,
            historicalHints: historicalHints
        )
        let hintEffectiveness = summarizeHintEffectiveness(resolutions: resolutions, hints: blendedHints)
        let backendComparisons = summarizeBackendComparisons(resolutions: resolutions)
        let backendDivergence = summarizeBackendDivergence(comparisons: backendComparisons)
        let backendAttempts = summarizeBackendAttempts(traces: executionTraces)
        let overallOrderEffectiveness = summarizeOrderStrategyEffectiveness(
            traces: executionTraces,
            resolutions: resolutions
        )
        let orderStrategySourceSummaries = summarizeOrderStrategiesBySource(
            traces: executionTraces,
            resolutions: resolutions
        )
        let orderModeSummaries = summarizeOrderStrategiesByMode(
            traces: executionTraces,
            resolutions: resolutions
        )

        return ReRecognitionSessionSummary(
            sessionID: sessionID,
            currentOrderMode: currentOrderMode,
            planCount: plans.count,
            actualReRecognitionCount: records.count,
            acceptedCount: records.filter(\.shouldPromoteCandidate).count,
            rejectedCount: records.filter { !$0.shouldPromoteCandidate }.count,
            commonTriggerFlags: Array(triggerStats.prefix(configuration.topStatsLimit)),
            commonDecisionReasons: Array(reasonStats.prefix(configuration.topStatsLimit)),
            backendSummaries: backendStats,
            triggerFlagBackendSummaries: triggerBackendStats,
            sessionBackendPreferenceHints: sessionHints,
            historicalBackendPreferenceHints: historicalHints,
            blendedBackendPreferenceHints: blendedHints,
            hintEffectiveness: hintEffectiveness,
            orderEffectiveness: ReRecognitionSessionSummary.OrderEffectivenessSummary(
                overall: overallOrderEffectiveness,
                byStrategySource: orderStrategySourceSummaries,
                byMode: orderModeSummaries
            ),
            backendComparisons: backendComparisons,
            backendDivergence: backendDivergence,
            backendAttempts: backendAttempts
        )
    }

    func makeBackendOrderingDecision(
        enabledBackends: [ReRecognitionBackendOption],
        triggerFlags: [SuspicionFlag],
        mode: ReRecognitionOrderMode,
        sessionHints: [ReRecognitionSessionSummary.BackendPreferenceHint],
        historicalHints: [ReRecognitionSessionSummary.BackendPreferenceHint],
        blendedHints: [ReRecognitionSessionSummary.BackendPreferenceHint]
    ) -> BackendOrderingDecision {
        switch mode {
        case .fixed:
            return BackendOrderingDecision(
                mode: mode,
                source: .fixedDefault,
                rankedBackends: fixedOrderEntries(for: enabledBackends)
            )
        case .session:
            let ranked = rankBackends(
                enabledBackends: enabledBackends,
                triggerFlags: triggerFlags,
                sessionHints: sessionHints,
                historicalHints: [],
                blendedHints: []
            )
            let source: ReRecognitionOrderStrategySource = (ranked.first?.score ?? 0) > 0 ? .sessionDriven : .fixedDefault
            return BackendOrderingDecision(mode: mode, source: source, rankedBackends: ranked)
        case .blended:
            let ranked = rankBackends(
                enabledBackends: enabledBackends,
                triggerFlags: triggerFlags,
                sessionHints: sessionHints,
                historicalHints: historicalHints,
                blendedHints: blendedHints
            )
            let source = classifyBlendedOrderingSource(
                rankedBackends: ranked,
                triggerFlags: triggerFlags,
                sessionHints: sessionHints,
                historicalHints: historicalHints
            )
            return BackendOrderingDecision(mode: mode, source: source, rankedBackends: ranked)
        }
    }

    private func rankBackends(
        enabledBackends: [ReRecognitionBackendOption],
        triggerFlags: [SuspicionFlag],
        sessionHints: [ReRecognitionSessionSummary.BackendPreferenceHint],
        historicalHints: [ReRecognitionSessionSummary.BackendPreferenceHint],
        blendedHints: [ReRecognitionSessionSummary.BackendPreferenceHint]
    ) -> [BackendPriorityEntry] {
        let triggerCodes = Array(Set(triggerFlags.map(\.code))).sorted()
        let sessionHintMap = Dictionary(uniqueKeysWithValues: sessionHints.map { ($0.triggerFlag, $0) })
        let historicalHintMap = Dictionary(uniqueKeysWithValues: historicalHints.map { ($0.triggerFlag, $0) })
        let blendedHintMap = Dictionary(uniqueKeysWithValues: blendedHints.map { ($0.triggerFlag, $0) })

        return enabledBackends.map { option in
            var score = 0
            var matchedFlags: [String] = []
            var reasons: [String] = []

            for code in triggerCodes {
                if let hint = historicalHintMap[code],
                   hint.preferredBackend == option.rawValue {
                    let contribution = rankingContribution(for: hint)
                    if contribution > 0 {
                        score += contribution
                        matchedFlags.append(code)
                        reasons.append("\(code):historical(\(hint.confidence.rawValue),samples:\(hint.sampleCount),threshold:\(hint.meetsSampleThreshold))")
                    } else {
                        reasons.append("\(code):historical(ignored-small-sample)")
                    }
                }

                if let hint = sessionHintMap[code],
                   hint.preferredBackend == option.rawValue {
                    let contribution = rankingContribution(for: hint)
                    score += contribution
                    matchedFlags.append(code)
                    reasons.append("\(code):session(\(hint.confidence.rawValue))")
                }

                if let hint = blendedHintMap[code],
                   hint.preferredBackend == option.rawValue {
                    let contribution = rankingContribution(for: hint)
                    score += contribution
                    matchedFlags.append(code)
                    reasons.append("\(code):blended(\(hint.confidence.rawValue))")
                }
            }

            if matchedFlags.isEmpty {
                reasons.append("无命中 hint")
            }

            return BackendPriorityEntry(
                backend: option.rawValue,
                score: score,
                matchedTriggerFlags: Array(Set(matchedFlags)).sorted(),
                reasons: reasons
            )
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.backend < rhs.backend
            }
            return lhs.score > rhs.score
        }
    }

    private func fixedOrderEntries(
        for enabledBackends: [ReRecognitionBackendOption]
    ) -> [BackendPriorityEntry] {
        enabledBackends.enumerated().map { index, option in
            BackendPriorityEntry(
                backend: option.rawValue,
                score: max(0, enabledBackends.count - index),
                matchedTriggerFlags: [],
                reasons: ["fixed-order-index:\(index)"]
            )
        }
    }

    private func countStats(_ labels: [String]) -> [RankedStat] {
        let counts = labels.reduce(into: [String: Int]()) { partialResult, label in
            partialResult[label, default: 0] += 1
        }

        return counts
            .map { RankedStat(label: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs.label < rhs.label
                }
                return lhs.count > rhs.count
            }
    }

    private func summarizeBackends(
        records: [ReRecognitionCandidateRecord],
        resolutions: [CandidateResolution]
    ) -> [ReRecognitionSessionSummary.BackendSummary] {
        let readyCounts = resolutions.reduce(into: [String: Int]()) { partialResult, resolution in
            guard resolution.readyForReview, let backend = resolution.bestCandidate?.backend else { return }
            partialResult[backend, default: 0] += 1
        }

        let grouped = Dictionary(grouping: records, by: \.backend)
        return grouped.map { backend, records in
            ReRecognitionSessionSummary.BackendSummary(
                backend: backend,
                candidateCount: records.count,
                acceptedCount: records.filter(\.shouldPromoteCandidate).count,
                rejectedCount: records.filter { !$0.shouldPromoteCandidate }.count,
                readyForReviewCount: readyCounts[backend, default: 0]
            )
        }
        .sorted { lhs, rhs in
            if lhs.candidateCount == rhs.candidateCount {
                return lhs.backend < rhs.backend
            }
            return lhs.candidateCount > rhs.candidateCount
        }
    }

    private func summarizeTriggerFlagBackends(
        records: [ReRecognitionCandidateRecord],
        resolutions: [CandidateResolution]
    ) -> [ReRecognitionSessionSummary.TriggerFlagBackendSummary] {
        let readyPairs = resolutions.flatMap { resolution -> [(String, String)] in
            guard resolution.readyForReview,
                  let backend = resolution.bestCandidate?.backend else { return [] }

            let triggerFlags = Set(resolution.group.triggerFlags.map(\.code))
            guard !triggerFlags.isEmpty else { return [] }
            return triggerFlags.map { ($0, backend) }
        }

        let readyCounts = readyPairs.reduce(into: [String: Int]()) { partialResult, pair in
            partialResult["\(pair.0)|\(pair.1)", default: 0] += 1
        }

        var grouped: [String: [ReRecognitionCandidateRecord]] = [:]
        for record in records {
            let triggerCodes = Set(record.triggerFlags.map(\.code))
            for code in triggerCodes {
                grouped["\(code)|\(record.backend)", default: []].append(record)
            }
        }

        return grouped.map { key, records in
            let parts = key.components(separatedBy: "|")
            let triggerFlag = parts[0]
            let backend = parts[1]
            return ReRecognitionSessionSummary.TriggerFlagBackendSummary(
                triggerFlag: triggerFlag,
                backend: backend,
                candidateCount: records.count,
                acceptedCount: records.filter(\.shouldPromoteCandidate).count,
                rejectedCount: records.filter { !$0.shouldPromoteCandidate }.count,
                readyForReviewCount: readyCounts[key, default: 0]
            )
        }
        .sorted { lhs, rhs in
            if lhs.triggerFlag == rhs.triggerFlag {
                if lhs.candidateCount == rhs.candidateCount {
                    return lhs.backend < rhs.backend
                }
                return lhs.candidateCount > rhs.candidateCount
            }
            return lhs.triggerFlag < rhs.triggerFlag
        }
    }

    private func buildSessionBackendPreferenceHints(
        from summaries: [ReRecognitionSessionSummary.TriggerFlagBackendSummary]
    ) -> [ReRecognitionSessionSummary.BackendPreferenceHint] {
        let grouped = Dictionary(grouping: summaries, by: \.triggerFlag)

        return grouped.compactMap { triggerFlag, items in
            guard let best = items.max(by: isWeakerTriggerBackendSummary) else { return nil }

            var reasons: [String] = []
            reasons.append("accepted=\(best.acceptedCount), ready=\(best.readyForReviewCount), candidates=\(best.candidateCount)")

            if let runnerUp = items
                .filter({ $0.backend != best.backend })
                .max(by: isWeakerTriggerBackendSummary) {
                reasons.append(
                    "相对次优 backend 在 accepted 上领先 \(best.acceptedCount - runnerUp.acceptedCount)，ready 上领先 \(best.readyForReviewCount - runnerUp.readyForReviewCount)"
                )
            } else {
                reasons.append("当前会话该类可疑片段只有一个 backend 有统计数据")
            }

            let score = best.acceptedCount * 3 + best.readyForReviewCount * 4 + best.candidateCount - best.rejectedCount
            let confidence = sessionConfidence(for: best)

            return ReRecognitionSessionSummary.BackendPreferenceHint(
                triggerFlag: triggerFlag,
                preferredBackend: best.backend,
                source: .session,
                score: score,
                reasons: reasons,
                confidence: confidence,
                sampleCount: best.candidateCount,
                meetsSampleThreshold: best.candidateCount > 0,
                weighting: "session-current"
            )
        }
        .sorted { $0.triggerFlag < $1.triggerFlag }
    }

    private func buildHistoricalBackendPreferenceHints(
        from stats: [HistoricalBackendPreferenceStat]
    ) -> [ReRecognitionSessionSummary.BackendPreferenceHint] {
        let grouped = Dictionary(grouping: stats, by: \.triggerFlag)

        return grouped.compactMap { triggerFlag, items in
            let ranked = items.map { stat in
                (stat: stat, details: historicalScoreDetails(for: stat))
            }
            guard let best = ranked.max(by: isWeakerHistoricalEntry) else { return nil }

            let confidence = historicalConfidence(for: best.details)
            let reasons = [
                "candidate=\(best.stat.candidateCount)",
                "accepted=\(best.stat.acceptedCount)",
                "ready=\(best.stat.readyForReviewCount)",
                "missed=\(best.stat.hintMissedCount)",
                "recentSamples=\(best.details.sampleCount)",
                "recencyWeighted=\(best.details.usedRecencyWeighting)",
                "weighting=\(best.details.weighting)"
            ]

            return ReRecognitionSessionSummary.BackendPreferenceHint(
                triggerFlag: triggerFlag,
                preferredBackend: best.stat.backend,
                source: .historical,
                score: best.details.score,
                reasons: reasons,
                confidence: confidence,
                sampleCount: best.details.sampleCount,
                meetsSampleThreshold: best.details.meetsSampleThreshold,
                weighting: best.details.weighting
            )
        }
        .sorted { $0.triggerFlag < $1.triggerFlag }
    }

    private func buildBlendedBackendPreferenceHints(
        sessionHints: [ReRecognitionSessionSummary.BackendPreferenceHint],
        historicalHints: [ReRecognitionSessionSummary.BackendPreferenceHint]
    ) -> [ReRecognitionSessionSummary.BackendPreferenceHint] {
        let triggerFlags = Array(
            Set(sessionHints.map(\.triggerFlag) + historicalHints.map(\.triggerFlag))
        ).sorted()

        let sessionMap = Dictionary(uniqueKeysWithValues: sessionHints.map { ($0.triggerFlag, $0) })
        let historicalMap = Dictionary(uniqueKeysWithValues: historicalHints.map { ($0.triggerFlag, $0) })

        return triggerFlags.compactMap { triggerFlag in
            let sessionHint = sessionMap[triggerFlag]
            let historicalHint = historicalMap[triggerFlag]
            let candidates = Array(
                Set([sessionHint?.preferredBackend, historicalHint?.preferredBackend].compactMap { $0 })
            )
            guard !candidates.isEmpty else { return nil }

            let ranked = candidates.map { backend -> (String, Int, [String]) in
                var total = 0
                var reasons: [String] = []

                if let historicalHint, historicalHint.preferredBackend == backend {
                    if historicalHint.meetsSampleThreshold {
                        total += historicalHint.score
                        reasons.append("historical=\(historicalHint.score)")
                    } else {
                        reasons.append("historical-below-threshold")
                    }
                }
                if let sessionHint, sessionHint.preferredBackend == backend {
                    total += sessionHint.score * 2
                    reasons.append("session=\(sessionHint.score)x2")
                }

                return (backend, total, reasons)
            }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0 < rhs.0
                }
                return lhs.1 > rhs.1
            }

            guard let best = ranked.first else { return nil }
            let confidence = blendedConfidence(
                sessionHint: sessionHint,
                historicalHint: historicalHint,
                chosenBackend: best.0
            )
            let sampleCount = max(sessionHint?.sampleCount ?? 0, historicalHint?.sampleCount ?? 0)
            let meetsThreshold = (sessionHint != nil) || (historicalHint?.meetsSampleThreshold == true)

            return ReRecognitionSessionSummary.BackendPreferenceHint(
                triggerFlag: triggerFlag,
                preferredBackend: best.0,
                source: .blended,
                score: best.1,
                reasons: best.2,
                confidence: confidence,
                sampleCount: sampleCount,
                meetsSampleThreshold: meetsThreshold,
                weighting: "historical-base+session-correction"
            )
        }
    }

    private func summarizeHintEffectiveness(
        resolutions: [CandidateResolution],
        hints: [ReRecognitionSessionSummary.BackendPreferenceHint]
    ) -> ReRecognitionSessionSummary.HintEffectivenessSummary {
        var groupsWithHints = 0
        var recommendedBecameBestCount = 0
        var recommendedReadyForReviewCount = 0

        for resolution in resolutions {
            let backendNames = Array(Set(resolution.sortedCandidates.map(\.backend))).sorted()
            let ranked = rankBackendNames(
                backendNames: backendNames,
                triggerFlags: resolution.group.triggerFlags,
                hints: hints
            )

            guard let topRank = ranked.first, topRank.score > 0 else { continue }
            groupsWithHints += 1

            if resolution.bestCandidate?.backend == topRank.backend {
                recommendedBecameBestCount += 1
                if resolution.readyForReview {
                    recommendedReadyForReviewCount += 1
                }
            }
        }

        return ReRecognitionSessionSummary.HintEffectivenessSummary(
            groupsWithHints: groupsWithHints,
            recommendedBecameBestCount: recommendedBecameBestCount,
            recommendedReadyForReviewCount: recommendedReadyForReviewCount,
            hintMissedCount: max(0, groupsWithHints - recommendedBecameBestCount)
        )
    }

    private func summarizeOrderStrategyEffectiveness(
        traces: [ReRecognitionExecutionTrace],
        resolutions: [CandidateResolution]
    ) -> ReRecognitionSessionSummary.OrderEffectivenessStats {
        let joined = joinStrategyTraces(traces: traces, resolutions: resolutions)
        return makeOrderStrategyEffectiveness(from: joined)
    }

    private func summarizeOrderStrategiesBySource(
        traces: [ReRecognitionExecutionTrace],
        resolutions: [CandidateResolution]
    ) -> [ReRecognitionSessionSummary.OrderStrategySourceSummary] {
        let joined = joinStrategyTraces(traces: traces, resolutions: resolutions)
        let grouped = Dictionary(grouping: joined, by: \.trace.strategySource)

        return grouped.map { source, items in
            let summary = makeOrderStrategyEffectiveness(from: items)
            return ReRecognitionSessionSummary.OrderStrategySourceSummary(
                source: source,
                stats: summary
            )
        }
        .sorted { $0.source.rawValue < $1.source.rawValue }
    }

    private func summarizeOrderStrategiesByMode(
        traces: [ReRecognitionExecutionTrace],
        resolutions: [CandidateResolution]
    ) -> [ReRecognitionSessionSummary.OrderModeSummary] {
        let joined = joinStrategyTraces(traces: traces, resolutions: resolutions)
        let grouped = Dictionary(grouping: joined, by: \.trace.strategyMode)

        return grouped.map { mode, items in
            ReRecognitionSessionSummary.OrderModeSummary(
                mode: mode,
                stats: makeOrderStrategyEffectiveness(from: items)
            )
        }
        .sorted { $0.mode.rawValue < $1.mode.rawValue }
    }

    private func summarizeBackendComparisons(
        resolutions: [CandidateResolution]
    ) -> [ReRecognitionSessionSummary.BackendComparisonSummary] {
        resolutions.map { resolution in
            let candidates = resolution.sortedCandidates.map {
                ReRecognitionSessionSummary.BackendCandidateObservation(
                    backend: $0.backend,
                    candidateText: $0.candidateText,
                    score: $0.score,
                    shouldPromoteCandidate: $0.shouldPromoteCandidate,
                    replacementMode: $0.replacementMode.rawValue
                )
            }

            let normalizedTexts = Set(candidates.map { normalizeCandidateText($0.candidateText) })
            let distinctScores = Set(candidates.map(\.score))
            let hasTextDivergence = normalizedTexts.count > 1
            let hasScoreDivergence = distinctScores.count > 1

            var divergenceReasons: [String] = []
            if hasTextDivergence {
                divergenceReasons.append("backend 间 candidateText 不一致")
            }
            if hasScoreDivergence {
                divergenceReasons.append("backend 间 score 不一致")
            }
            if let best = resolution.bestCandidate {
                divergenceReasons.append("bestCandidate=\(best.backend)")
            } else {
                divergenceReasons.append("当前计划没有 bestCandidate")
            }

            let suitableForOrderComparison =
                candidates.count > 1 && (hasTextDivergence || hasScoreDivergence)

            return ReRecognitionSessionSummary.BackendComparisonSummary(
                planID: resolution.group.id,
                segmentIDs: resolution.group.segmentIDs,
                originalText: resolution.group.originalText,
                startTime: resolution.group.startTime,
                endTime: resolution.group.endTime,
                triggerFlags: resolution.group.triggerFlags.map(\.code),
                candidates: candidates,
                bestCandidateBackend: resolution.bestCandidate?.backend,
                bestCandidateText: resolution.bestCandidate?.candidateText,
                hasTextDivergence: hasTextDivergence,
                hasScoreDivergence: hasScoreDivergence,
                divergenceReasons: divergenceReasons,
                suitableForOrderComparison: suitableForOrderComparison
            )
        }
    }

    private func summarizeBackendDivergence(
        comparisons: [ReRecognitionSessionSummary.BackendComparisonSummary]
    ) -> ReRecognitionSessionSummary.BackendDivergenceSummary {
        let comparedPlanCount = comparisons.count
        let multiBackendPlanCount = comparisons.count { $0.candidates.count > 1 }
        let textDivergenceCount = comparisons.count { $0.hasTextDivergence }
        let scoreDivergenceCount = comparisons.count { $0.hasScoreDivergence }
        let suitableForOrderComparisonCount = comparisons.count { $0.suitableForOrderComparison }

        return ReRecognitionSessionSummary.BackendDivergenceSummary(
            comparedPlanCount: comparedPlanCount,
            multiBackendPlanCount: multiBackendPlanCount,
            textDivergenceCount: textDivergenceCount,
            scoreDivergenceCount: scoreDivergenceCount,
            suitableForOrderComparisonCount: suitableForOrderComparisonCount,
            suitableForOrderComparisonRatio: ratio(suitableForOrderComparisonCount, comparedPlanCount)
        )
    }

    private func summarizeBackendAttempts(
        traces: [ReRecognitionExecutionTrace]
    ) -> [ReRecognitionSessionSummary.BackendAttemptSummary] {
        traces
            .flatMap { trace in
                trace.backendAttemptResults.map { attempt in
                    ReRecognitionSessionSummary.BackendAttemptSummary(
                        planID: trace.planID,
                        segmentIDs: trace.segmentIDs,
                        backend: attempt.backend,
                        status: attempt.status.rawValue,
                        failureReason: attempt.failureReason,
                        attemptedAt: attempt.attemptedAt,
                        completedAt: attempt.completedAt
                    )
                }
            }
            .sorted { lhs, rhs in
                if lhs.attemptedAt == rhs.attemptedAt {
                    if lhs.planID == rhs.planID {
                        return lhs.backend < rhs.backend
                    }
                    return lhs.planID < rhs.planID
                }
                return lhs.attemptedAt < rhs.attemptedAt
            }
    }

    private func joinStrategyTraces(
        traces: [ReRecognitionExecutionTrace],
        resolutions: [CandidateResolution]
    ) -> [(trace: ReRecognitionExecutionTrace, resolution: CandidateResolution)] {
        let resolutionMap = Dictionary(uniqueKeysWithValues: resolutions.map { ($0.group.id, $0) })
        return traces.compactMap { trace in
            guard let resolution = resolutionMap[trace.planID] else { return nil }
            return (trace, resolution)
        }
    }

    private func makeOrderStrategyEffectiveness(
        from joined: [(trace: ReRecognitionExecutionTrace, resolution: CandidateResolution)]
    ) -> ReRecognitionSessionSummary.OrderEffectivenessStats {
        let planCount = joined.count
        let recommendedBecameBestCount = joined.count {
            $0.trace.recommendedBackend == $0.resolution.bestCandidate?.backend
        }
        let recommendedReadyForReviewCount = joined.count {
            $0.trace.recommendedBackend == $0.resolution.bestCandidate?.backend && $0.resolution.readyForReview
        }
        let firstTriedBecameBestCount = joined.count {
            $0.trace.firstTriedBackend == $0.resolution.bestCandidate?.backend
        }
        let bestFromNonFirstBackendCount = joined.count {
            guard let bestBackend = $0.resolution.bestCandidate?.backend,
                  let firstBackend = $0.trace.firstTriedBackend else { return false }
            return bestBackend != firstBackend
        }

        return ReRecognitionSessionSummary.OrderEffectivenessStats(
            planCount: planCount,
            recommendedBecameBestCount: recommendedBecameBestCount,
            recommendedBecameBestRatio: ratio(recommendedBecameBestCount, planCount),
            recommendedReadyForReviewCount: recommendedReadyForReviewCount,
            recommendedReadyForReviewRatio: ratio(recommendedReadyForReviewCount, planCount),
            firstTriedBecameBestCount: firstTriedBecameBestCount,
            firstTriedBecameBestRatio: ratio(firstTriedBecameBestCount, planCount),
            bestFromNonFirstBackendCount: bestFromNonFirstBackendCount,
            bestFromNonFirstBackendRatio: ratio(bestFromNonFirstBackendCount, planCount)
        )
    }

    private func rankBackendNames(
        backendNames: [String],
        triggerFlags: [SuspicionFlag],
        hints: [ReRecognitionSessionSummary.BackendPreferenceHint]
    ) -> [BackendPriorityEntry] {
        let triggerCodes = Array(Set(triggerFlags.map(\.code))).sorted()
        let hintMap = Dictionary(uniqueKeysWithValues: hints.map { ($0.triggerFlag, $0) })

        return backendNames.map { backend in
            var score = 0
            var matchedFlags: [String] = []
            var reasons: [String] = []

            for code in triggerCodes {
                guard let hint = hintMap[code], hint.preferredBackend == backend else { continue }
                let contribution = rankingContribution(for: hint)
                guard contribution > 0 else {
                    reasons.append("\(code) hint 未过样本门槛")
                    continue
                }
                score += contribution
                matchedFlags.append(code)
                reasons.append("\(code) 推荐 \(backend)")
            }

            if matchedFlags.isEmpty {
                reasons.append("当前会话暂无命中 \(backend) 的 flag hint")
            }

            return BackendPriorityEntry(
                backend: backend,
                score: score,
                matchedTriggerFlags: matchedFlags,
                reasons: reasons
            )
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.backend < rhs.backend
            }
            return lhs.score > rhs.score
        }
    }

    private func rankingContribution(
        for hint: ReRecognitionSessionSummary.BackendPreferenceHint
    ) -> Int {
        switch hint.source {
        case .historical:
            guard hint.meetsSampleThreshold else { return 0 }
            switch hint.confidence {
            case .low: return 1
            case .medium: return 2
            case .high: return 3
            }
        case .session:
            switch hint.confidence {
            case .low: return 1
            case .medium: return 2
            case .high: return 3
            }
        case .blended:
            switch hint.confidence {
            case .low: return 2
            case .medium: return 4
            case .high: return 5
            }
        }
    }

    private func classifyBlendedOrderingSource(
        rankedBackends: [BackendPriorityEntry],
        triggerFlags: [SuspicionFlag],
        sessionHints: [ReRecognitionSessionSummary.BackendPreferenceHint],
        historicalHints: [ReRecognitionSessionSummary.BackendPreferenceHint]
    ) -> ReRecognitionOrderStrategySource {
        guard let top = rankedBackends.first, top.score > 0 else { return .fixedDefault }
        let triggerCodes = Set(triggerFlags.map(\.code))
        let sessionMap = Dictionary(uniqueKeysWithValues: sessionHints.map { ($0.triggerFlag, $0) })
        let historicalMap = Dictionary(uniqueKeysWithValues: historicalHints.map { ($0.triggerFlag, $0) })

        let hasSession = triggerCodes.contains { code in
            sessionMap[code]?.preferredBackend == top.backend
        }
        let hasHistorical = triggerCodes.contains { code in
            guard let hint = historicalMap[code] else { return false }
            return hint.preferredBackend == top.backend && hint.meetsSampleThreshold
        }

        switch (hasSession, hasHistorical) {
        case (true, true):
            return .blendedDriven
        case (true, false):
            return .sessionDriven
        case (false, true):
            return .historicalDriven
        case (false, false):
            return .fixedDefault
        }
    }

    private func sessionConfidence(
        for summary: ReRecognitionSessionSummary.TriggerFlagBackendSummary
    ) -> ReRecognitionSessionSummary.HintConfidence {
        if summary.readyForReviewCount > 0 || summary.acceptedCount >= 2 {
            return .high
        }
        if summary.acceptedCount > 0 || summary.candidateCount >= 2 {
            return .medium
        }
        return .low
    }

    private func historicalConfidence(
        for details: HistoricalScoreDetails
    ) -> ReRecognitionSessionSummary.HintConfidence {
        guard details.meetsSampleThreshold else { return .low }
        if details.sampleCount >= configuration.historicalMinimumSampleCount * 2,
           details.score >= 8 {
            return .high
        }
        return .medium
    }

    private func blendedConfidence(
        sessionHint: ReRecognitionSessionSummary.BackendPreferenceHint?,
        historicalHint: ReRecognitionSessionSummary.BackendPreferenceHint?,
        chosenBackend: String
    ) -> ReRecognitionSessionSummary.HintConfidence {
        let chosenSession = sessionHint?.preferredBackend == chosenBackend ? sessionHint : nil
        let chosenHistorical = historicalHint?.preferredBackend == chosenBackend ? historicalHint : nil

        if chosenSession?.confidence == .high,
           chosenHistorical?.confidence == .high,
           chosenHistorical?.meetsSampleThreshold == true {
            return .high
        }

        if chosenSession != nil || chosenHistorical?.meetsSampleThreshold == true {
            return .medium
        }

        return .low
    }

    private func historicalScoreDetails(
        for stat: HistoricalBackendPreferenceStat
    ) -> HistoricalScoreDetails {
        let recentEvents = Array(stat.recentEvents.suffix(configuration.historicalRecentEventLimit))

        if !recentEvents.isEmpty {
            let weightedScore = recentEvents.enumerated().reduce(into: 0.0) { partialResult, item in
                let weight = recencyWeight(index: item.offset, count: recentEvents.count)
                let eventScore = Double(
                    item.element.acceptedDelta * 3
                        + item.element.readyForReviewDelta * 4
                        + item.element.candidateDelta
                        - item.element.hintMissedDelta * 2
                )
                partialResult += eventScore * weight
            }

            let sampleCount = recentEvents.count
            return HistoricalScoreDetails(
                score: Int(weightedScore.rounded()),
                sampleCount: sampleCount,
                meetsSampleThreshold: sampleCount >= configuration.historicalMinimumSampleCount,
                weighting: "recent-\(configuration.historicalRecentEventLimit)-linear-recency",
                usedRecencyWeighting: true
            )
        }

        let fallbackSampleCount = min(stat.candidateCount, 1)
        let fallbackScore = stat.acceptedCount * 3
            + stat.readyForReviewCount * 4
            + stat.candidateCount
            - stat.hintMissedCount * 2
        return HistoricalScoreDetails(
            score: fallbackScore,
            sampleCount: fallbackSampleCount,
            meetsSampleThreshold: false,
            weighting: "legacy-aggregate-fallback",
            usedRecencyWeighting: false
        )
    }

    private func recencyWeight(index: Int, count: Int) -> Double {
        guard count > 1 else { return 1.0 }
        let progress = Double(index) / Double(count - 1)
        return 0.35 + progress * 0.65
    }

    private func ratio(_ numerator: Int, _ denominator: Int) -> Double {
        guard denominator > 0 else { return 0 }
        return Double(numerator) / Double(denominator)
    }

    private func normalizeCandidateText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private func isWeakerTriggerBackendSummary(
        _ lhs: ReRecognitionSessionSummary.TriggerFlagBackendSummary,
        _ rhs: ReRecognitionSessionSummary.TriggerFlagBackendSummary
    ) -> Bool {
        let lhsTuple = (lhs.acceptedCount, lhs.readyForReviewCount, lhs.candidateCount, -lhs.rejectedCount)
        let rhsTuple = (rhs.acceptedCount, rhs.readyForReviewCount, rhs.candidateCount, -rhs.rejectedCount)
        if lhsTuple != rhsTuple {
            return lhsTuple < rhsTuple
        }
        return lhs.backend < rhs.backend
    }

    private func isWeakerHistoricalEntry(
        _ lhs: (stat: HistoricalBackendPreferenceStat, details: HistoricalScoreDetails),
        _ rhs: (stat: HistoricalBackendPreferenceStat, details: HistoricalScoreDetails)
    ) -> Bool {
        let lhsTuple = (
            lhs.details.meetsSampleThreshold ? 1 : 0,
            lhs.details.score,
            lhs.details.sampleCount,
            lhs.stat.readyForReviewCount,
            lhs.stat.acceptedCount,
            -lhs.stat.hintMissedCount
        )
        let rhsTuple = (
            rhs.details.meetsSampleThreshold ? 1 : 0,
            rhs.details.score,
            rhs.details.sampleCount,
            rhs.stat.readyForReviewCount,
            rhs.stat.acceptedCount,
            -rhs.stat.hintMissedCount
        )

        if lhsTuple != rhsTuple {
            return lhsTuple < rhsTuple
        }
        return lhs.stat.backend < rhs.stat.backend
    }
}
