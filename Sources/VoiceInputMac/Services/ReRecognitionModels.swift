import Foundation

// MARK: - Candidate Comparison

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

// MARK: - Statistics & Backend Priority

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

// MARK: - Re-Recognition Order Strategy

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

// MARK: - Session Summary

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
