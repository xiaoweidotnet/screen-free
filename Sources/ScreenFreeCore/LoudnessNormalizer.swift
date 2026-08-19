import Foundation

/// Streaming loudness normalizer for recorded audio.
///
/// The previous approach derived a gain from each callback buffer's RMS,
/// which made the result depend on buffer boundaries and capped quiet
/// microphones far below a usable loudness. This normalizer instead:
///
/// 1. Measures loudness over a sliding window of fixed-size blocks, gated
///    so silence between words neither pumps the gain up nor drags the
///    estimate down.
/// 2. Applies one smoothed long-term gain toward a target loudness. The
///    first gated signal snaps the gain immediately so recordings do not
///    start with a quiet intro, and later corrections are slew-limited.
/// 3. Protects the output with a per-sample peak limiter (instant attack,
///    exponential release) instead of a low-threshold waveshaping
///    compressor, so peaks are controlled without squashing the program
///    material below the target.
public final class LoudnessNormalizer {
    public struct Configuration: Equatable, Sendable {
        /// Linear RMS the gated program material is steered toward.
        /// 0.16 ≈ −16 dBFS RMS, in line with common voice loudness targets.
        public var targetLoudness: Float
        /// Upper bound for the long-term gain. Quieter sources stay quiet
        /// rather than boosting the noise floor without limit.
        public var maximumGain: Float
        /// Hard output ceiling enforced by the limiter.
        public var outputCeiling: Float
        /// Length of the sliding loudness window, in seconds of gated audio.
        public var windowDuration: Double
        /// Length of one measurement block, in seconds.
        public var blockDuration: Double
        /// Blocks whose RMS stays below this floor are treated as silence
        /// and do not influence the measured loudness.
        public var signalFloor: Float
        /// Smoothing time constant when the gain needs to rise.
        public var riseTimeConstant: Double
        /// Smoothing time constant when the gain needs to fall.
        public var fallTimeConstant: Double
        /// Release time of the peak limiter envelope, in seconds.
        public var limiterRelease: Double

        public init(
            targetLoudness: Float = 0.16,
            maximumGain: Float = 32,
            outputCeiling: Float = 0.95,
            windowDuration: Double = 3,
            blockDuration: Double = 0.1,
            signalFloor: Float = 0.001,
            riseTimeConstant: Double = 1,
            fallTimeConstant: Double = 0.25,
            limiterRelease: Double = 0.2
        ) {
            self.targetLoudness = targetLoudness
            self.maximumGain = maximumGain
            self.outputCeiling = outputCeiling
            self.windowDuration = windowDuration
            self.blockDuration = blockDuration
            self.signalFloor = signalFloor
            self.riseTimeConstant = riseTimeConstant
            self.fallTimeConstant = fallTimeConstant
            self.limiterRelease = limiterRelease
        }
    }

    private struct GatedBlock {
        var energy: Double
        var sampleCount: Int
    }

    public let configuration: Configuration
    public private(set) var currentGain: Float = 1

    private var gatedBlocks: [GatedBlock] = []
    private var gatedEnergyTotal: Double = 0
    private var gatedSampleTotal = 0
    private var currentBlockEnergy: Double = 0
    private var currentBlockSampleCount = 0
    private var hasSnappedInitialGain = false
    private var limiterEnvelope: Float = 0

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public func reset() {
        gatedBlocks.removeAll(keepingCapacity: true)
        gatedEnergyTotal = 0
        gatedSampleTotal = 0
        currentBlockEnergy = 0
        currentBlockSampleCount = 0
        hasSnappedInitialGain = false
        limiterEnvelope = 0
        currentGain = 1
    }

    /// Loudness of the gated sliding window, or nil until any block has
    /// carried signal above the floor. Silence keeps the last estimate.
    public var measuredLoudness: Float? {
        guard gatedSampleTotal > 0 else { return nil }
        return Float(sqrt(gatedEnergyTotal / Double(gatedSampleTotal)))
    }

    public func process(
        _ samples: UnsafeMutableBufferPointer<Float>,
        channelCount: Int,
        sampleRate: Double
    ) {
        guard !samples.isEmpty, sampleRate > 0 else { return }
        let channels = max(1, channelCount)
        let blockCapacity = max(
            channels,
            Int(configuration.blockDuration * sampleRate) * channels
        )

        var bufferEnergy: Double = 0
        for sample in samples {
            let value = Double(sample)
            bufferEnergy += value * value
            currentBlockEnergy += value * value
            currentBlockSampleCount += 1
            if currentBlockSampleCount >= blockCapacity {
                commitCurrentBlock()
            }
        }

        let bufferRMS = Float(sqrt(bufferEnergy / Double(samples.count)))
        updateGain(
            bufferRMS: bufferRMS,
            bufferDuration: Double(samples.count) / (sampleRate * Double(channels))
        )
        applyGainAndLimit(samples, sampleRate: sampleRate)
    }

    public func process(
        _ samples: inout [Float],
        channelCount: Int,
        sampleRate: Double = 48_000
    ) {
        samples.withUnsafeMutableBufferPointer {
            process($0, channelCount: channelCount, sampleRate: sampleRate)
        }
    }

    private func commitCurrentBlock() {
        defer {
            currentBlockEnergy = 0
            currentBlockSampleCount = 0
        }
        guard currentBlockSampleCount > 0 else { return }
        let blockRMS = sqrt(
            currentBlockEnergy / Double(currentBlockSampleCount)
        )
        guard blockRMS > Double(configuration.signalFloor) else { return }

        gatedBlocks.append(
            GatedBlock(
                energy: currentBlockEnergy,
                sampleCount: currentBlockSampleCount
            )
        )
        gatedEnergyTotal += currentBlockEnergy
        gatedSampleTotal += currentBlockSampleCount

        let windowBlockCount = max(
            1,
            Int(configuration.windowDuration / max(0.01, configuration.blockDuration))
        )
        while gatedBlocks.count > windowBlockCount {
            let removed = gatedBlocks.removeFirst()
            gatedEnergyTotal -= removed.energy
            gatedSampleTotal -= removed.sampleCount
        }
        if gatedSampleTotal <= 0 || gatedEnergyTotal < 0 {
            gatedEnergyTotal = gatedBlocks.reduce(0) { $0 + $1.energy }
            gatedSampleTotal = gatedBlocks.reduce(0) { $0 + $1.sampleCount }
        }
    }

    private func updateGain(bufferRMS: Float, bufferDuration: Double) {
        // Before the first gated block completes, fall back to the current
        // buffer so the opening words are boosted right away instead of
        // fading in while the window fills.
        let reference = measuredLoudness
            ?? (bufferRMS > configuration.signalFloor ? bufferRMS : nil)
        guard let reference, reference > 0 else { return }

        let desiredGain = (configuration.targetLoudness / reference)
            .clamped(to: 1...max(1, configuration.maximumGain))
        if hasSnappedInitialGain {
            let timeConstant = desiredGain < currentGain
                ? configuration.fallTimeConstant
                : configuration.riseTimeConstant
            let response = Float(
                1 - exp(-bufferDuration / max(0.001, timeConstant))
            )
            currentGain += (desiredGain - currentGain) * response
        } else {
            currentGain = desiredGain
            hasSnappedInitialGain = true
        }
    }

    private func applyGainAndLimit(
        _ samples: UnsafeMutableBufferPointer<Float>,
        sampleRate: Double
    ) {
        let ceiling = configuration.outputCeiling.clamped(to: 0.1...0.99)
        let releaseCoefficient = Float(
            exp(-1 / (max(0.01, configuration.limiterRelease) * sampleRate))
        )
        for index in samples.indices {
            let amplified = samples[index] * currentGain
            let magnitude = abs(amplified)
            limiterEnvelope = max(
                magnitude,
                limiterEnvelope * releaseCoefficient
            )
            if limiterEnvelope > ceiling {
                samples[index] = amplified * (ceiling / limiterEnvelope)
            } else {
                samples[index] = amplified
            }
        }
    }
}
