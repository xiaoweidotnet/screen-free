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

        let barCount = min(
            90,
            max(1, Int(canvasSize.width / 5))
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

            let normalizedLevel = CGFloat(level.clamped(to: 0...1))
            let visibleLevel = pow(normalizedLevel, 0.72)
            return TimelineWaveformBar(
                x: canvasSize.width
                    * (CGFloat(barIndex) + 0.5)
                    / CGFloat(barCount),
                halfHeight: max(
                    0.75,
                    visibleLevel * canvasSize.height * 0.45
                )
            )
        }
    }
}
