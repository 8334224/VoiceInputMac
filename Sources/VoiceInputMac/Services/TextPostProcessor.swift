import Foundation

protocol TextPostProcessor {
    func process(_ snapshot: RecognitionResultSnapshot) -> RecognitionResultSnapshot
}

struct BasicTextPostProcessor: TextPostProcessor {
    let correctionPipeline: TextCorrectionPipeline

    func process(_ snapshot: RecognitionResultSnapshot) -> RecognitionResultSnapshot {
        let processedSegments = snapshot.segments.map { segment in
            TranscriptSegment(
                id: segment.id,
                text: correctionPipeline.applyLocalCorrections(to: segment.text),
                startTime: segment.startTime,
                endTime: segment.endTime,
                isFinal: segment.isFinal,
                source: segment.source,
                suspicionFlags: segment.suspicionFlags
            )
        }

        return RecognitionResultSnapshot(
            rawText: snapshot.rawText,
            displayText: correctionPipeline.applyLocalCorrections(to: snapshot.rawText),
            segments: processedSegments,
            isFinal: snapshot.isFinal,
            source: snapshot.source
        )
    }
}
