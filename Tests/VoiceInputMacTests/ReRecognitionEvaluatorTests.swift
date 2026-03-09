import XCTest
@testable import VoiceInputMac

final class ReRecognitionEvaluatorTests: XCTestCase {
    func testEnglishSingleWordCandidateScoresLowerThanStableChinese() {
        let baseline = evaluateScore(candidate: "语音转写成文字")
        let englishSingleWord = evaluateScore(candidate: "you")

        XCTAssertGreaterThan(baseline, englishSingleWord)
    }

    func testEnglishSingleWordIsPenalizedInShortChineseWindow() {
        let baseline = evaluateScore(candidate: "已经转写成文", originalText: "转写成")
        let englishSingleWord = evaluateScore(candidate: "you", originalText: "转写成")

        XCTAssertGreaterThan(baseline, englishSingleWord)
        XCTAssertLessThan(englishSingleWord, 0)
    }

    func testChineseVariantCandidatesScoreLowerThanStableChinese() {
        let baseline = evaluateScore(candidate: "语音转写成文字")
        let simplifiedVariant = evaluateScore(candidate: "已经转写成文字")
        let weakenedVariant = evaluateScore(candidate: "已转写成文字。")
        let traditionalVariant = evaluateScore(candidate: "已經轉寫成文字了")
        let confusableVariant = evaluateScore(candidate: "已應轉寫成文字。")

        XCTAssertGreaterThanOrEqual(baseline, simplifiedVariant)
        XCTAssertGreaterThan(baseline, weakenedVariant)
        XCTAssertGreaterThanOrEqual(simplifiedVariant, weakenedVariant)
        XCTAssertGreaterThan(simplifiedVariant, traditionalVariant)
        XCTAssertGreaterThan(simplifiedVariant, confusableVariant)
        XCTAssertLessThan(traditionalVariant, 0)
        XCTAssertLessThan(confusableVariant, 0)
    }

    func testWeakenedChinesePrefixScoresLowerThanTruncatedChineseVariantInShortWindow() {
        let truncatedVariant = evaluateScore(candidate: "已经转写成文", originalText: "转写成")
        let weakenedVariant = evaluateScore(candidate: "已转写成文字。", originalText: "转写成")

        XCTAssertGreaterThan(truncatedVariant, weakenedVariant)
        XCTAssertLessThan(weakenedVariant, 0)
    }

    func testTraditionalCompletePhraseScoresHigherThanTruncatedSimplifiedVariant() {
        let traditionalComplete = evaluateScore(candidate: "轉寫成文字", originalText: "转写成")
        let truncatedSimplified = evaluateScore(candidate: "转写成文", originalText: "转写成")

        XCTAssertGreaterThan(traditionalComplete, truncatedSimplified)
    }

    private func evaluateScore(
        candidate: String,
        originalText: String = "语音转写成文字"
    ) -> Int {
        let evaluator = ReRecognitionEvaluator(
            correctionPipeline: TextCorrectionPipeline(settings: AppSettings())
        )
        let plan = ReRecognitionPlan(
            id: "test-plan",
            segmentIDs: ["segment-1"],
            originalText: originalText,
            startTime: 0,
            endTime: 1,
            triggerFlags: [],
            priority: 1,
            reasons: ["test"]
        )

        return evaluator.evaluate(
            plan: plan,
            originalWindowText: plan.originalText,
            rerecognizedText: candidate,
            triggerFlags: [],
            backend: "test.backend",
            sessionID: nil
        ).score
    }
}
