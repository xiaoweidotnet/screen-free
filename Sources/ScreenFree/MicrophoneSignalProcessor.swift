import AudioToolbox
import CoreMedia
import Foundation
import ScreenFreeCore

struct MicrophoneEnhancementSettings: Equatable, Sendable {
    var reduceNoise: Bool
    var normalizeVolume: Bool
    /// Linear RMS target for the gated program material. 0.16 ≈ −16 dBFS,
    /// comparable to the voice loudness other screen recorders deliver.
    var targetLoudness: Float
    var maximumGain: Float
    var outputCeiling: Float

    init(
        reduceNoise: Bool,
        normalizeVolume: Bool,
        targetLoudness: Float = 0.16,
        maximumGain: Float = 32,
        outputCeiling: Float = 0.95
    ) {
        self.reduceNoise = reduceNoise
        self.normalizeVolume = normalizeVolume
        self.targetLoudness = targetLoudness
        self.maximumGain = maximumGain
        self.outputCeiling = outputCeiling
    }

    static let disabled = MicrophoneEnhancementSettings(
        reduceNoise: false,
        normalizeVolume: false
    )

    /// System audio is usually mixed and mastered already; boost quiet
    /// material moderately and never attenuate loud content, the limiter
    /// keeps peaks under the ceiling.
    static let systemAudioLoudness = MicrophoneEnhancementSettings(
        reduceNoise: false,
        normalizeVolume: true,
        targetLoudness: 0.16,
        maximumGain: 8,
        outputCeiling: 0.95
    )

    /// Microphones (especially wireless receivers) can deliver very low
    /// raw levels, so speech needs far more available gain than system
    /// audio to reach the loudness target.
    static func microphoneLoudness(
        reduceNoise: Bool,
        normalizeVolume: Bool
    ) -> MicrophoneEnhancementSettings {
        MicrophoneEnhancementSettings(
            reduceNoise: reduceNoise,
            normalizeVolume: normalizeVolume,
            targetLoudness: 0.16,
            maximumGain: 32,
            outputCeiling: 0.95
        )
    }

    var isEnabled: Bool {
        reduceNoise || normalizeVolume
    }

    var normalizerConfiguration: LoudnessNormalizer.Configuration {
        LoudnessNormalizer.Configuration(
            targetLoudness: targetLoudness,
            maximumGain: maximumGain,
            outputCeiling: outputCeiling
        )
    }
}

final class MicrophoneSignalProcessor: @unchecked Sendable {
    private let settings: MicrophoneEnhancementSettings
    private var previousInput: [Float] = []
    private var previousOutput: [Float] = []
    /// One normalizer per channel-plane offset so non-interleaved layouts
    /// keep independent state, mirroring the filter state arrays above.
    private var normalizers: [Int: LoudnessNormalizer] = [:]

    init(settings: MicrophoneEnhancementSettings) {
        self.settings = settings
    }

    func reset() {
        previousInput.removeAll(keepingCapacity: true)
        previousOutput.removeAll(keepingCapacity: true)
        normalizers.values.forEach { $0.reset() }
    }

    private func normalizer(forChannelOffset offset: Int) -> LoudnessNormalizer {
        if let existing = normalizers[offset] { return existing }
        let created = LoudnessNormalizer(
            configuration: settings.normalizerConfiguration
        )
        normalizers[offset] = created
        return created
    }

    /// Returns the buffer that should be appended to `AVAssetWriter`.
    ///
    /// ScreenCaptureKit owns its callback buffer. Asking Core Media for an
    /// aligned `AudioBufferList` is allowed to return copied storage, so
    /// mutating that list and then appending the original sample buffer can
    /// silently discard every enhancement. Build an owned PCM buffer first,
    /// process that buffer, and append the returned sample buffer instead.
    func processedSampleBuffer(
        _ captureBuffer: CMSampleBuffer
    ) -> CMSampleBuffer? {
        guard settings.isEnabled else { return captureBuffer }
        guard let formatDescription = CMSampleBufferGetFormatDescription(
                  captureBuffer
              ),
              let streamDescription =
                  CMAudioFormatDescriptionGetStreamBasicDescription(
                      formatDescription
                  )?.pointee,
              streamDescription.mFormatID == kAudioFormatLinearPCM,
              let copiedData = copiedAudioData(from: captureBuffer) else {
            return nil
        }

        var recordingBuffer: CMSampleBuffer?
        let status = CMAudioSampleBufferCreateWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: copiedData,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: CMSampleBufferGetNumSamples(captureBuffer),
            presentationTimeStamp: captureBuffer.presentationTimeStamp,
            packetDescriptions: nil,
            sampleBufferOut: &recordingBuffer
        )
        guard status == noErr, let recordingBuffer,
              process(recordingBuffer) else {
            return nil
        }
        return recordingBuffer
    }

    @discardableResult
    func process(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard settings.isEnabled,
              let formatDescription = CMSampleBufferGetFormatDescription(
                  sampleBuffer
              ),
              let streamDescription =
                  CMAudioFormatDescriptionGetStreamBasicDescription(
                      formatDescription
                  )?.pointee,
              streamDescription.mFormatID == kAudioFormatLinearPCM else {
            return false
        }

        var requiredSize = 0
        var retainedBlockBuffer: CMBlockBuffer?
        let flags = UInt32(
            kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment
        )
        let sizeStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &requiredSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: flags,
            blockBufferOut: &retainedBlockBuffer
        )
        guard sizeStatus == noErr, requiredSize > 0 else {
            return false
        }

        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: requiredSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { storage.deallocate() }
        let audioBufferList = storage.bindMemory(
            to: AudioBufferList.self,
            capacity: 1
        )
        let listStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferList,
            bufferListSize: requiredSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: flags,
            blockBufferOut: &retainedBlockBuffer
        )
        guard listStatus == noErr else { return false }

        let audioBuffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let isFloat = streamDescription.mFormatFlags
            & kAudioFormatFlagIsFloat != 0
        let isSignedInteger = streamDescription.mFormatFlags
            & kAudioFormatFlagIsSignedInteger != 0
        let isNonInterleaved = streamDescription.mFormatFlags
            & kAudioFormatFlagIsNonInterleaved != 0
        let nominalChannels = max(
            1,
            Int(streamDescription.mChannelsPerFrame)
        )
        var processed = false

        for (index, audioBuffer) in audioBuffers.enumerated() {
            guard let data = audioBuffer.mData else { continue }
            let channelCount = isNonInterleaved
                ? 1
                : max(1, Int(audioBuffer.mNumberChannels) == 0
                    ? nominalChannels
                    : Int(audioBuffer.mNumberChannels))
            let channelOffset = isNonInterleaved ? index : 0

            if isFloat, streamDescription.mBitsPerChannel == 32 {
                let count = Int(audioBuffer.mDataByteSize)
                    / MemoryLayout<Float>.size
                let pointer = data.bindMemory(to: Float.self, capacity: count)
                process(
                    UnsafeMutableBufferPointer(start: pointer, count: count),
                    channelCount: channelCount,
                    channelOffset: channelOffset,
                    sampleRate: streamDescription.mSampleRate
                )
                processed = true
            } else if isSignedInteger,
                      streamDescription.mBitsPerChannel == 16 {
                let count = Int(audioBuffer.mDataByteSize)
                    / MemoryLayout<Int16>.size
                let pointer = data.bindMemory(to: Int16.self, capacity: count)
                var floating = (0..<count).map {
                    Float(pointer[$0]) / Float(Int16.max)
                }
                floating.withUnsafeMutableBufferPointer {
                    process(
                        $0,
                        channelCount: channelCount,
                        channelOffset: channelOffset,
                        sampleRate: streamDescription.mSampleRate
                    )
                }
                for sampleIndex in 0..<count {
                    let scaled = floating[sampleIndex]
                        .clamped(to: -1...1)
                        * Float(Int16.max)
                    pointer[sampleIndex] = Int16(scaled.rounded())
                }
                processed = true
            }
        }
        return processed
    }

    private func copiedAudioData(
        from sampleBuffer: CMSampleBuffer
    ) -> CMBlockBuffer? {
        if let source = CMSampleBufferGetDataBuffer(sampleBuffer) {
            let length = CMBlockBufferGetDataLength(source)
            guard length > 0,
                  let destination = makeBlockBuffer(length: length) else {
                return nil
            }
            var bytes = [UInt8](repeating: 0, count: length)
            guard bytes.withUnsafeMutableBytes({ rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else {
                    return false
                }
                return CMBlockBufferCopyDataBytes(
                    source,
                    atOffset: 0,
                    dataLength: length,
                    destination: baseAddress
                ) == kCMBlockBufferNoErr
            }),
                bytes.withUnsafeBytes({ rawBuffer in
                    guard let baseAddress = rawBuffer.baseAddress else {
                        return false
                    }
                    return CMBlockBufferReplaceDataBytes(
                        with: baseAddress,
                        blockBuffer: destination,
                        offsetIntoDestination: 0,
                        dataLength: length
                    ) == kCMBlockBufferNoErr
                }) else {
                return nil
            }
            return destination
        }

        var requiredSize = 0
        var retainedBlockBuffer: CMBlockBuffer?
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &requiredSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &retainedBlockBuffer
        ) == noErr,
            requiredSize > 0 else {
            return nil
        }

        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: requiredSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { storage.deallocate() }
        let list = storage.bindMemory(to: AudioBufferList.self, capacity: 1)
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: list,
            bufferListSize: requiredSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &retainedBlockBuffer
        ) == noErr else {
            return nil
        }

        let buffers = UnsafeMutableAudioBufferListPointer(list)
        let totalLength = buffers.reduce(0) {
            $0 + Int($1.mDataByteSize)
        }
        guard totalLength > 0,
              let destination = makeBlockBuffer(length: totalLength) else {
            return nil
        }
        var offset = 0
        for buffer in buffers {
            let length = Int(buffer.mDataByteSize)
            guard let data = buffer.mData,
                  CMBlockBufferReplaceDataBytes(
                      with: data,
                      blockBuffer: destination,
                      offsetIntoDestination: offset,
                      dataLength: length
                  ) == kCMBlockBufferNoErr else {
                return nil
            }
            offset += length
        }
        return destination
    }

    private func makeBlockBuffer(length: Int) -> CMBlockBuffer? {
        var blockBuffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: length,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: length,
            flags: 0,
            blockBufferOut: &blockBuffer
        ) == kCMBlockBufferNoErr else {
            return nil
        }
        return blockBuffer
    }

    func process(
        _ samples: inout [Float],
        channelCount: Int,
        sampleRate: Double = 48_000
    ) {
        samples.withUnsafeMutableBufferPointer {
            process(
                $0,
                channelCount: max(1, channelCount),
                channelOffset: 0,
                sampleRate: sampleRate
            )
        }
    }

    private func process(
        _ samples: UnsafeMutableBufferPointer<Float>,
        channelCount: Int,
        channelOffset: Int,
        sampleRate: Double
    ) {
        guard settings.isEnabled, !samples.isEmpty else { return }
        let stateCount = channelOffset + channelCount
        if previousInput.count < stateCount {
            previousInput.append(
                contentsOf: repeatElement(
                    0,
                    count: stateCount - previousInput.count
                )
            )
            previousOutput.append(
                contentsOf: repeatElement(
                    0,
                    count: stateCount - previousOutput.count
                )
            )
        }

        if settings.reduceNoise {
            let cutoff: Float = 80
            let delta = Float(1 / max(8_000, sampleRate))
            let rc = 1 / (2 * Float.pi * cutoff)
            let alpha = rc / (rc + delta)
            for index in samples.indices {
                let channel = channelOffset + index % channelCount
                let input = samples[index]
                let output = alpha
                    * (previousOutput[channel]
                        + input
                        - previousInput[channel])
                previousInput[channel] = input
                previousOutput[channel] = output
                samples[index] = output
            }
        }

        if settings.normalizeVolume {
            normalizer(forChannelOffset: channelOffset).process(
                samples,
                channelCount: channelCount,
                sampleRate: sampleRate
            )
        }

        if settings.reduceNoise {
            // Expand only after automatic gain. The old fixed -44 dBFS gate
            // ran first and could turn a valid weak voice into near-silence
            // before the normalizer had a chance to raise it.
            let gateThreshold: Float
            if settings.normalizeVolume {
                let inputFloor: Float = 0.000_3
                let appliedGain = normalizers[channelOffset]?.currentGain ?? 1
                gateThreshold = (
                    inputFloor * appliedGain
                ).clamped(to: 0.000_3...0.004)
            } else {
                gateThreshold = 0.006
            }
            let rms = rootMeanSquare(samples)
            if rms < gateThreshold {
                let ratio = (rms / gateThreshold).clamped(to: 0...1)
                let attenuation = max(0.08, ratio * ratio)
                for index in samples.indices {
                    samples[index] *= attenuation
                }
            }
        }
    }

    private func rootMeanSquare(
        _ samples: UnsafeMutableBufferPointer<Float>
    ) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Double = 0
        for sample in samples {
            let value = Double(sample)
            sum += value * value
        }
        return Float(sqrt(sum / Double(samples.count)))
    }
}
