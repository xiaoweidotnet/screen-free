import CoreGraphics
import Foundation
import ScreenFreeCore

struct TimelineWaveformBar: Equatable, Sendable {
    var x: CGFloat
    var halfHeight: CGFloat
}

enum TimelineWaveformGeometry {
    static func bars(
        samples: [Float],
        sourceDuration: TimeInterval,
        clip: TimelineClip,
        canvasSize: CGSize
    ) -> [TimelineWaveformBar] {
        guard !samples.isEmpty,
              sourceDuration > 0,
              clip.duration > 0,
              canvasSize.width > 0,
              canvasSize.height > 0 else {
            return []
        }

        let visibleSourceStart = clip.sourceStart.clamped(
            to: 0...sourceDuration
        )
        let visibleSourceEnd = clip.sourceEnd.clamped(
            to: 0...sourceDuration
        )
        guard visibleSourceEnd > visibleSourceStart else {
            return []
        }

        // One bar every 2 points keeps the waveform fine-grained enough to
        // read like a real amplitude envelope instead of a coarse histogram.
        // The 2000-bar cap keeps deeply zoomed-in clips from building paths
        // with tens of thousands of strokes.
        let barCount = min(
            2000,
            max(1, Int(canvasSize.width / 2))
        )
        return (0..<barCount).compactMap { barIndex in
            let lowerProgress = Double(barIndex) / Double(barCount)
            let upperProgress = Double(barIndex + 1) / Double(barCount)
            let sampleStart = visibleSourceStart
                + (visibleSourceEnd - visibleSourceStart) * lowerProgress
            let sampleEnd = visibleSourceStart
                + (visibleSourceEnd - visibleSourceStart) * upperProgress
            let lowerIndex = min(
                samples.count - 1,
                max(
                    0,
                    Int(
                        floor(
                            sampleStart / sourceDuration
                                * Double(samples.count)
                        )
                    )
                )
            )
            let upperIndex = min(
                samples.count,
                max(
                    lowerIndex + 1,
                    Int(
                        ceil(
                            sampleEnd / sourceDuration
                                * Double(samples.count)
                        )
                    )
                )
            )
            let level = samples[lowerIndex..<upperIndex].reduce(
                Float.zero
            ) { peak, sample in
                guard sample.isFinite else { return peak }
                return max(peak, sample)
            }
            guard level > 0 else { return nil }

            // Keep the bar height proportional to the (already
            // loudness-compensated) sample level so loud passages read tall
            // and quiet passages read low. Non-zero levels get at least 1pt
            // so faint-but-real audio stays visible on the 26pt waveform
            // strip; zero levels still render nothing (silence stays blank).
            let normalizedLevel = CGFloat(level.clamped(to: 0...1))
            return TimelineWaveformBar(
                x: canvasSize.width
                    * (CGFloat(barIndex) + 0.5)
                    / CGFloat(barCount),
                halfHeight: max(
                    1.0,
                    normalizedLevel * canvasSize.height * 0.45
                )
            )
        }
    }
}
