import XCTest
@testable import ScreenFreeCore

final class LoudnessNormalizerTests: XCTestCase {
    private let sampleRate: Double = 48_000

    func testVeryQuietSpeechReachesLoudnessTarget() {
        // Raw wireless-microphone levels measured in real recordings sit
        // around −48 dBFS RMS. The normalizer must be able to lift that
        // into a clearly audible range, which the old ×10 gain cap
        // could not.
        let normalizer = LoudnessNormalizer()
        var lastRMS: Float = 0
        for chunk in 0..<40 {
            var samples = makeSine(
                amplitude: 0.005_7,
                frequency: 520,
                frames: 2_400,
                phaseOffset: chunk * 2_400
            )
            normalizer.process(
                &samples,
                channelCount: 2,
                sampleRate: sampleRate
            )
            lastRMS = rms(samples)
        }
        XCTAssertGreaterThan(
            lastRMS,
            0.1,
            "−48 dBFS speech must reach at least −20 dBFS after normalization."
        )
        XCTAssertLessThanOrEqual(
            lastRMS,
            normalizer.configuration.targetLoudness * 1.1
        )
    }

    func testFirstBufferIsBoostedImmediately() {
        let normalizer = LoudnessNormalizer()
        var samples = makeSine(amplitude: 0.02, frequency: 520, frames: 2_400)
        let inputRMS = rms(samples)
        normalizer.process(&samples, channelCount: 2, sampleRate: sampleRate)
        XCTAssertGreaterThan(
            rms(samples),
            inputRMS * 3,
            "The opening words must not fade in while the window fills."
        )
    }

    func testSilenceHoldsGainWithoutPumping() {
        let normalizer = LoudnessNormalizer()
        for chunk in 0..<20 {
            var speech = makeSine(
                amplitude: 0.02,
                frequency: 520,
                frames: 2_400,
                phaseOffset: chunk * 2_400
            )
            normalizer.process(
                &speech,
                channelCount: 2,
                sampleRate: sampleRate
            )
        }
        let gainAfterSpeech = normalizer.currentGain

        var silence = [Float](repeating: 0, count: 4_800 * 20)
        normalizer.process(&silence, channelCount: 2, sampleRate: sampleRate)

        XCTAssertEqual(
            normalizer.currentGain,
            gainAfterSpeech,
            accuracy: 0.001,
            "Silence must not drive the gain toward the maximum."
        )
        XCTAssertEqual(silence.map { abs($0) }.max() ?? 0, 0)
    }

    func testLoudInputIsNotBoostedAndPeaksStayUnderCeiling() {
        let normalizer = LoudnessNormalizer()
        for chunk in 0..<20 {
            var loud = makeSine(
                amplitude: 0.9,
                frequency: 440,
                frames: 2_400,
                phaseOffset: chunk * 2_400
            )
            normalizer.process(
                &loud,
                channelCount: 2,
                sampleRate: sampleRate
            )
            XCTAssertLessThanOrEqual(
                loud.map { abs($0) }.max() ?? 0,
                normalizer.configuration.outputCeiling + 0.000_1
            )
        }
        XCTAssertEqual(normalizer.currentGain, 1, accuracy: 0.01)
    }

    func testGainFallsWhenProgramGetsLouder() {
        let normalizer = LoudnessNormalizer()
        for chunk in 0..<20 {
            var quiet = makeSine(
                amplitude: 0.005,
                frequency: 520,
                frames: 2_400,
                phaseOffset: chunk * 2_400
            )
            normalizer.process(
                &quiet,
                channelCount: 2,
                sampleRate: sampleRate
            )
        }
        let boostedGain = normalizer.currentGain
        XCTAssertGreaterThan(boostedGain, 20)

        var finalRMS: Float = 0
        for chunk in 0..<80 {
            var loud = makeSine(
                amplitude: 0.2,
                frequency: 520,
                frames: 2_400,
                phaseOffset: chunk * 2_400
            )
            normalizer.process(
                &loud,
                channelCount: 2,
                sampleRate: sampleRate
            )
            XCTAssertLessThanOrEqual(
                loud.map { abs($0) }.max() ?? 0,
                normalizer.configuration.outputCeiling + 0.000_1
            )
            finalRMS = rms(loud)
        }
        XCTAssertLessThan(normalizer.currentGain, boostedGain * 0.2)
        XCTAssertLessThanOrEqual(
            finalRMS,
            normalizer.configuration.targetLoudness * 1.6,
            "A louder passage must settle near the target instead of staying over-boosted."
        )
    }

    func testResetRestoresUnityGain() {
        let normalizer = LoudnessNormalizer()
        var samples = makeSine(amplitude: 0.01, frequency: 520, frames: 2_400)
        normalizer.process(&samples, channelCount: 2, sampleRate: sampleRate)
        XCTAssertGreaterThan(normalizer.currentGain, 1)

        normalizer.reset()

        XCTAssertEqual(normalizer.currentGain, 1)
        XCTAssertNil(normalizer.measuredLoudness)
    }

    private func makeSine(
        amplitude: Float,
        frequency: Float,
        frames: Int,
        phaseOffset: Int = 0
    ) -> [Float] {
        (0..<frames).flatMap { frame in
            let value = amplitude * sin(
                2 * Float.pi * frequency
                    * Float(frame + phaseOffset) / Float(sampleRate)
            )
            return [value, value]
        }
    }

    private func rms(_ samples: [Float]) -> Float {
        let sum = samples.reduce(0.0) {
            $0 + Double($1 * $1)
        }
        return Float(sqrt(sum / Double(max(1, samples.count))))
    }
}
