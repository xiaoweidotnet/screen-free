import AVFoundation
import CoreMedia
import Foundation

struct AudioAnalysis: Sendable {
    var waveform: [Float]
    var rms: Float
    var peak: Float
    var trackPeaks: [Float]
    /// Absolute (not display-normalized) peaks sampled into a shared media
    /// timeline. Each outer index matches AVAsset's audio-track order.
    var trackPeakEnvelopes: [[Float]]

    init(
        waveform: [Float],
        rms: Float,
        peak: Float,
        trackPeaks: [Float] = [],
        trackPeakEnvelopes: [[Float]] = []
    ) {
        self.waveform = waveform
        self.rms = rms
        self.peak = peak
        self.trackPeaks = trackPeaks
        self.trackPeakEnvelopes = trackPeakEnvelopes
    }

    static let empty = AudioAnalysis(
        waveform: [],
        rms: 0,
        peak: 0,
        trackPeaks: [],
        trackPeakEnvelopes: []
    )

    var recommendedGain: Double {
        guard rms > 0 else { return 1 }
        let targetRMS: Float = 0.16
        var gain = Double(targetRMS / rms)
        if peak > 0 {
            gain = min(gain, Double(0.96 / peak))
        }
        return min(4, max(0.25, gain))
    }
}

enum AudioWaveformNormalizer {
    /// RMS values below -80 dBFS are codec/noise-floor residue, not useful
    /// timeline activity. Gate them before relative normalization so a silent
    /// track cannot promote its own floor to a full-height waveform.
    static let absoluteSilenceFloor: Float = 0.000_1

    static func normalize(
        _ levels: [Float],
        bins: Int
    ) -> [Float] {
        guard !levels.isEmpty else { return [] }
        let safeBins = max(1, bins)
        let resampled = (0..<safeBins).map { bin -> Float in
            let lower = bin * levels.count / safeBins
            let upper = max(
                lower + 1,
                (bin + 1) * levels.count / safeBins
            )
            return levels[
                lower..<min(upper, levels.count)
            ].max() ?? 0
        }
        let audibleLevels = resampled
            .filter { $0.isFinite && $0 >= absoluteSilenceFloor }
            .sorted()
        guard let rawCeiling = audibleLevels.last else {
            return Array(repeating: 0, count: safeBins)
        }
        let noiseFloorIndex = min(
            audibleLevels.count - 1,
            Int(Double(audibleLevels.count - 1) * 0.2)
        )
        let estimatedNoiseFloor = audibleLevels[noiseFloorIndex]
        let adaptiveFloor: Float
        if audibleLevels.count >= 4,
           rawCeiling >= estimatedNoiseFloor * 3 {
            adaptiveFloor = max(
                absoluteSilenceFloor,
                estimatedNoiseFloor * 1.8
            )
        } else {
            // Continuous low-level music or speech has no distinct noise/voice
            // separation, so an adaptive gate would erase real content.
            adaptiveFloor = absoluteSilenceFloor
        }
        let gated = resampled.map { level -> Float in
            guard level.isFinite,
                  level >= adaptiveFloor else {
                return 0
            }
            return level
        }
        guard let ceiling = gated.max(),
              ceiling >= absoluteSilenceFloor else {
            return Array(repeating: 0, count: safeBins)
        }
        return gated.map { level in
            let normalized = max(0, min(1, level / ceiling))
            return sqrt(normalized)
        }
    }
}

struct AudioAnalyzer: Sendable {
    private struct TrackAnalysis {
        var waveform: [Float]
        var rms: Float
        var peak: Float
        var peakEnvelope: [Float]
    }

    func analyze(url: URL, bins: Int = 512) async throws -> AudioAnalysis {
        try await Task.detached(priority: .utility) {
            try await analyzeSynchronously(url: url, bins: bins)
        }.value
    }

    private func analyzeSynchronously(
        url: URL,
        bins: Int
    ) async throws -> AudioAnalysis {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { return .empty }
        let assetDuration = try await asset.load(.duration).seconds
        let safeBins = max(1, bins)

        var analyses: [TrackAnalysis] = []
        var trackPeaks: [Float] = []
        var trackPeakEnvelopes: [[Float]] = []
        for track in tracks {
            if let analysis = try analyze(
                track: track,
                asset: asset,
                bins: safeBins,
                assetDuration: assetDuration
            ) {
                analyses.append(analysis)
                trackPeaks.append(analysis.peak)
                trackPeakEnvelopes.append(analysis.peakEnvelope)
            } else {
                // Keep analysis indices aligned with AVAsset's audio-track
                // order, even when an individual track cannot be decoded.
                trackPeaks.append(0)
                trackPeakEnvelopes.append(
                    Array(repeating: 0, count: safeBins)
                )
            }
        }
        guard !analyses.isEmpty else { return .empty }

        let waveformCount = analyses.map(\.waveform.count).max() ?? 0
        let combinedWaveform = (0..<waveformCount).map { index -> Float in
            analyses.reduce(0) { partial, analysis in
                guard analysis.waveform.indices.contains(index) else {
                    return partial
                }
                return max(partial, analysis.waveform[index])
            }
        }
        let combinedRMSSquare = analyses.reduce(0.0) {
            $0 + Double($1.rms * $1.rms)
        }
        let concurrentPeak: Float
        if trackPeakEnvelopes.allSatisfy({ !$0.isEmpty }) {
            concurrentPeak = (0..<safeBins).reduce(Float.zero) {
                currentPeak, bin in
                let binSum = trackPeakEnvelopes.reduce(Float.zero) {
                    partial, envelope in
                    guard envelope.indices.contains(bin) else { return partial }
                    return partial + envelope[bin]
                }
                return max(currentPeak, binSum)
            }
        } else {
            // Without timestamps we cannot infer cross-track concurrency.
            concurrentPeak = trackPeaks.max() ?? 0
        }
        return AudioAnalysis(
            waveform: combinedWaveform,
            rms: Float(sqrt(combinedRMSSquare)),
            peak: concurrentPeak,
            trackPeaks: trackPeaks,
            trackPeakEnvelopes: trackPeakEnvelopes
        )
    }

    private func analyze(
        track: AVAssetTrack,
        asset: AVAsset,
        bins: Int,
        assetDuration: TimeInterval
    ) throws -> TrackAnalysis? {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? VideoExportError.exportFailed
        }

        var chunkLevels: [Float] = []
        var totalSquares: Double = 0
        var totalSamples = 0
        var globalPeak: Float = 0
        var peakEnvelope = Array(repeating: Float.zero, count: bins)
        var hasAlignedPeakEnvelope = true

        while let sampleBuffer = output.copyNextSampleBuffer() {
            defer { CMSampleBufferInvalidate(sampleBuffer) }
            guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                continue
            }
            var length = 0
            var pointer: UnsafeMutablePointer<Int8>?
            let status = CMBlockBufferGetDataPointer(
                block,
                atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: &length,
                dataPointerOut: &pointer
            )
            guard status == kCMBlockBufferNoErr,
                  let pointer,
                  length >= MemoryLayout<Float>.size else {
                continue
            }
            let count = length / MemoryLayout<Float>.size
            let samples = UnsafeRawPointer(pointer).bindMemory(
                to: Float.self,
                capacity: count
            )
            var chunkSquares: Double = 0
            var chunkPeak: Float = 0
            for index in 0..<count {
                let value = samples[index].isFinite ? samples[index] : 0
                chunkSquares += Double(value * value)
                chunkPeak = max(chunkPeak, abs(value))
            }
            guard count > 0 else { continue }
            totalSquares += chunkSquares
            totalSamples += count
            globalPeak = max(globalPeak, chunkPeak)
            chunkLevels.append(
                Float(sqrt(chunkSquares / Double(count)))
            )
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(
                sampleBuffer
            ).seconds
            let sampleDuration = CMSampleBufferGetDuration(sampleBuffer)
            let sampleDurationSeconds: TimeInterval
            if sampleDuration.isValid,
               sampleDuration.isNumeric,
               sampleDuration.seconds > 0 {
                sampleDurationSeconds = sampleDuration.seconds
            } else if let formatDescription = CMSampleBufferGetFormatDescription(
                sampleBuffer
            ),
            let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(
                formatDescription
            ),
            streamDescription.pointee.mSampleRate > 0 {
                sampleDurationSeconds = Double(
                    CMSampleBufferGetNumSamples(sampleBuffer)
                ) / streamDescription.pointee.mSampleRate
            } else {
                sampleDurationSeconds = 0
            }
            if presentationTime.isFinite,
               assetDuration.isFinite,
               assetDuration > 0 {
                let firstEnvelopeIndex = Int(
                    floor(
                        presentationTime.clamped(to: 0...assetDuration)
                            / assetDuration
                            * Double(bins)
                    )
                ).clamped(to: 0...(bins - 1))
                let endTime = (
                    presentationTime + max(0, sampleDurationSeconds)
                ).clamped(to: 0...assetDuration)
                let lastEnvelopeIndex = Int(
                    floor(
                        max(presentationTime, endTime - 0.000_000_1)
                            .clamped(to: 0...assetDuration)
                            / assetDuration
                            * Double(bins)
                    )
                ).clamped(to: firstEnvelopeIndex...(bins - 1))
                for envelopeIndex in firstEnvelopeIndex...lastEnvelopeIndex {
                    peakEnvelope[envelopeIndex] = max(
                        peakEnvelope[envelopeIndex],
                        chunkPeak
                    )
                }
            } else {
                // Do not line up unrelated sequential chunks from different
                // tracks. An empty envelope tells the mixer that concurrency
                // cannot be established for this media.
                hasAlignedPeakEnvelope = false
            }
        }

        guard !chunkLevels.isEmpty, totalSamples > 0 else { return nil }
        return TrackAnalysis(
            waveform: AudioWaveformNormalizer.normalize(
                chunkLevels,
                bins: bins
            ),
            rms: Float(sqrt(totalSquares / Double(totalSamples))),
            peak: globalPeak,
            peakEnvelope: hasAlignedPeakEnvelope ? peakEnvelope : []
        )
    }
}
