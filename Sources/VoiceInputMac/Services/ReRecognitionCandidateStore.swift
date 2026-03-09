import Foundation

struct ReRecognitionCandidateRecord: Identifiable, Sendable {
    let id: UUID
    let sessionID: UUID?
    let segmentIDs: [String]
    let originalText: String
    let candidateText: String
    let score: Int
    let decisionReasons: [String]
    let triggerFlags: [SuspicionFlag]
    let startTime: TimeInterval
    let endTime: TimeInterval
    let backend: String
    let shouldPromoteCandidate: Bool
    let replacementMode: ReplacementMode
    let createdAt: Date
}

struct ReRecognitionExecutionTrace: Identifiable, Sendable {
    struct BackendAttemptResult: Identifiable, Sendable {
        enum Status: String, Sendable {
            case attempted
            case succeeded
            case failed
        }

        let id: UUID
        let backend: String
        var status: Status
        var failureReason: String?
        let attemptedAt: Date
        var completedAt: Date?
    }

    let id: UUID
    let sessionID: UUID?
    let planID: String
    let segmentIDs: [String]
    let strategyMode: ReRecognitionOrderMode
    let strategySource: ReRecognitionOrderStrategySource
    let recommendedBackend: String?
    let firstTriedBackend: String?
    let attemptedBackends: [String]
    var backendAttemptResults: [BackendAttemptResult]
    let createdAt: Date
}

actor ReRecognitionCandidateStore {
    private var currentSessionID: UUID?
    private var plans: [ReRecognitionPlan] = []
    private var records: [ReRecognitionCandidateRecord] = []
    private var executionTraces: [String: ReRecognitionExecutionTrace] = [:]

    func beginSession(id: UUID?) {
        currentSessionID = id
        plans.removeAll()
        records.removeAll()
        executionTraces.removeAll()
    }

    func recordPlans(_ newPlans: [ReRecognitionPlan]) {
        plans = newPlans
    }

    func record(_ record: ReRecognitionCandidateRecord) {
        records.append(record)
    }

    func recordExecutionTrace(_ trace: ReRecognitionExecutionTrace) {
        executionTraces[trace.planID] = trace
    }

    func markBackendAttemptStarted(planID: String, backend: String, at: Date = Date()) {
        guard var trace = executionTraces[planID] else { return }
        if let index = trace.backendAttemptResults.firstIndex(where: { $0.backend == backend }) {
            trace.backendAttemptResults[index].status = .attempted
            trace.backendAttemptResults[index].failureReason = nil
            trace.backendAttemptResults[index].completedAt = nil
        } else {
            trace.backendAttemptResults.append(
                .init(
                    id: UUID(),
                    backend: backend,
                    status: .attempted,
                    failureReason: nil,
                    attemptedAt: at,
                    completedAt: nil
                )
            )
        }
        executionTraces[planID] = trace
    }

    func markBackendAttemptSucceeded(planID: String, backend: String, at: Date = Date()) {
        guard var trace = executionTraces[planID] else { return }
        if let index = trace.backendAttemptResults.firstIndex(where: { $0.backend == backend }) {
            trace.backendAttemptResults[index].status = .succeeded
            trace.backendAttemptResults[index].failureReason = nil
            trace.backendAttemptResults[index].completedAt = at
        } else {
            trace.backendAttemptResults.append(
                .init(
                    id: UUID(),
                    backend: backend,
                    status: .succeeded,
                    failureReason: nil,
                    attemptedAt: at,
                    completedAt: at
                )
            )
        }
        executionTraces[planID] = trace
    }

    func markBackendAttemptFailed(
        planID: String,
        backend: String,
        failureReason: String,
        at: Date = Date()
    ) {
        guard var trace = executionTraces[planID] else { return }
        if let index = trace.backendAttemptResults.firstIndex(where: { $0.backend == backend }) {
            trace.backendAttemptResults[index].status = .failed
            trace.backendAttemptResults[index].failureReason = failureReason
            trace.backendAttemptResults[index].completedAt = at
        } else {
            trace.backendAttemptResults.append(
                .init(
                    id: UUID(),
                    backend: backend,
                    status: .failed,
                    failureReason: failureReason,
                    attemptedAt: at,
                    completedAt: at
                )
            )
        }
        executionTraces[planID] = trace
    }

    func allPlans() -> [ReRecognitionPlan] {
        plans
    }

    func allRecords() -> [ReRecognitionCandidateRecord] {
        records
    }

    func allExecutionTraces() -> [ReRecognitionExecutionTrace] {
        executionTraces.values.sorted { $0.createdAt < $1.createdAt }
    }

    func acceptedCandidates() -> [ReRecognitionCandidateRecord] {
        records.filter(\.shouldPromoteCandidate)
    }

    func rejectedCandidates() -> [ReRecognitionCandidateRecord] {
        records.filter { !$0.shouldPromoteCandidate }
    }

    func sessionID() -> UUID? {
        currentSessionID
    }

    func groupedBySegmentIDs() -> [CandidateComparisonGroup] {
        let grouped = Dictionary(grouping: records) { $0.segmentIDs.joined(separator: "|") }

        return grouped.values.compactMap { records in
            guard let first = records.first else { return nil }
            let matchingPlan = plans.first(where: { $0.segmentIDs == first.segmentIDs })

            return CandidateComparisonGroup(
                id: matchingPlan?.id ?? first.segmentIDs.joined(separator: "|"),
                segmentIDs: first.segmentIDs,
                originalText: matchingPlan?.originalText ?? first.originalText,
                startTime: matchingPlan?.startTime ?? first.startTime,
                endTime: matchingPlan?.endTime ?? first.endTime,
                triggerFlags: matchingPlan?.triggerFlags ?? first.triggerFlags,
                candidates: records.sorted { $0.createdAt < $1.createdAt }
            )
        }
        .sorted { $0.startTime < $1.startTime }
    }

    func groups(matchingSegmentIDs segmentIDs: [String]) -> [CandidateComparisonGroup] {
        groupedBySegmentIDs().filter { $0.segmentIDs == segmentIDs }
    }

    func groups(overlappingStart startTime: TimeInterval, endTime: TimeInterval) -> [CandidateComparisonGroup] {
        groupedBySegmentIDs().filter { group in
            max(group.startTime, startTime) <= min(group.endTime, endTime)
        }
    }
}
