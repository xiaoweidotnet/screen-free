import XCTest
@testable import ScreenFree

final class AudioAnalyzerTests: XCTestCase {
    func testNearSilentNoiseFloorDoesNotNormalizeIntoVisibleAudio() {
        let waveform = AudioWaveformNormalizer.normalize(
            [0.000_001, 0.000_004, 0.000_008, 0.000_002],
            bins: 4
        )

        XCTAssertEqual(waveform, [0, 0, 0, 0])
    }

    func testSilentRangeRemainsBlankNextToAudibleAudio() {
        let waveform = AudioWaveformNormalizer.normalize(
            [0.000_008, 0.008],
            bins: 2
        )

        XCTAssertEqual(waveform, [0, 1])
    }

    func testPersistentMicrophoneNoiseFloorStaysBlankAroundSpeech() {
        let waveform = AudioWaveformNormalizer.normalize(
            [
                0.008, 0.0085, 0.009, 0.008,
                0.032, 0.05, 0.03,
                0.0085, 0.009, 0.008
            ],
            bins: 10
        )

        XCTAssertEqual(waveform[0], 0)
        XCTAssertEqual(waveform[2], 0)
        XCTAssertGreaterThan(waveform[4], 0)
        XCTAssertEqual(waveform[9], 0)
    }

    func testQuietDialogueWaveformIsNormalizedForTimelineVisibility() {
        let waveform = AudioWaveformNormalizer.normalize(
            [0, 0.000_4, 0.002, 0.008, 0.003, 0],
            bins: 6
        )

        XCTAssertEqual(waveform.count, 6)
        XCTAssertEqual(waveform.max() ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(waveform.first, 0)
        XCTAssertGreaterThan(waveform[2], 0.2)
    }

    func testRecommendedGainRaisesQuietAudioWithoutPredictingClipping() {
        let analysis = AudioAnalysis(
            waveform: [0, 1, 0],
            rms: 0.025,
            peak: 0.18
        )

        let gain = analysis.recommendedGain

        XCTAssertGreaterThan(gain, 3)
        XCTAssertLessThanOrEqual(gain * Double(analysis.peak), 0.96)
    }
}
