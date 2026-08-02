import AudioToolbox
import CoreMedia
import XCTest
@testable import ScreenFree

final class MicrophoneSignalProcessorTests: XCTestCase {
    func testNoiseReductionAndNormalizationReachPCMRecordingBuffer() throws {
        var disabledSamples = makeSine(
            amplitude: 0.02,
            frequency: 1_000,
            frames: 2_400
        )
        let original = disabledSamples
        MicrophoneSignalProcessor(settings: .disabled).process(
            &disabledSamples,
            channelCount: 2
        )
        XCTAssertEqual(disabledSamples, original)

        var lowNoise = Array(repeating: Float(0.003), count: 4_800)
        let noiseInputRMS = rms(lowNoise)
        MicrophoneSignalProcessor(
            settings: MicrophoneEnhancementSettings(
                reduceNoise: true,
                normalizeVolume: false
            )
        ).process(&lowNoise, channelCount: 2)
        XCTAssertLessThan(rms(lowNoise), noiseInputRMS * 0.2)

        let quietVoice = makeSine(
            amplitude: 0.02,
            frequency: 1_000,
            frames: 2_400
        )
        let sampleBuffer = try makeFloatSampleBuffer(samples: quietVoice)
        let processor = MicrophoneSignalProcessor(
            settings: MicrophoneEnhancementSettings(
                reduceNoise: false,
                normalizeVolume: true
            )
        )
        XCTAssertTrue(processor.process(sampleBuffer))
        let normalizedVoice = try samples(from: sampleBuffer)
        XCTAssertGreaterThan(rms(normalizedVoice), rms(quietVoice) * 1.5)
        XCTAssertLessThanOrEqual(
            normalizedVoice.map { abs($0) }.max() ?? 0,
            0.98
        )

        var loudVoice = makeSine(
            amplitude: 1.2,
            frequency: 440,
            frames: 2_400
        )
        MicrophoneSignalProcessor(
            settings: MicrophoneEnhancementSettings(
                reduceNoise: false,
                normalizeVolume: true
            )
        ).process(&loudVoice, channelCount: 2)
        XCTAssertLessThanOrEqual(
            loudVoice.map { abs($0) }.max() ?? 0,
            0.98
        )
    }

    func testSystemAudioLoudnessRaisesDialogueAndSoftLimitsPeaks() {
        var quietDialogue = makeSine(
            amplitude: 0.04,
            frequency: 700,
            frames: 2_400
        )
        let originalRMS = rms(quietDialogue)
        let processor = MicrophoneSignalProcessor(
            settings: .systemAudioLoudness
        )

        processor.process(&quietDialogue, channelCount: 2)

        XCTAssertGreaterThanOrEqual(
            rms(quietDialogue),
            originalRMS * 3,
            "Recorded system audio should be immediately about 3–4× louder."
        )
        XCTAssertLessThanOrEqual(
            quietDialogue.map { abs($0) }.max() ?? 0,
            0.96
        )

        var transient = [Float](repeating: 0, count: 4_800)
        transient[100] = 1.4
        transient[101] = -1.4
        processor.process(&transient, channelCount: 2)

        XCTAssertLessThanOrEqual(
            transient.map { abs($0) }.max() ?? 0,
            0.96,
            "The louder profile must compress peaks instead of clipping."
        )
    }

    func testMicrophoneLoudnessMakesQuietSpeechClearlyAudible() {
        var quietSpeech = makeSine(
            amplitude: 0.025,
            frequency: 520,
            frames: 2_400
        )
        let originalRMS = rms(quietSpeech)
        let processor = MicrophoneSignalProcessor(
            settings: .microphoneLoudness(
                reduceNoise: false,
                normalizeVolume: true
            )
        )

        processor.process(&quietSpeech, channelCount: 2)

        XCTAssertGreaterThan(rms(quietSpeech), originalRMS * 2.5)
        XCTAssertLessThanOrEqual(
            quietSpeech.map { abs($0) }.max() ?? 0,
            0.96
        )
    }

    func testNoiseReductionDoesNotSwallowWeakSpeechBeforeNormalization() {
        var weakSpeech = makeSine(
            amplitude: 0.002,
            frequency: 520,
            frames: 2_400
        )
        let originalRMS = rms(weakSpeech)
        let processor = MicrophoneSignalProcessor(
            settings: .microphoneLoudness(
                reduceNoise: true,
                normalizeVolume: true
            )
        )

        processor.process(&weakSpeech, channelCount: 2)

        XCTAssertGreaterThan(
            rms(weakSpeech),
            originalRMS * 1.5,
            "A weak but coherent voice must reach automatic gain before the silence expander."
        )
        XCTAssertLessThanOrEqual(
            weakSpeech.map { abs($0) }.max() ?? 0,
            0.96
        )
    }

    private func makeSine(
        amplitude: Float,
        frequency: Float,
        frames: Int
    ) -> [Float] {
        (0..<frames).flatMap { frame in
            let value = amplitude * sin(
                2 * Float.pi * frequency * Float(frame) / 48_000
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

    private func makeFloatSampleBuffer(
        samples: [Float]
    ) throws -> CMSampleBuffer {
        var streamDescription = AudioStreamBasicDescription(
            mSampleRate: 48_000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat
                | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8,
            mFramesPerPacket: 1,
            mBytesPerFrame: 8,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        var formatDescription: CMAudioFormatDescription?
        XCTAssertEqual(
            CMAudioFormatDescriptionCreate(
                allocator: kCFAllocatorDefault,
                asbd: &streamDescription,
                layoutSize: 0,
                layout: nil,
                magicCookieSize: 0,
                magicCookie: nil,
                extensions: nil,
                formatDescriptionOut: &formatDescription
            ),
            noErr
        )
        let format = try XCTUnwrap(formatDescription)
        let byteCount = samples.count * MemoryLayout<Float>.size
        var blockBuffer: CMBlockBuffer?
        XCTAssertEqual(
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: byteCount,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: byteCount,
                flags: 0,
                blockBufferOut: &blockBuffer
            ),
            kCMBlockBufferNoErr
        )
        let block = try XCTUnwrap(blockBuffer)
        let replaceStatus = samples.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(
                with: $0.baseAddress!,
                blockBuffer: block,
                offsetIntoDestination: 0,
                dataLength: byteCount
            )
        }
        XCTAssertEqual(replaceStatus, kCMBlockBufferNoErr)

        var sampleBuffer: CMSampleBuffer?
        XCTAssertEqual(
            CMAudioSampleBufferCreateWithPacketDescriptions(
                allocator: kCFAllocatorDefault,
                dataBuffer: block,
                dataReady: true,
                makeDataReadyCallback: nil,
                refcon: nil,
                formatDescription: format,
                sampleCount: samples.count / 2,
                presentationTimeStamp: .zero,
                packetDescriptions: nil,
                sampleBufferOut: &sampleBuffer
            ),
            noErr
        )
        return try XCTUnwrap(sampleBuffer)
    }

    private func samples(
        from sampleBuffer: CMSampleBuffer
    ) throws -> [Float] {
        let block = try XCTUnwrap(
            CMSampleBufferGetDataBuffer(sampleBuffer)
        )
        let length = CMBlockBufferGetDataLength(block)
        var result = Array(
            repeating: Float.zero,
            count: length / MemoryLayout<Float>.size
        )
        let status = result.withUnsafeMutableBytes {
            CMBlockBufferCopyDataBytes(
                block,
                atOffset: 0,
                dataLength: length,
                destination: $0.baseAddress!
            )
        }
        XCTAssertEqual(status, kCMBlockBufferNoErr)
        return result
    }
}
