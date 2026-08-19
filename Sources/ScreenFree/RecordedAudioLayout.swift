import Foundation

struct RecordedAudioLayout: Codable, Equatable, Sendable {
    var systemTrackIndex: Int?
    var microphoneTrackIndex: Int?

    var hasSystemAudio: Bool {
        systemTrackIndex != nil
    }

    var hasMicrophone: Bool {
        microphoneTrackIndex != nil
    }

    static func recording(
        systemAudioMode: SystemAudioCaptureMode,
        recordMicrophone: Bool
    ) -> RecordedAudioLayout {
        switch (systemAudioMode, recordMicrophone) {
        case (.all, false), (.selected, false):
            return RecordedAudioLayout(
                systemTrackIndex: 0,
                microphoneTrackIndex: nil
            )
        case (.all, true):
            return RecordedAudioLayout(
                systemTrackIndex: 0,
                microphoneTrackIndex: 1
            )
        case (.selected, true):
            // The microphone is written into the primary recording. Selected
            // application audio is captured separately and appended by
            // RecordingAudioMixer.
            return RecordedAudioLayout(
                systemTrackIndex: 1,
                microphoneTrackIndex: 0
            )
        case (.off, true):
            return RecordedAudioLayout(
                systemTrackIndex: nil,
                microphoneTrackIndex: 0
            )
        case (.off, false):
            return RecordedAudioLayout(
                systemTrackIndex: nil,
                microphoneTrackIndex: nil
            )
        }
    }
}

struct RecordedAudioMixStyle: Sendable {
    var layout: RecordedAudioLayout
    var systemVolume: Double
    var microphoneVolume: Double
    var microphoneMuted: Bool
    var trackPeaks: [Float] = []
    var trackPeakEnvelopes: [[Float]] = []
    /// Gated per-track RMS from AudioAnalyzer. Enables automatic loudness
    /// repair for recordings whose raw capture level is far below target.
    var trackLoudness: [Float] = []

    private static let audiblePeakFloor: Double = 0.001
    private static let targetCombinedPeak = pow(10, -1.0 / 20)
    private static let maximumBoostedCombinedPeak = pow(10, -0.05 / 20)
    /// Program material this loud (-16 dBFS gated RMS) already sits at a
    /// comfortable editing loudness and receives no automatic makeup.
    private static let loudnessTarget: Double = 0.16
    private static let maximumMicrophoneMakeupGain: Double = 16
    private static let maximumSystemMakeupGain: Double = 4
    private static let maximumResolvedGain: Double = 16

    /// Boost-only gain that lifts quiet program material toward the loudness
    /// target. Capped so the track's own peak cannot exceed the combined-peak
    /// target: loudness repair must never introduce clipping.
    private func loudnessMakeupGain(forTrackAt index: Int) -> Double {
        guard trackLoudness.indices.contains(index) else { return 1 }
        let loudness = Double(trackLoudness[index])
        guard loudness.isFinite,
              loudness > 0.000_1 else {
            return 1
        }
        let maximumMakeup = layout.microphoneTrackIndex == index
            ? Self.maximumMicrophoneMakeupGain
            : Self.maximumSystemMakeupGain
        let desired = (Self.loudnessTarget / loudness)
            .clamped(to: 1...maximumMakeup)
        let peak = absolutePeak(forTrackAt: index)
        guard peak >= Self.audiblePeakFloor else { return 1 }
        return min(desired, max(1, Self.targetCombinedPeak / peak))
    }

    private func baseGain(forTrackAt index: Int) -> Double {
        if layout.systemTrackIndex == index {
            return systemVolume.clamped(to: 0...2)
                * loudnessMakeupGain(forTrackAt: index)
        }
        if layout.microphoneTrackIndex == index {
            return microphoneMuted
                ? 0
                : microphoneVolume.clamped(to: 0...2)
                    * loudnessMakeupGain(forTrackAt: index)
        }
        return 1
    }

    private var roleIndices: [Int] {
        Array(Set([
            layout.systemTrackIndex,
            layout.microphoneTrackIndex
        ].compactMap { $0 })).sorted()
    }

    private func absolutePeak(forTrackAt index: Int) -> Double {
        let envelopePeak = trackPeakEnvelopes.indices.contains(index)
            ? trackPeakEnvelopes[index]
                .filter { $0.isFinite }
                .max()
                .map(Double.init) ?? 0
            : 0
        let analyzedPeak = trackPeaks.indices.contains(index)
            && trackPeaks[index].isFinite
            ? Double(trackPeaks[index])
            : 0
        return max(0, max(envelopePeak, analyzedPeak))
    }

    private var audibleRoleIndices: [Int] {
        roleIndices.filter { index in
            baseGain(forTrackAt: index) > 0
                && absolutePeak(forTrackAt: index) >= Self.audiblePeakFloor
        }
    }

    /// Returns the maximum sum for peaks that occur in the same media-time
    /// bin. Global per-track peaks are intentionally not used here: peaks at
    /// different times cannot clip the mix together.
    private func concurrentPeakAtUnity() -> Double? {
        let audibleIndices = audibleRoleIndices
        guard audibleIndices.count > 1,
              audibleIndices.allSatisfy({ index in
                  trackPeakEnvelopes.indices.contains(index)
                      && !trackPeakEnvelopes[index].isEmpty
              }) else {
            return nil
        }
        let binCount = audibleIndices.reduce(0) { count, index in
            max(count, trackPeakEnvelopes[index].count)
        }
        guard binCount > 0 else { return nil }

        return (0..<binCount).reduce(0) { maximum, bin in
            let simultaneousSum = audibleIndices.reduce(0) {
                partial, index in
                let envelope = trackPeakEnvelopes[index]
                let sourceBin = min(
                    envelope.count - 1,
                    bin * envelope.count / binCount
                )
                let peak = Double(envelope[sourceBin])
                guard peak.isFinite else { return partial }
                return partial
                    + max(0, peak) * baseGain(forTrackAt: index)
            }
            return max(maximum, simultaneousSum)
        }
    }

    private func combinedPeakCeiling(clipVolume: Double) -> Double {
        let boostProgress = (
            (clipVolume.clamped(to: 0...4) - 1) / 1
        ).clamped(to: 0...1)
        return Self.targetCombinedPeak
            + (
                Self.maximumBoostedCombinedPeak
                    - Self.targetCombinedPeak
            ) * boostProgress
    }

    private func sharedHeadroom(clipVolume: Double) -> Double {
        guard let concurrentPeak = concurrentPeakAtUnity() else { return 1 }
        let safeClipVolume = clipVolume.clamped(to: 0...4)
        let predictedPeak = concurrentPeak * safeClipVolume
        let ceiling = combinedPeakCeiling(clipVolume: safeClipVolume)
        guard predictedPeak > ceiling else { return 1 }
        return ceiling / predictedPeak
    }

    private func resolvedGain(
        forTrackAt index: Int,
        clipVolume: Double
    ) -> Double {
        let safeClipVolume = clipVolume.clamped(to: 0...4)
        let requestedGain = baseGain(forTrackAt: index) * safeClipVolume
        let audibleIndices = audibleRoleIndices

        if audibleIndices.count == 1,
           audibleIndices[0] == index {
            let peak = absolutePeak(forTrackAt: index)
            guard requestedGain > 1,
                  peak >= Self.audiblePeakFloor else {
                return requestedGain.clamped(to: 0...Self.maximumResolvedGain)
            }
            return min(
                requestedGain,
                max(1, Self.targetCombinedPeak / peak)
            ).clamped(to: 0...Self.maximumResolvedGain)
        }

        return (
            requestedGain * sharedHeadroom(clipVolume: safeClipVolume)
        ).clamped(to: 0...Self.maximumResolvedGain)
    }

    func gain(forTrackAt index: Int) -> Double {
        resolvedGain(forTrackAt: index, clipVolume: 1)
    }

    func gain(
        forTrackAt index: Int,
        clipVolume: Double
    ) -> Double {
        resolvedGain(forTrackAt: index, clipVolume: clipVolume)
    }
}
