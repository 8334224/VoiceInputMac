import Foundation

/// Formats and prints diagnostic logs for the re-recognition pipeline.
/// Stateless — all data is passed in as parameters.
struct ReRecognitionLogger {
    let experimentPathEnabled: Bool

    // MARK: - Suspicious Segments

    func logSuspiciousSegmentsIfNeeded(_ segments: [TranscriptSegment], isFinal: Bool) {
        guard experimentPathEnabled else { return }
        let flaggedSegments = segments.filter { !$0.suspicionFlags.isEmpty }
        guard !flaggedSegments.isEmpty else { return }

        for segment in flaggedSegments {
            let codes = segment.suspicionFlags.map(\.code).joined(separator: ", ")
            print(
                "[SuspicionDetector][\(isFinal ? "final" : "partial")] " +
                "[\(String(format: "%.2f", segment.startTime))-\(String(format: "%.2f", segment.endTime))] " +
                "\(codes) :: \(segment.text)"
            )
        }
    }

    // MARK: - Re-Recognition Plans

    func logReRecognitionPlans(_ plans: [ReRecognitionPlan]) {
        guard experimentPathEnabled else { return }
        guard !plans.isEmpty else {
            print("[ReRecognitionPlanner] no plans")
            return
        }

        for plan in plans {
            let codes = plan.triggerFlags.map(\.code).joined(separator: ", ")
            print(
                "[ReRecognitionPlanner] priority=\(plan.priority) " +
                "window=\(String(format: "%.2f", plan.startTime))-\(String(format: "%.2f", plan.endTime)) " +
                "reasons=\(codes) text=\(plan.originalText)"
            )
        }
    }

    // MARK: - Re-Recognition Evaluation

    func logReRecognitionEvaluation(_ evaluation: ReRecognitionCandidateRecord) {
        guard experimentPathEnabled else { return }
        let reasons = evaluation.decisionReasons.joined(separator: " | ")
        print(
            "[ReRecognitionEvaluation] mode=\(evaluation.replacementMode.rawValue) " +
            "score=\(evaluation.score) " +
            "promote=\(evaluation.shouldPromoteCandidate) " +
            "window=\(String(format: "%.2f", evaluation.startTime))-\(String(format: "%.2f", evaluation.endTime)) " +
            "backend=\(evaluation.backend) " +
            "reasons=\(reasons)"
        )
    }

    // MARK: - Candidate Store Snapshot

    func logCandidateStoreSnapshot(
        summary: ReRecognitionSessionSummary,
        readyForReviewCount: Int,
        experimentTag: ReRecognitionExperimentTag
    ) {
        guard experimentPathEnabled else { return }
        let topFlags = summary.commonTriggerFlags.map { "\($0.label):\($0.count)" }.joined(separator: ", ")
        let topReasons = summary.commonDecisionReasons.map { "\($0.label):\($0.count)" }.joined(separator: ", ")
        let backendStats = summary.backendSummaries.map {
            "\($0.backend){candidates:\($0.candidateCount),accepted:\($0.acceptedCount),ready:\($0.readyForReviewCount)}"
        }.joined(separator: "; ")
        let flagBackendStats = summary.triggerFlagBackendSummaries.map {
            "\($0.triggerFlag)->\($0.backend){candidates:\($0.candidateCount),accepted:\($0.acceptedCount),ready:\($0.readyForReviewCount)}"
        }.joined(separator: "; ")
        let hintEffectiveness =
            "groups:\(summary.hintEffectiveness.groupsWithHints)," +
            "best:\(summary.hintEffectiveness.recommendedBecameBestCount)," +
            "ready:\(summary.hintEffectiveness.recommendedReadyForReviewCount)," +
            "missed:\(summary.hintEffectiveness.hintMissedCount)"
        let orderOverall = formatOrderEffectiveness(summary.orderEffectiveness.overall)
        let sessionHints = summary.sessionBackendPreferenceHints.map(formatHint).joined(separator: "; ")
        let historicalHints = summary.historicalBackendPreferenceHints.map(formatHint).joined(separator: "; ")
        let blendedHints = summary.blendedBackendPreferenceHints.map(formatHint).joined(separator: "; ")
        let strategySourceStats = summary.orderEffectiveness.byStrategySource.map {
            "\($0.source.rawValue){\(formatOrderEffectiveness($0.stats))}"
        }.joined(separator: "; ")
        let modeStats = summary.orderEffectiveness.byMode.map {
            "\($0.mode.rawValue){\(formatOrderEffectiveness($0.stats))}"
        }.joined(separator: "; ")
        let backendDivergence = formatBackendDivergence(summary.backendDivergence)
        print(
            "[ReRecognitionSessionSummary] " +
            "sampleLabel=\(experimentTag.sampleLabel?.rawValue ?? "-") " +
            "sessionTag=\(experimentTag.sessionTag ?? "-") " +
            "mode=\(summary.currentOrderMode.rawValue) " +
            "plans=\(summary.planCount) " +
            "rerecognized=\(summary.actualReRecognitionCount) " +
            "accepted=\(summary.acceptedCount) " +
            "rejected=\(summary.rejectedCount) " +
            "readyForReview=\(readyForReviewCount) " +
            "topFlags=\(topFlags.isEmpty ? "-" : topFlags) " +
            "topReasons=\(topReasons.isEmpty ? "-" : topReasons) " +
            "backends=\(backendStats.isEmpty ? "-" : backendStats) " +
            "flagBackends=\(flagBackendStats.isEmpty ? "-" : flagBackendStats) " +
            "sessionHints=\(sessionHints.isEmpty ? "-" : sessionHints) " +
            "historicalHints=\(historicalHints.isEmpty ? "-" : historicalHints) " +
            "blendedHints=\(blendedHints.isEmpty ? "-" : blendedHints) " +
            "hintEffectiveness=\(hintEffectiveness) " +
            "backendDivergence=\(backendDivergence) " +
            "orderEffectiveness.overall=\(orderOverall) " +
            "orderEffectiveness.byStrategySource=\(strategySourceStats.isEmpty ? "-" : strategySourceStats) " +
            "orderEffectiveness.byMode=\(modeStats.isEmpty ? "-" : modeStats)"
        )
    }

    // MARK: - Backend Order

    func logHintDrivenBackendOrder(
        plan: ReRecognitionPlan,
        strategyMode: ReRecognitionOrderMode,
        strategySource: ReRecognitionOrderStrategySource,
        rankedBackends: [BackendPriorityEntry]
    ) {
        guard experimentPathEnabled else { return }
        let triggerFlags = plan.triggerFlags.map(\.code).joined(separator: ",")
        let order = rankedBackends.map {
            "\($0.backend)(score:\($0.score),flags:\($0.matchedTriggerFlags.joined(separator: "+")),reasons:\($0.reasons.joined(separator: "|")))"
        }.joined(separator: " -> ")
        print(
            "[ReRecognitionBackendOrder] " +
            "window=\(String(format: "%.2f", plan.startTime))-\(String(format: "%.2f", plan.endTime)) " +
            "triggerFlags=\(triggerFlags.isEmpty ? "-" : triggerFlags) " +
            "mode=\(strategyMode.rawValue) " +
            "source=\(strategySource.rawValue) " +
            "order=\(order)"
        )
    }

    // MARK: - Formatting Helpers

    func formatHint(_ hint: ReRecognitionSessionSummary.BackendPreferenceHint) -> String {
        "\(hint.triggerFlag):\(hint.preferredBackend)" +
        "(source:\(hint.source.rawValue),score:\(hint.score),conf:\(hint.confidence.rawValue),samples:\(hint.sampleCount)," +
        "threshold:\(hint.meetsSampleThreshold),weighting:\(hint.weighting))"
    }

    func formatRatio(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    func formatOrderEffectiveness(
        _ stats: ReRecognitionSessionSummary.OrderEffectivenessStats
    ) -> String {
        "plans:\(stats.planCount)," +
        "recommendedBest:\(stats.recommendedBecameBestCount)/\(stats.planCount)(\(formatRatio(stats.recommendedBecameBestRatio)))," +
        "recommendedReady:\(stats.recommendedReadyForReviewCount)/\(stats.planCount)(\(formatRatio(stats.recommendedReadyForReviewRatio)))," +
        "firstBest:\(stats.firstTriedBecameBestCount)/\(stats.planCount)(\(formatRatio(stats.firstTriedBecameBestRatio)))," +
        "nonFirstBest:\(stats.bestFromNonFirstBackendCount)/\(stats.planCount)(\(formatRatio(stats.bestFromNonFirstBackendRatio)))"
    }

    func formatBackendDivergence(
        _ summary: ReRecognitionSessionSummary.BackendDivergenceSummary
    ) -> String {
        "compared:\(summary.comparedPlanCount)," +
        "multiBackend:\(summary.multiBackendPlanCount)," +
        "textDiff:\(summary.textDivergenceCount)," +
        "scoreDiff:\(summary.scoreDivergenceCount)," +
        "suitable:\(summary.suitableForOrderComparisonCount)/\(summary.comparedPlanCount)(\(formatRatio(summary.suitableForOrderComparisonRatio)))"
    }
}
