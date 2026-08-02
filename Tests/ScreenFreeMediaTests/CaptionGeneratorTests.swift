import Speech
import XCTest
@testable import ScreenFree

final class CaptionGeneratorTests: XCTestCase {
    func testVocabularyIsSanitizedAndAppliedToOnDeviceRequest() {
        let longPhrase = String(repeating: "术", count: 100)
        let raw = """
        ScreenFree, AVFoundation
        screenfree；\(longPhrase)
        , ,
        """
        let context = CaptionRecognitionContext(rawText: raw)
        XCTAssertEqual(context.phrases.count, 3)
        XCTAssertEqual(context.phrases[0], "ScreenFree")
        XCTAssertEqual(context.phrases[1], "AVFoundation")
        XCTAssertEqual(
            context.phrases[2].count,
            CaptionRecognitionContext.maximumPhraseLength
        )

        let request = CaptionGenerator.makeRequest(
            from: URL(fileURLWithPath: "/tmp/screenfree-caption-test.m4a"),
            vocabulary: raw
        )
        XCTAssertTrue(request.requiresOnDeviceRecognition)
        XCTAssertFalse(request.shouldReportPartialResults)
        XCTAssertEqual(request.taskHint, .dictation)
        XCTAssertEqual(request.contextualStrings, context.phrases)

        let overflow = (0..<120).map { "term-\($0)" }.joined(separator: ",")
        XCTAssertEqual(
            CaptionRecognitionContext(rawText: overflow).phrases.count,
            CaptionRecognitionContext.maximumPhraseCount
        )
    }
}
