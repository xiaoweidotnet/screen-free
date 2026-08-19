import AudioToolbox
import AVFoundation
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

    func testProcessedRecordingBufferCarriesGainWithoutMutatingCaptureBuffer() throws {
        let quietSpeech = makeSine(
            amplitude: 0.025,
            frequency: 520,
            frames: 2_400
        )
        let captureBuffer = try makeFloatSampleBuffer(samples: quietSpeech)
        let processor = MicrophoneSignalProcessor(
            settings: .microphoneLoudness(
                reduceNoise: false,
                normalizeVolume: true
            )
        )

        let recordingBuffer = try XCTUnwrap(
            processor.processedSampleBuffer(captureBuffer)
        )

        XCTAssertEqual(
            try samples(from: captureBuffer),
            quietSpeech,
            "ScreenCaptureKit owns the capture buffer; enhancement must be written to a new buffer."
        )
        XCTAssertGreaterThan(
            rms(try samples(from: recordingBuffer)),
            rms(quietSpeech) * 2.5,
            "The sample buffer appended to AVAssetWriter must contain the enhanced PCM."
        )
        XCTAssertEqual(
            recordingBuffer.presentationTimeStamp,
            captureBuffer.presentationTimeStamp
        )
        XCTAssertEqual(
            CMSampleBufferGetNumSamples(recordingBuffer),
            CMSampleBufferGetNumSamples(captureBuffer)
        )
    }

    func testEnhancedMicrophoneLevelSurvivesAACEncodingAndReopen() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("microphone.m4a")
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000
            ]
        )
        XCTAssertTrue(writer.canAdd(input))
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        let inputAmplitude: Float = 0.025
        let processor = MicrophoneSignalProcessor(
            settings: .microphoneLoudness(
                reduceNoise: false,
                normalizeVolume: true
            )
        )
        let framesPerBuffer = 1_024
        for index in 0..<24 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(2))
            }
            let captureBuffer = try makeFloatSampleBuffer(
                samples: makeSine(
                    amplitude: inputAmplitude,
                    frequency: 520,
                    frames: framesPerBuffer
                ),
                presentationTimeStamp: CMTime(
                    value: Int64(index * framesPerBuffer),
                    timescale: 48_000
                )
            )
            let recordingBuffer = try XCTUnwrap(
                processor.processedSampleBuffer(captureBuffer)
            )
            XCTAssertTrue(input.append(recordingBuffer))
        }
        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting { continuation.resume() }
        }
        XCTAssertEqual(
            writer.status,
            .completed,
            writer.error?.localizedDescription ?? "AAC writer did not complete."
        )

        let decodedFile = try AVAudioFile(forReading: outputURL)
        let decodedFormat = decodedFile.processingFormat
        let decoded = try XCTUnwrap(
            AVAudioPCMBuffer(
                pcmFormat: decodedFormat,
                frameCapacity: AVAudioFrameCount(decodedFile.length)
            )
        )
        try decodedFile.read(into: decoded)
        let channelData = try XCTUnwrap(decoded.floatChannelData)
        var decodedSamples: [Float] = []
        for channel in 0..<Int(decodedFormat.channelCount) {
            decodedSamples.append(
                contentsOf: UnsafeBufferPointer(
                    start: channelData[channel],
                    count: Int(decoded.frameLength)
                )
            )
        }
        let originalRMS = inputAmplitude / sqrt(2)
        XCTAssertGreaterThan(
            rms(decodedSamples),
            originalRMS * 2.2,
            "The louder PCM must still be present after AAC encoding and reopening the real media file."
        )
        XCTAssertLessThanOrEqual(
            decodedSamples.map { abs($0) }.max() ?? 0,
            1,
            "The loudness repair must not introduce digital clipping."
        )
    }

    func testWirelessMicrophoneLevelReachesUsableLoudness() {
        // Regression: real recordings made with a wireless microphone came
        // in around −48 dBFS RMS and ended up at only ~−27 LUFS because the
        // old per-buffer AGC capped its gain at ×10. Speech this quiet must
        // still reach a clearly audible level.
        let processor = MicrophoneSignalProcessor(
            settings: .microphoneLoudness(
                reduceNoise: true,
                normalizeVolume: true
            )
        )

        var lastRMS: Float = 0
        var maximumMagnitude: Float = 0
        for chunk in 0..<40 {
            var samples = (0..<2_400).flatMap { frame -> [Float] in
                let value = 0.005_7 * sin(
                    2 * Float.pi * 520
                        * Float(frame + chunk * 2_400) / 48_000
                )
                return [value, value]
            }
            processor.process(&samples, channelCount: 2)
            lastRMS = rms(samples)
            maximumMagnitude = max(
                maximumMagnitude,
                samples.map { abs($0) }.max() ?? 0
            )
        }

        XCTAssertGreaterThan(
            lastRMS,
            0.1,
            "−48 dBFS wireless-microphone speech must be normalized into a usable loudness range."
        )
        XCTAssertLessThanOrEqual(maximumMagnitude, 0.96)
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

    func testNonInterleavedCaptureBufferIsActuallyAmplifiedOnDisk() throws {
        // SCStream's microphone output arrives as non-interleaved Float32
        // planes. The processed buffer that gets appended to the recording
        // must contain the amplified samples, not an untouched copy.
        let frames = 2_400
        let plane = (0..<frames).map { frame in
            0.01 * sin(2 * Float.pi * 440 * Float(frame) / 48_000)
        }
        let processor = MicrophoneSignalProcessor(
            settings: .microphoneLoudness(
                reduceNoise: false,
                normalizeVolume: true
            )
        )
        var boostedRMS: Float = 0
        for chunk in 0..<10 {
            let buffer = try makeNonInterleavedFloatSampleBuffer(
                planes: [plane, plane],
                presentationTimeStamp: CMTime(
                    value: CMTimeValue(chunk * frames),
                    timescale: 48_000
                )
            )
            let processed = try XCTUnwrap(
                processor.processedSampleBuffer(buffer),
                "The non-interleaved capture format must be processable."
            )
            let written = try samples(from: processed)
            XCTAssertEqual(written.count, frames * 2)
            boostedRMS = rms(written)
        }
        XCTAssertGreaterThan(
            boostedRMS,
            rms(plane) * 2,
            "Samples written to disk must carry the loudness boost."
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
        samples: [Float],
        presentationTimeStamp: CMTime = .zero
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
                presentationTimeStamp: presentationTimeStamp,
                packetDescriptions: nil,
                sampleBufferOut: &sampleBuffer
            ),
            noErr
        )
        return try XCTUnwrap(sampleBuffer)
    }

    private func makeNonInterleavedFloatSampleBuffer(
        planes: [[Float]],
        presentationTimeStamp: CMTime
    ) throws -> CMSampleBuffer {
        let channelCount = UInt32(planes.count)
        let frameCount = planes.first?.count ?? 0
        var streamDescription = AudioStreamBasicDescription(
            mSampleRate: 48_000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat
                | kAudioFormatFlagIsPacked
                | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: channelCount,
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
        let flattened = planes.flatMap { $0 }
        let byteCount = flattened.count * MemoryLayout<Float>.size
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
        let replaceStatus = flattened.withUnsafeBytes {
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
                sampleCount: frameCount,
                presentationTimeStamp: presentationTimeStamp,
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
