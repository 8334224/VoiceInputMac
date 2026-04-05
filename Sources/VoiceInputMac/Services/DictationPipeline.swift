import AVFoundation
import Foundation

protocol DictationPipelineControlling: AnyObject, Sendable {
    func start(
        settings: AppSettings,
        onStatus: @escaping @Sendable (String) -> Void,
        onPreview: @escaping @Sendable (String) -> Void,
        onSegments: @escaping @Sendable ([TranscriptSegment]) -> Void,
        onActiveInputDevice: @escaping @Sendable (ActiveInputDeviceInfo) -> Void,
        onAudioLevel: @escaping @Sendable (Float) -> Void,
        onFailure: @escaping @Sendable (Error) -> Void
    ) async throws

    func stop(
        settings: AppSettings,
        onStatus: @escaping @Sendable (String) -> Void,
        onSegments: @escaping @Sendable ([TranscriptSegment]) -> Void
    ) async throws -> DictationPipeline.StopResult

    func cancelCurrentSession()
    func setReRecognitionOrderMode(_ mode: ReRecognitionOrderMode)
    func setExperimentPathEnabled(_ enabled: Bool)
    func setReRecognitionExperimentTag(sampleLabel: ReRecognitionExperimentSampleLabel?, sessionTag: String?)
    func saveLatestReRecognitionExperimentJSON(prettyPrinted: Bool) async throws -> URL
    func reRecognitionExperimentExportDirectoryURL() throws -> URL
}

final class DictationPipeline: DictationPipelineControlling, @unchecked Sendable {
    enum OnlineOptimizationStatus: Equatable {
        case disabled
        case optimized(elapsed: TimeInterval, quotaSummary: String?)
        case fallback(String)
    }

    struct StopResult {
        let text: String
        let onlineOptimizationStatus: OnlineOptimizationStatus
    }

    enum DictationError: LocalizedError {
        case alreadyRunning
        case notRunning
        case missingSessionAudio

        var errorDescription: String? {
            switch self {
            case .alreadyRunning:
                return "当前已有一段听写正在进行。"
            case .notRunning:
                return "当前没有进行中的听写。"
            case .missingSessionAudio:
                return "当前会话没有可用的录音缓存。"
            }
        }
    }

    private let audioCaptureService = AudioCaptureService()
    private let optimizer = OnlineOptimizer()
    private let reRecognitionPlanner = ReRecognitionPlanner()
    private let candidateStore = ReRecognitionCandidateStore()
    private let candidateResolver = CandidateResolver()
    private let backendPreferenceHistoryStore = BackendPreferenceHistoryStore()
    private let enabledReRecognitionBackends = ReRecognitionBackendOption.allCases.filter(\.shouldRunByDefault)
    /// Serial queue protecting mutable pipeline state against concurrent access.
    private let stateQueue = DispatchQueue(label: "VoiceInputMac.DictationPipeline.state")
    private var reRecognitionOrderMode: ReRecognitionOrderMode = .blended
    private var experimentTag = ReRecognitionExperimentTag(sampleLabel: nil, sessionTag: nil)
    private var experimentPathEnabled = false
    private var logger = ReRecognitionLogger(experimentPathEnabled: false)

    private var correctionPipeline = TextCorrectionPipeline(settings: .init())
    private var postProcessor: any TextPostProcessor = BasicTextPostProcessor(correctionPipeline: .init(settings: .init()))
    private var reRecognitionEvaluator = ReRecognitionEvaluator(correctionPipeline: .init(settings: .init()))
    private var recognitionBackend: RecognitionBackend?
    private var suspicionDetector = SuspicionDetector(correctionPipeline: .init(settings: .init()))
    private var running = false
    private var latestSnapshot = RecognitionResultSnapshot.empty(source: "apple.speech")
    private(set) var lastSessionRecord: DictationSessionRecord?
    private var pendingReRecognitionTask: Task<Void, Never>?

    func start(
        settings: AppSettings,
        onStatus: @escaping @Sendable (String) -> Void,
        onPreview: @escaping @Sendable (String) -> Void,
        onSegments: @escaping @Sendable ([TranscriptSegment]) -> Void = { _ in },
        onActiveInputDevice: @escaping @Sendable (ActiveInputDeviceInfo) -> Void = { _ in },
        onAudioLevel: @escaping @Sendable (Float) -> Void = { _ in },
        onFailure: @escaping @Sendable (Error) -> Void = { _ in }
    ) async throws {
        await awaitPendingReRecognitionIfNeeded()
        let alreadyRunning = stateQueue.sync { running }
        guard !alreadyRunning else { throw DictationError.alreadyRunning }

        correctionPipeline = TextCorrectionPipeline(settings: settings)
        postProcessor = BasicTextPostProcessor(correctionPipeline: correctionPipeline)
        reRecognitionEvaluator = ReRecognitionEvaluator(correctionPipeline: correctionPipeline)
        suspicionDetector = SuspicionDetector(correctionPipeline: correctionPipeline)
        suspicionDetector.reset()
        latestSnapshot = RecognitionResultSnapshot.empty(source: "apple.speech")
        lastSessionRecord = nil
        await candidateStore.beginSession(id: nil)

        let backend = AppleSpeechRecognitionBackend()
        stateQueue.sync { recognitionBackend = backend }

        let configuration = RecognitionConfiguration(
            localeIdentifier: settings.localeIdentifier,
            contextualPhrases: correctionPipeline.customPhrases,
            addsPunctuation: true,
            requiresOnDeviceRecognition: false
        )

        try backend.startSession(configuration: configuration) { [weak self] snapshot in
            guard let self else { return }
            let postProcessed = self.postProcessor.process(snapshot)
            let detected = self.suspicionDetector.evaluate(
                rawSnapshot: snapshot,
                processedSnapshot: postProcessed
            )
            self.stateQueue.sync { self.latestSnapshot = detected }
            self.logger.logSuspiciousSegmentsIfNeeded(detected.segments, isFinal: detected.isFinal)
            onPreview(detected.displayText)
            onSegments(detected.segments)
        }

        onStatus("使用苹果语音识别...")

        do {
            let sessionAudio = try audioCaptureService.startSession(
                selection: settings.microphoneSelection,
                onBuffer: { [weak self] buffer, _ in
                    self?.stateQueue.sync { self?.recognitionBackend }?.appendAudioBuffer(buffer)
                    if let channelData = buffer.floatChannelData?[0] {
                        let frameLength = Int(buffer.frameLength)
                        guard frameLength > 0 else { return }
                        var sumOfSquares: Float = 0
                        for i in 0..<frameLength {
                            let sample = channelData[i]
                            sumOfSquares += sample * sample
                        }
                        let rms = sqrtf(sumOfSquares / Float(frameLength))
                        onAudioLevel(rms)
                    }
                },
                onFailure: { [weak self] error in
                    if let self {
                        self.stateQueue.sync {
                            self.running = false
                            self.recognitionBackend?.cancel()
                            self.recognitionBackend = nil
                        }
                    }
                    onFailure(error)
                }
            )
            lastSessionRecord = DictationSessionRecord(
                id: sessionAudio.id,
                transcript: latestSnapshot,
                audio: sessionAudio
            )
            if let inputDevice = sessionAudio.inputDevice {
                onActiveInputDevice(inputDevice)
            }
            await candidateStore.beginSession(id: sessionAudio.id)
        } catch {
            stateQueue.sync {
                recognitionBackend?.cancel()
                recognitionBackend = nil
            }
            throw error
        }

        stateQueue.sync { running = true }
        onStatus("正在听写...")
    }

    func stop(
        settings: AppSettings,
        onStatus: @escaping @Sendable (String) -> Void,
        onSegments: @escaping @Sendable ([TranscriptSegment]) -> Void = { _ in }
    ) async throws -> StopResult {
        let currentBackend: RecognitionBackend? = stateQueue.sync {
            guard running else { return nil }
            running = false
            return recognitionBackend
        }
        guard let currentBackend else { throw DictationError.notRunning }

        onStatus("整理转写结果...")

        // Keep a short tail so the final syllables are not cut off,
        // but avoid making the stop action feel sluggish.
        try? await Task.sleep(nanoseconds: 180_000_000)

        let sessionAudio = try audioCaptureService.stopSession()
        let finalizedSnapshot: RecognitionResultSnapshot
        do {
            finalizedSnapshot = try await currentBackend.finish()
        } catch {
            currentBackend.cancel()
            stateQueue.sync { self.recognitionBackend = nil }
            throw error
        }
        stateQueue.sync { self.recognitionBackend = nil }

        let postProcessed = postProcessor.process(finalizedSnapshot)
        let processedSnapshot = suspicionDetector.evaluate(
            rawSnapshot: finalizedSnapshot,
            processedSnapshot: postProcessed
        )
        stateQueue.sync { latestSnapshot = processedSnapshot }
        logger.logSuspiciousSegmentsIfNeeded(processedSnapshot.segments, isFinal: processedSnapshot.isFinal)
        onSegments(processedSnapshot.segments)

        let localText = processedSnapshot.displayText
        var finalText = localText
        var onlineOptimizationStatus: OnlineOptimizationStatus = .disabled
        if !localText.isEmpty, settings.onlineOptimizationEnabled {
            onStatus("在线纠错优化中...")
            let outcome = await optimizer.optimizeWithDiagnostics(localText, settings: settings, correctionPipeline: correctionPipeline)
            switch outcome {
            case .notEnabled:
                onlineOptimizationStatus = .disabled
            case let .optimized(optimized, quota, elapsed):
                finalText = correctionPipeline.applyLocalCorrections(to: optimized)
                onlineOptimizationStatus = .optimized(elapsed: elapsed, quotaSummary: quota?.summary)
            case let .fallbackToLocal(result, reason):
                finalText = correctionPipeline.applyLocalCorrections(to: result)
                onlineOptimizationStatus = .fallback(reason)
            }
        } else if settings.onlineOptimizationEnabled {
            onlineOptimizationStatus = .fallback("首轮转写为空，未执行在线纠错。")
        }

        let finalSnapshot = RecognitionResultSnapshot(
            rawText: processedSnapshot.rawText,
            displayText: finalText,
            segments: processedSnapshot.segments,
            isFinal: true,
            source: processedSnapshot.source
        )

        let sessionID = sessionAudio?.id ?? UUID()
        let sessionRecord = DictationSessionRecord(
            id: sessionID,
            transcript: finalSnapshot,
            audio: sessionAudio
        )
        lastSessionRecord = sessionRecord
        scheduleReRecognition(sessionRecord: sessionRecord, settings: settings)

        return StopResult(text: finalText, onlineOptimizationStatus: onlineOptimizationStatus)
    }

    func latestSegments() -> [TranscriptSegment] {
        stateQueue.sync { latestSnapshot.segments }
    }

    func latestSession() -> DictationSessionRecord? {
        lastSessionRecord
    }

    func latestReRecognitionRecords() async -> [ReRecognitionCandidateRecord] {
        await candidateStore.allRecords()
    }

    func latestReRecognitionPlans() async -> [ReRecognitionPlan] {
        await candidateStore.allPlans()
    }

    func latestAcceptedCandidates() async -> [ReRecognitionCandidateRecord] {
        await candidateStore.acceptedCandidates()
    }

    func latestRejectedCandidates() async -> [ReRecognitionCandidateRecord] {
        await candidateStore.rejectedCandidates()
    }

    func candidateComparisonsBySegmentIDs() async -> [CandidateResolution] {
        let groups = await candidateStore.groupedBySegmentIDs()
        return groups.map { candidateResolver.resolve(group: $0) }
    }

    func candidateComparisons(matchingSegmentIDs segmentIDs: [String]) async -> [CandidateResolution] {
        let groups = await candidateStore.groups(matchingSegmentIDs: segmentIDs)
        return groups.map { candidateResolver.resolve(group: $0) }
    }

    func candidateComparisons(overlappingStart startTime: TimeInterval, endTime: TimeInterval) async -> [CandidateResolution] {
        let groups = await candidateStore.groups(overlappingStart: startTime, endTime: endTime)
        return groups.map { candidateResolver.resolve(group: $0) }
    }

    func latestReRecognitionSummary() async -> ReRecognitionSessionSummary {
        let sessionID = await candidateStore.sessionID()
        let plans = await candidateStore.allPlans()
        let records = await candidateStore.allRecords()
        let groups = await candidateStore.groupedBySegmentIDs()
        let resolutions = groups.map { candidateResolver.resolve(group: $0) }
        let executionTraces = await candidateStore.allExecutionTraces()
        let historicalStats = await backendPreferenceHistoryStore.snapshot()
        return candidateResolver.summarize(
            sessionID: sessionID,
            currentOrderMode: reRecognitionOrderMode,
            plans: plans,
            records: records,
            resolutions: resolutions,
            executionTraces: executionTraces,
            historicalStats: historicalStats
        )
    }

    func reRecognitionBackendCapabilities() -> [BackendCapabilities] {
        ReRecognitionBackendOption.allCases.map(\.capabilities)
    }

    func setReRecognitionOrderMode(_ mode: ReRecognitionOrderMode) {
        reRecognitionOrderMode = mode
    }

    func setExperimentPathEnabled(_ enabled: Bool) {
        experimentPathEnabled = enabled
        logger = ReRecognitionLogger(experimentPathEnabled: enabled)
    }

    func isExperimentPathEnabled() -> Bool {
        experimentPathEnabled
    }

    func currentReRecognitionOrderMode() -> ReRecognitionOrderMode {
        reRecognitionOrderMode
    }

    func setReRecognitionExperimentTag(
        sampleLabel: ReRecognitionExperimentSampleLabel?,
        sessionTag: String? = nil
    ) {
        experimentTag = ReRecognitionExperimentTag(
            sampleLabel: sampleLabel,
            sessionTag: sessionTag?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
    }

    func currentReRecognitionExperimentTag() -> ReRecognitionExperimentTag {
        experimentTag
    }

    @discardableResult
    func runFixedAudioExperimentAndSave(
        audioFileURL: URL,
        settings: AppSettings,
        prettyPrinted: Bool = true
    ) async throws -> URL {
        try await runFixedAudioExperiment(audioFileURL: audioFileURL, settings: settings)
        return try await saveLatestReRecognitionExperimentJSON(prettyPrinted: prettyPrinted)
    }

    func runFixedAudioExperiment(
        audioFileURL: URL,
        settings: AppSettings
    ) async throws {
        await awaitPendingReRecognitionIfNeeded()
        experimentPathEnabled = true

        correctionPipeline = TextCorrectionPipeline(settings: settings)
        postProcessor = BasicTextPostProcessor(correctionPipeline: correctionPipeline)
        reRecognitionEvaluator = ReRecognitionEvaluator(correctionPipeline: correctionPipeline)
        suspicionDetector = SuspicionDetector(correctionPipeline: correctionPipeline)
        suspicionDetector.reset()
        latestSnapshot = RecognitionResultSnapshot.empty(source: "apple.speech")
        recognitionBackend?.cancel()
        recognitionBackend = nil
        running = false

        let sessionAudio = try makeSessionAudioArtifact(from: audioFileURL)
        lastSessionRecord = nil
        await candidateStore.beginSession(id: sessionAudio.id)

        let backend = AppleSpeechRecognitionBackend()
        let configuration = RecognitionConfiguration(
            localeIdentifier: settings.localeIdentifier,
            contextualPhrases: correctionPipeline.customPhrases,
            addsPunctuation: true,
            requiresOnDeviceRecognition: false
        )

        let rawSnapshot = try await backend.transcribeAudioFile(at: audioFileURL, configuration: configuration)
        let postProcessed = postProcessor.process(rawSnapshot)
        let processedSnapshot = suspicionDetector.evaluate(
            rawSnapshot: rawSnapshot,
            processedSnapshot: postProcessed
        )
        latestSnapshot = processedSnapshot
        logger.logSuspiciousSegmentsIfNeeded(processedSnapshot.segments, isFinal: processedSnapshot.isFinal)

        let localText = processedSnapshot.displayText
        var finalText = localText
        if !localText.isEmpty, settings.onlineOptimizationEnabled {
            let optimized = try await optimizer.optimize(localText, settings: settings, correctionPipeline: correctionPipeline)
            finalText = correctionPipeline.applyLocalCorrections(to: optimized)
        }

        let finalSnapshot = RecognitionResultSnapshot(
            rawText: processedSnapshot.rawText,
            displayText: finalText,
            segments: processedSnapshot.segments,
            isFinal: true,
            source: processedSnapshot.source
        )
        let sessionRecord = DictationSessionRecord(
            id: sessionAudio.id,
            transcript: finalSnapshot,
            audio: sessionAudio
        )
        lastSessionRecord = sessionRecord
        scheduleReRecognition(sessionRecord: sessionRecord, settings: settings)
        await awaitPendingReRecognitionIfNeeded()
    }

    func exportLatestReRecognitionExperiment() async -> ReRecognitionExperimentExport {
        await awaitPendingReRecognitionIfNeeded()
        let summary = await latestReRecognitionSummary()
        let transcript = lastSessionRecord?.transcript ?? (latestSnapshot.segments.isEmpty ? nil : latestSnapshot)
        return ReRecognitionExperimentExport(
            summary: summary,
            experimentTag: experimentTag,
            transcript: transcript
        )
    }

    func exportLatestReRecognitionExperimentJSON(prettyPrinted: Bool = true) async -> String? {
        let export = await exportLatestReRecognitionExperiment()
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(export) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func saveLatestReRecognitionExperimentJSON(prettyPrinted: Bool = true) async throws -> URL {
        let export = await exportLatestReRecognitionExperiment()
        return try ReRecognitionExperimentExportStore.save(
            export: export,
            prettyPrinted: prettyPrinted
        )
    }

    func reRecognitionExperimentExportDirectoryURL() throws -> URL {
        try ReRecognitionExperimentExportStore.directoryURL()
    }

    func cancelCurrentSession() {
        stateQueue.sync {
            recognitionBackend?.cancel()
            recognitionBackend = nil
            running = false
        }
        audioCaptureService.cancelSession()
        pendingReRecognitionTask?.cancel()
        pendingReRecognitionTask = nil
    }

    func extractAudioClip(startTime: TimeInterval, endTime: TimeInterval) throws -> URL {
        guard let sessionAudio = lastSessionRecord?.audio else {
            throw DictationError.missingSessionAudio
        }

        return try audioCaptureService.extractClip(
            from: sessionAudio,
            startTime: startTime,
            endTime: endTime
        )
    }



    private func makeSessionAudioArtifact(from audioFileURL: URL) throws -> SessionAudioArtifact {
        let audioFile = try AVAudioFile(forReading: audioFileURL)
        let format = audioFile.processingFormat
        let duration = format.sampleRate > 0
            ? Double(audioFile.length) / format.sampleRate
            : 0

        return SessionAudioArtifact(
            id: UUID(),
            fileURL: audioFileURL,
            createdAt: Date(),
            sampleRate: format.sampleRate,
            channelCount: format.channelCount,
            duration: duration,
            inputDevice: nil
        )
    }

    private func scheduleReRecognition(sessionRecord: DictationSessionRecord, settings: AppSettings) {
        guard experimentPathEnabled else {
            pendingReRecognitionTask = nil
            return
        }
        guard let audio = sessionRecord.audio else { return }

        let plans = reRecognitionPlanner.makePlans(
            from: sessionRecord.transcript.segments,
            audioDuration: audio.duration
        )
        logger.logReRecognitionPlans(plans)

        guard let firstPlan = plans.first else {
            pendingReRecognitionTask = nil
            Task {
                await candidateStore.recordPlans(plans)
            }
            return
        }
        let configuration = RecognitionConfiguration(
            localeIdentifier: settings.localeIdentifier,
            contextualPhrases: correctionPipeline.customPhrases,
            addsPunctuation: true,
            requiresOnDeviceRecognition: false
        )

        let task = Task { [weak self] in
            guard let self else { return }
            await candidateStore.recordPlans(plans)
            let summary = await latestReRecognitionSummary()
            let orderingDecision = candidateResolver.makeBackendOrderingDecision(
                enabledBackends: enabledReRecognitionBackends,
                triggerFlags: firstPlan.triggerFlags,
                mode: reRecognitionOrderMode,
                sessionHints: summary.sessionBackendPreferenceHints,
                historicalHints: summary.historicalBackendPreferenceHints,
                blendedHints: summary.blendedBackendPreferenceHints
            )
            let rankedBackends = orderingDecision.rankedBackends
            let orderedBackends = rankedBackends.compactMap { entry in
                enabledReRecognitionBackends.first(where: { $0.rawValue == entry.backend })
            }
            await candidateStore.recordExecutionTrace(
                ReRecognitionExecutionTrace(
                    id: UUID(),
                    sessionID: lastSessionRecord?.id,
                    planID: firstPlan.id,
                    segmentIDs: firstPlan.segmentIDs,
                    strategyMode: orderingDecision.mode,
                    strategySource: orderingDecision.source,
                    recommendedBackend: rankedBackends.first?.backend,
                    firstTriedBackend: orderedBackends.first?.rawValue,
                    attemptedBackends: orderedBackends.map(\.rawValue),
                    backendAttemptResults: orderedBackends.map {
                        .init(
                            id: UUID(),
                            backend: $0.rawValue,
                            status: .attempted,
                            failureReason: nil,
                            attemptedAt: Date(),
                            completedAt: nil
                        )
                    },
                    createdAt: Date()
                )
            )
            self.logger.logHintDrivenBackendOrder(
                plan: firstPlan,
                strategyMode: orderingDecision.mode,
                strategySource: orderingDecision.source,
                rankedBackends: rankedBackends
            )

            for backendOption in orderedBackends {
                await self.runReRecognition(
                    plan: firstPlan,
                    audio: audio,
                    backendOption: backendOption,
                    configuration: configuration
                )
            }

            let matchingResolutions = await self.candidateComparisons(matchingSegmentIDs: firstPlan.segmentIDs)
            if let resolution = matchingResolutions.first {
                let recommendedBackend = rankedBackends.first?.backend
                await backendPreferenceHistoryStore.recordOutcome(
                    triggerFlags: firstPlan.triggerFlags.map(\.code),
                    records: resolution.sortedCandidates,
                    bestBackend: resolution.bestCandidate?.backend,
                    readyForReview: resolution.readyForReview,
                    recommendedBackend: recommendedBackend
                )
                await logCandidateStoreSnapshot()
            }
        }
        pendingReRecognitionTask = task
    }

    private func runReRecognition(
        plan: ReRecognitionPlan,
        audio: SessionAudioArtifact,
        backendOption: ReRecognitionBackendOption,
        configuration: RecognitionConfiguration
    ) async {
        await candidateStore.markBackendAttemptStarted(planID: plan.id, backend: backendOption.rawValue)
        do {
            let clipURL = try audioCaptureService.extractClip(
                from: audio,
                startTime: plan.startTime,
                endTime: plan.endTime
            )
            let backend = backendOption.makeBackend()
            let effectiveConfiguration = backendOption.effectiveConfiguration(from: configuration)
            let snapshot = try await backend.transcribeAudioFile(at: clipURL, configuration: effectiveConfiguration)
            let postProcessed = postProcessor.process(snapshot)
            let evaluation = reRecognitionEvaluator.evaluate(
                plan: plan,
                originalWindowText: plan.originalText,
                rerecognizedText: postProcessed.displayText,
                triggerFlags: plan.triggerFlags,
                backend: backend.identifier,
                sessionID: lastSessionRecord?.id
            )
            await candidateStore.record(evaluation)
            await candidateStore.markBackendAttemptSucceeded(planID: plan.id, backend: backend.identifier)
            print(
                "[ReRecognition][\(backend.identifier)] priority=\(plan.priority) " +
                "window=\(String(format: "%.2f", plan.startTime))-\(String(format: "%.2f", plan.endTime)) " +
                "original=\(plan.originalText) " +
                "rerecognized=\(postProcessed.displayText)"
            )
            await logCandidateStoreSnapshot()
            logger.logReRecognitionEvaluation(evaluation)
        } catch {
            await candidateStore.markBackendAttemptFailed(
                planID: plan.id,
                backend: backendOption.rawValue,
                failureReason: error.localizedDescription
            )
            print(
                "[ReRecognition][\(backendOption.rawValue)] failed " +
                "window=\(String(format: "%.2f", plan.startTime))-\(String(format: "%.2f", plan.endTime)) " +
                "error=\(error.localizedDescription)"
            )
        }
    }

    private func logCandidateStoreSnapshot() async {
        guard experimentPathEnabled else { return }
        let summary = await latestReRecognitionSummary()
        let comparisons = await candidateComparisonsBySegmentIDs()
        let readyForReview = comparisons.filter(\.readyForReview).count
        logger.logCandidateStoreSnapshot(
            summary: summary,
            readyForReviewCount: readyForReview,
            experimentTag: experimentTag
        )
    }

    private func awaitPendingReRecognitionIfNeeded() async {
        guard let task = pendingReRecognitionTask else { return }
        await task.value
        pendingReRecognitionTask = nil
    }
}
