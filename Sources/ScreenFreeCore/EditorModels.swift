import CoreGraphics
import Foundation

public struct TimelineClip: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var sourceStart: TimeInterval
    /// Duration in the source asset before playback-rate scaling.
    public var duration: TimeInterval
    public var playbackRate: Double
    public var volume: Double

    public init(
        id: UUID = UUID(),
        sourceStart: TimeInterval,
        duration: TimeInterval,
        playbackRate: Double = 1,
        volume: Double = 1
    ) {
        self.id = id
        self.sourceStart = sourceStart
        self.duration = duration
        self.playbackRate = playbackRate
        self.volume = volume
    }

    public var sourceEnd: TimeInterval { sourceStart + duration }
    public var timelineDuration: TimeInterval {
        duration / max(0.01, playbackRate)
    }

    /// Whether the clip deviates from a pristine full-length source clip,
    /// i.e. it was trimmed, produced by a split, speed-changed, or
    /// volume-adjusted.
    public func isEdited(sourceDuration: TimeInterval) -> Bool {
        let epsilon = 0.000_1
        if sourceStart > epsilon { return true }
        if sourceDuration.isFinite, sourceDuration > 0,
           sourceEnd < sourceDuration - epsilon {
            return true
        }
        if abs(playbackRate - 1) > epsilon { return true }
        if abs(volume - 1) > epsilon { return true }
        return false
    }
}

public struct CursorSample: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var time: TimeInterval
    public var normalizedX: CGFloat
    public var normalizedY: CGFloat

    public init(
        id: UUID = UUID(),
        time: TimeInterval,
        normalizedX: CGFloat,
        normalizedY: CGFloat
    ) {
        self.id = id
        self.time = time
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
    }
}

public enum MouseButtonKind: String, Codable, Sendable {
    case left
    case right
}

public struct MouseClick: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var time: TimeInterval
    public var normalizedX: CGFloat
    public var normalizedY: CGFloat
    public var button: MouseButtonKind?
    public var holdDuration: TimeInterval?

    public init(
        id: UUID = UUID(),
        time: TimeInterval,
        normalizedX: CGFloat,
        normalizedY: CGFloat,
        button: MouseButtonKind? = nil,
        holdDuration: TimeInterval? = nil
    ) {
        self.id = id
        self.time = time
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
        self.button = button
        self.holdDuration = holdDuration
    }
}

public enum AutomaticZoomTriggerPolicy {
    public static let minimumRightHoldDuration: TimeInterval = 0.5

    /// 点击（左键，含旧数据里未标注类型的点击）触发标准时长的自动缩放；
    /// 右键长按 ≥ minimumRightHoldDuration 触发按住时长加长的缩放；
    /// 普通鼠标移动与短右键不触发。
    public static func shouldTriggerZoom(for click: MouseClick) -> Bool {
        switch click.button {
        case .right:
            return (click.holdDuration ?? 0) >= minimumRightHoldDuration
        case .left, nil:
            return true
        }
    }
}

public struct ZoomEvent: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var start: TimeInterval
    public var duration: TimeInterval
    public var scale: CGFloat
    public var focusX: CGFloat
    public var focusY: CGFloat
    public var followsCursor: Bool?

    public init(
        id: UUID = UUID(),
        start: TimeInterval,
        duration: TimeInterval = 3.2,
        scale: CGFloat = 1.8,
        focusX: CGFloat,
        focusY: CGFloat,
        followsCursor: Bool? = nil
    ) {
        self.id = id
        self.start = start
        self.duration = duration
        self.scale = scale
        self.focusX = focusX
        self.focusY = focusY
        self.followsCursor = followsCursor
    }

    public var end: TimeInterval { start + duration }
    public var resolvedFollowsCursor: Bool { followsCursor ?? true }
}

public enum ZoomRangeEdit: Sendable {
    case move
    case resizeLeading
    case resizeTrailing
}

public struct CaptionCue: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var sourceStart: TimeInterval
    public var duration: TimeInterval
    public var text: String

    public init(
        id: UUID = UUID(),
        sourceStart: TimeInterval,
        duration: TimeInterval,
        text: String
    ) {
        self.id = id
        self.sourceStart = sourceStart
        self.duration = duration
        self.text = text
    }
}

public struct ShortcutEvent: Identifiable, Equatable, Codable, Sendable {
    public static let displayDuration: TimeInterval = 1.45

    public let id: UUID
    public var time: TimeInterval
    public var label: String

    public init(
        id: UUID = UUID(),
        time: TimeInterval,
        label: String
    ) {
        self.id = id
        self.time = time
        self.label = label
    }
}

public enum TimedRegionPresentation: String, Codable, Sendable {
    case redaction
    case spotlight
}

public enum PrivacyRedactionEffect: String, Codable, CaseIterable, Sendable {
    case solid
    case blur
}

public struct PrivacyRedaction: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var start: TimeInterval
    public var duration: TimeInterval
    public var normalizedX: CGFloat
    public var normalizedY: CGFloat
    public var normalizedWidth: CGFloat
    public var normalizedHeight: CGFloat
    public var opacity: CGFloat
    public var presentation: TimedRegionPresentation?
    public var highlightHue: CGFloat?
    public var effect: PrivacyRedactionEffect?

    public init(
        id: UUID = UUID(),
        start: TimeInterval,
        duration: TimeInterval = 3,
        normalizedX: CGFloat = 0.5,
        normalizedY: CGFloat = 0.5,
        normalizedWidth: CGFloat = 0.3,
        normalizedHeight: CGFloat = 0.16,
        opacity: CGFloat = 0.92,
        presentation: TimedRegionPresentation? = nil,
        highlightHue: CGFloat? = nil,
        effect: PrivacyRedactionEffect? = nil
    ) {
        self.id = id
        self.start = start
        self.duration = duration
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
        self.normalizedWidth = normalizedWidth
        self.normalizedHeight = normalizedHeight
        self.opacity = opacity
        self.presentation = presentation
        self.highlightHue = highlightHue
        self.effect = effect
    }

    public var end: TimeInterval { start + duration }
    public var resolvedPresentation: TimedRegionPresentation {
        presentation ?? .redaction
    }
    public var resolvedHighlightHue: CGFloat {
        (highlightHue ?? 0.13).clamped(to: 0...1)
    }
    /// Projects created before blur masks existed used an opaque cover.
    /// Keeping `nil` as solid preserves their appearance while new masks can
    /// explicitly opt into blur.
    public var resolvedEffect: PrivacyRedactionEffect {
        effect ?? .solid
    }

    /// A render-size-aware blur keeps the privacy mask equally effective in
    /// the editor, 720p previews, and 4K exports.
    public func blurRadius(forRenderSize size: CGSize) -> CGFloat {
        let reference = max(1, min(size.width, size.height))
        return (
            reference * (0.008 + opacity.clamped(to: 0...1) * 0.018)
        ).clamped(to: 6...36)
    }
}

public enum AnnotationKind: String, Codable, CaseIterable, Sendable {
    case brush
    case rectangle
    case ellipse
    case line
    case arrow
}

/// A point in normalized 0...1 video-composition coordinates (origin at the
/// bottom-left, Y up), matching the cursor-sample coordinate space.
public struct NormalizedPoint: Equatable, Codable, Sendable {
    public var x: CGFloat
    public var y: CGFloat

    public init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }
}

public struct AnnotationColor: Equatable, Codable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let red = AnnotationColor(red: 1, green: 0.22, blue: 0.22)
    public static let yellow = AnnotationColor(red: 1, green: 0.82, blue: 0.12)
    public static let green = AnnotationColor(red: 0.2, green: 0.9, blue: 0.42)
    public static let blue = AnnotationColor(red: 0.24, green: 0.6, blue: 1)
    public static let white = AnnotationColor(red: 1, green: 1, blue: 1)

    public static let palette: [AnnotationColor] = [
        .red, .yellow, .green, .blue, .white
    ]
}

public struct Annotation: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var kind: AnnotationKind
    /// Source time of the stroke's mouse-down.
    public var start: TimeInterval
    /// How long the finished annotation stays visible after the drawing
    /// gesture completes.
    public var duration: TimeInterval
    /// How long the drawing gesture took from mouse-down to mouse-up. During
    /// this window the shape is revealed progressively, matching the live
    /// drawing; 0 means the annotation appears complete (legacy data).
    public var drawDuration: TimeInterval
    public var points: [NormalizedPoint]
    public var normalizedStartX: CGFloat
    public var normalizedStartY: CGFloat
    public var normalizedEndX: CGFloat
    public var normalizedEndY: CGFloat
    public var lineWidth: CGFloat
    public var color: AnnotationColor

    public init(
        id: UUID = UUID(),
        kind: AnnotationKind,
        start: TimeInterval,
        duration: TimeInterval = 3,
        drawDuration: TimeInterval = 0,
        points: [NormalizedPoint] = [],
        normalizedStartX: CGFloat = 0,
        normalizedStartY: CGFloat = 0,
        normalizedEndX: CGFloat = 0,
        normalizedEndY: CGFloat = 0,
        lineWidth: CGFloat = 4,
        color: AnnotationColor = .red
    ) {
        self.id = id
        self.kind = kind
        self.start = start
        self.duration = duration
        self.drawDuration = max(0, drawDuration)
        self.points = points
        self.normalizedStartX = normalizedStartX
        self.normalizedStartY = normalizedStartY
        self.normalizedEndX = normalizedEndX
        self.normalizedEndY = normalizedEndY
        self.lineWidth = lineWidth
        self.color = color
    }

    public var end: TimeInterval {
        start + drawDuration + duration
    }

    /// 0 when the stroke begins, 1 once the drawing gesture completes.
    public func drawProgress(atSourceTime time: TimeInterval) -> Double {
        guard drawDuration > 0 else { return 1 }
        return ((time - start) / drawDuration).clamped(to: 0...1)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case start
        case duration
        case drawDuration
        case points
        case normalizedStartX
        case normalizedStartY
        case normalizedEndX
        case normalizedEndY
        case lineWidth
        case color
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try container.decode(AnnotationKind.self, forKey: .kind)
        start = try container.decode(TimeInterval.self, forKey: .start)
        duration = try container.decodeIfPresent(
            TimeInterval.self,
            forKey: .duration
        ) ?? 3
        drawDuration = try container.decodeIfPresent(
            TimeInterval.self,
            forKey: .drawDuration
        ) ?? 0
        points = try container.decodeIfPresent(
            [NormalizedPoint].self,
            forKey: .points
        ) ?? []
        normalizedStartX = try container.decodeIfPresent(
            CGFloat.self,
            forKey: .normalizedStartX
        ) ?? 0
        normalizedStartY = try container.decodeIfPresent(
            CGFloat.self,
            forKey: .normalizedStartY
        ) ?? 0
        normalizedEndX = try container.decodeIfPresent(
            CGFloat.self,
            forKey: .normalizedEndX
        ) ?? 0
        normalizedEndY = try container.decodeIfPresent(
            CGFloat.self,
            forKey: .normalizedEndY
        ) ?? 0
        lineWidth = try container.decodeIfPresent(
            CGFloat.self,
            forKey: .lineWidth
        ) ?? 4
        color = try container.decodeIfPresent(
            AnnotationColor.self,
            forKey: .color
        ) ?? .red
    }
}

public struct TimelineProject: Equatable, Codable, Sendable {
    public var clips: [TimelineClip]
    public var zooms: [ZoomEvent]
    public var cursorSamples: [CursorSample]
    public var clicks: [MouseClick]
    public var captions: [CaptionCue]
    public var shortcuts: [ShortcutEvent]
    public var redactions: [PrivacyRedaction]
    public var annotations: [Annotation]
    public var transitions: [ClipTransition]

    public init(
        clips: [TimelineClip] = [],
        zooms: [ZoomEvent] = [],
        cursorSamples: [CursorSample] = [],
        clicks: [MouseClick] = [],
        captions: [CaptionCue] = [],
        shortcuts: [ShortcutEvent] = [],
        redactions: [PrivacyRedaction] = [],
        annotations: [Annotation] = [],
        transitions: [ClipTransition] = []
    ) {
        self.clips = clips
        self.zooms = zooms
        self.cursorSamples = cursorSamples
        self.clicks = clicks
        self.captions = captions
        self.shortcuts = shortcuts
        self.redactions = redactions
        self.annotations = annotations
        self.transitions = transitions
        normalizeZoomRanges()
    }

    private enum CodingKeys: String, CodingKey {
        case clips
        case zooms
        case cursorSamples
        case clicks
        case captions
        case shortcuts
        case redactions
        case annotations
        case transitions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clips = try container.decodeIfPresent(
            [TimelineClip].self,
            forKey: .clips
        ) ?? []
        zooms = try container.decodeIfPresent(
            [ZoomEvent].self,
            forKey: .zooms
        ) ?? []
        cursorSamples = try container.decodeIfPresent(
            [CursorSample].self,
            forKey: .cursorSamples
        ) ?? []
        clicks = try container.decodeIfPresent(
            [MouseClick].self,
            forKey: .clicks
        ) ?? []
        captions = try container.decodeIfPresent(
            [CaptionCue].self,
            forKey: .captions
        ) ?? []
        shortcuts = try container.decodeIfPresent(
            [ShortcutEvent].self,
            forKey: .shortcuts
        ) ?? []
        redactions = try container.decodeIfPresent(
            [PrivacyRedaction].self,
            forKey: .redactions
        ) ?? []
        annotations = try container.decodeIfPresent(
            [Annotation].self,
            forKey: .annotations
        ) ?? []
        transitions = try container.decodeIfPresent(
            [ClipTransition].self,
            forKey: .transitions
        ) ?? []
        normalizeZoomRanges()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(clips, forKey: .clips)
        try container.encode(zooms, forKey: .zooms)
        try container.encode(cursorSamples, forKey: .cursorSamples)
        try container.encode(clicks, forKey: .clicks)
        try container.encode(captions, forKey: .captions)
        try container.encode(shortcuts, forKey: .shortcuts)
        try container.encode(redactions, forKey: .redactions)
        try container.encode(annotations, forKey: .annotations)
        try container.encode(transitions, forKey: .transitions)
    }

    public var duration: TimeInterval {
        clips.reduce(0) { $0 + $1.timelineDuration }
    }

    public func activeRedactions(
        atTimelineTime time: TimeInterval
    ) -> [PrivacyRedaction] {
        redactions.filter { time >= $0.start && time <= $0.end }
    }

    /// Annotations are recorded in source time (like cursor and click samples);
    /// they are rendered inside their fade window `[start, end]` in source
    /// coordinates and mapped to timeline time by the renderer.
    public func activeAnnotations(
        atSourceTime time: TimeInterval
    ) -> [Annotation] {
        annotations.filter { time >= $0.start && time <= $0.end }
    }

    @discardableResult
    public mutating func setRedactionRange(
        id: UUID,
        start: TimeInterval,
        duration requestedDuration: TimeInterval
    ) -> Bool {
        guard let index = redactions.firstIndex(where: { $0.id == id }),
              duration > 0 else {
            return false
        }
        let safeStart = start.clamped(to: 0...max(0, duration - 0.1))
        let safeDuration = requestedDuration.clamped(
            to: 0.1...max(0.1, duration - safeStart)
        )
        redactions[index].start = safeStart
        redactions[index].duration = safeDuration
        redactions.sort { $0.start < $1.start }
        return true
    }

    public mutating func clampTimedEventsToDuration() {
        let timelineDuration = duration
        guard timelineDuration > 0 else {
            zooms.removeAll()
            redactions.removeAll()
            annotations.removeAll()
            transitions.removeAll()
            return
        }
        normalizeZoomRanges()
        pruneTransitions()
        redactions.removeAll { $0.start >= timelineDuration }
        for index in redactions.indices {
            redactions[index].start = redactions[index].start.clamped(
                to: 0...max(0, timelineDuration - 0.1)
            )
            redactions[index].duration = redactions[index].duration.clamped(
                to: 0.1...max(
                    0.1,
                    timelineDuration - redactions[index].start
                )
            )
        }
    }

    public mutating func split(clipID: UUID, atTimelineTime time: TimeInterval) -> Bool {
        guard let index = clips.firstIndex(where: { $0.id == clipID }) else { return false }
        let timelineStart = clips[..<index].reduce(0) { $0 + $1.timelineDuration }
        let localTimeline = time - timelineStart
        let clip = clips[index]
        let localSource = localTimeline * clip.playbackRate
        guard localSource > 0.05, localSource < clip.duration - 0.05 else { return false }

        let first = TimelineClip(
            sourceStart: clip.sourceStart,
            duration: localSource,
            playbackRate: clip.playbackRate,
            volume: clip.volume
        )
        let second = TimelineClip(
            sourceStart: clip.sourceStart + localSource,
            duration: clip.duration - localSource,
            playbackRate: clip.playbackRate,
            volume: clip.volume
        )
        clips.replaceSubrange(index...index, with: [first, second])
        return true
    }

    @discardableResult
    public mutating func merge(
        clipID: UUID,
        withNext: Bool
    ) -> UUID? {
        guard let selectedIndex = clips.firstIndex(
            where: { $0.id == clipID }
        ) else {
            return nil
        }
        let leftIndex = withNext ? selectedIndex : selectedIndex - 1
        let rightIndex = leftIndex + 1
        guard clips.indices.contains(leftIndex),
              clips.indices.contains(rightIndex) else {
            return nil
        }
        let left = clips[leftIndex]
        let right = clips[rightIndex]
        guard abs(left.sourceEnd - right.sourceStart) < 0.01,
              abs(left.playbackRate - right.playbackRate) < 0.001,
              abs(left.volume - right.volume) < 0.001 else {
            return nil
        }
        let merged = TimelineClip(
            sourceStart: left.sourceStart,
            duration: left.duration + right.duration,
            playbackRate: left.playbackRate,
            volume: left.volume
        )
        clips.replaceSubrange(leftIndex...rightIndex, with: [merged])
        return merged.id
    }

    @discardableResult
    public mutating func trimStart(clipID: UUID, by amount: TimeInterval) -> Bool {
        guard amount > 0,
              let index = clips.firstIndex(where: { $0.id == clipID }),
              clips[index].duration - amount * clips[index].playbackRate >= 0.1 else {
            return false
        }
        let sourceAmount = amount * clips[index].playbackRate
        clips[index].sourceStart += sourceAmount
        clips[index].duration -= sourceAmount
        return true
    }

    @discardableResult
    public mutating func trimEnd(clipID: UUID, by amount: TimeInterval) -> Bool {
        guard amount > 0,
              let index = clips.firstIndex(where: { $0.id == clipID }),
              clips[index].duration - amount * clips[index].playbackRate >= 0.1 else {
            return false
        }
        clips[index].duration -= amount * clips[index].playbackRate
        return true
    }

    /// Moves the visible leading source boundary while preserving the clip's
    /// current trailing boundary. The edge may be dragged back into an
    /// earlier trim, but never across the preceding clip's source range.
    @discardableResult
    public mutating func setClipSourceStart(
        clipID: UUID,
        to proposedStart: TimeInterval,
        sourceDuration: TimeInterval
    ) -> Bool {
        guard sourceDuration.isFinite,
              sourceDuration > 0,
              let index = clips.firstIndex(where: { $0.id == clipID }) else {
            return false
        }
        let currentEnd = clips[index].sourceEnd
        let lowerBound = index > 0 ? clips[index - 1].sourceEnd : 0
        let upperBound = max(lowerBound, currentEnd - 0.1)
        let newStart = proposedStart.clamped(to: lowerBound...upperBound)
        guard abs(newStart - clips[index].sourceStart) > 0.000_1 else {
            return false
        }
        clips[index].sourceStart = newStart
        clips[index].duration = currentEnd - newStart
        return true
    }

    /// Moves the visible trailing source boundary while preserving the clip's
    /// current leading boundary. The edge may restore a previous trim, but
    /// cannot overlap the following clip or exceed the source asset.
    @discardableResult
    public mutating func setClipSourceEnd(
        clipID: UUID,
        to proposedEnd: TimeInterval,
        sourceDuration: TimeInterval
    ) -> Bool {
        guard sourceDuration.isFinite,
              sourceDuration > 0,
              let index = clips.firstIndex(where: { $0.id == clipID }) else {
            return false
        }
        let currentStart = clips[index].sourceStart
        let upperBound = index + 1 < clips.count
            ? clips[index + 1].sourceStart
            : sourceDuration
        let lowerBound = min(upperBound, currentStart + 0.1)
        let newEnd = proposedEnd.clamped(to: lowerBound...upperBound)
        guard abs(newEnd - clips[index].sourceEnd) > 0.000_1 else {
            return false
        }
        clips[index].duration = newEnd - currentStart
        return true
    }

    @discardableResult
    public mutating func resetTrim(
        clipID: UUID,
        sourceDuration: TimeInterval
    ) -> Bool {
        guard sourceDuration > 0,
              let index = clips.firstIndex(
                  where: { $0.id == clipID }
              ) else {
            return false
        }
        let lowerBound = index > 0
            ? clips[index - 1].sourceEnd
            : 0
        let upperBound = index + 1 < clips.count
            ? clips[index + 1].sourceStart
            : sourceDuration
        let safeStart = lowerBound.clamped(to: 0...sourceDuration)
        let safeEnd = upperBound.clamped(to: safeStart...sourceDuration)
        guard safeEnd - safeStart >= 0.1 else { return false }
        let changed = abs(clips[index].sourceStart - safeStart) > 0.001
            || abs(clips[index].duration - (safeEnd - safeStart)) > 0.001
        clips[index].sourceStart = safeStart
        clips[index].duration = safeEnd - safeStart
        return changed
    }

    public func clipID(atTimelineTime time: TimeInterval) -> UUID? {
        var cursor: TimeInterval = 0
        for clip in clips {
            if time >= cursor, time <= cursor + clip.timelineDuration {
                return clip.id
            }
            cursor += clip.timelineDuration
        }
        return clips.last?.id
    }

    public func nearestCursor(to time: TimeInterval) -> CursorSample? {
        nearestCursor(to: time, in: cursorSamples)
    }

    public func processedCursorSamples(
        removeShakes: Bool,
        shakeThreshold: CGFloat,
        optimizeRapidChanges: Bool
    ) -> [CursorSample] {
        let sorted = cursorSamples.sorted { $0.time < $1.time }
        guard sorted.count >= 3 else { return sorted }
        let threshold = shakeThreshold.clamped(to: 0.002...0.08)
        var filtered: [CursorSample] = []
        filtered.reserveCapacity(sorted.count)
        filtered.append(sorted[0])

        for index in 1..<(sorted.count - 1) {
            let previous = sorted[index - 1]
            let current = sorted[index]
            let next = sorted[index + 1]
            let surroundingDistance = hypot(
                next.normalizedX - previous.normalizedX,
                next.normalizedY - previous.normalizedY
            )
            let excursion = min(
                hypot(
                    current.normalizedX - previous.normalizedX,
                    current.normalizedY - previous.normalizedY
                ),
                hypot(
                    current.normalizedX - next.normalizedX,
                    current.normalizedY - next.normalizedY
                )
            )
            let isShortSpike = next.time - previous.time <= 0.22
                && surroundingDistance <= threshold
                && excursion >= threshold * 2
            if !removeShakes || !isShortSpike {
                filtered.append(current)
            }
        }
        filtered.append(sorted[sorted.count - 1])

        guard optimizeRapidChanges, filtered.count >= 3 else {
            return filtered
        }
        var smoothed = filtered
        for index in 1..<(filtered.count - 1) {
            let previous = filtered[index - 1]
            let current = filtered[index]
            let next = filtered[index + 1]
            let previousInterval = max(1 / 240, current.time - previous.time)
            let nextInterval = max(1 / 240, next.time - current.time)
            let incomingSpeed = hypot(
                current.normalizedX - previous.normalizedX,
                current.normalizedY - previous.normalizedY
            ) / previousInterval
            let outgoingSpeed = hypot(
                next.normalizedX - current.normalizedX,
                next.normalizedY - current.normalizedY
            ) / nextInterval
            guard max(incomingSpeed, outgoingSpeed) > 3 else { continue }
            smoothed[index].normalizedX = previous.normalizedX * 0.2
                + current.normalizedX * 0.6
                + next.normalizedX * 0.2
            smoothed[index].normalizedY = previous.normalizedY * 0.2
                + current.normalizedY * 0.6
                + next.normalizedY * 0.2
        }
        return smoothed
    }

    private func nearestCursor(
        to time: TimeInterval,
        in samples: [CursorSample]
    ) -> CursorSample? {
        guard let sourceTime = sourceTime(forTimelineTime: time) else { return nil }
        return samples.min {
            abs($0.time - sourceTime) < abs($1.time - sourceTime)
        }
    }

    private func interpolatedCursor(
        to time: TimeInterval,
        in samples: [CursorSample]
    ) -> CursorSample? {
        guard let sourceTime = sourceTime(forTimelineTime: time),
              !samples.isEmpty else {
            return nil
        }
        guard let first = samples.first,
              let last = samples.last else {
            return nil
        }
        if sourceTime <= first.time { return first }
        if sourceTime >= last.time { return last }
        guard let upperIndex = samples.firstIndex(
            where: { $0.time >= sourceTime }
        ), upperIndex > 0 else {
            return nearestCursor(to: time, in: samples)
        }
        let lower = samples[upperIndex - 1]
        let upper = samples[upperIndex]
        let interval = upper.time - lower.time
        guard interval > 0 else { return lower }
        let progress = CGFloat(
            ((sourceTime - lower.time) / interval).clamped(to: 0...1)
        )
        return CursorSample(
            id: lower.id,
            time: sourceTime,
            normalizedX: lower.normalizedX
                + (upper.normalizedX - lower.normalizedX) * progress,
            normalizedY: lower.normalizedY
                + (upper.normalizedY - lower.normalizedY) * progress
        )
    }

    public func cursorSample(
        atTimelineTime time: TimeInterval,
        freezeBeforeEnd: TimeInterval,
        loopToStart: Bool = false,
        removeShakes: Bool = false,
        shakeThreshold: CGFloat = 0.012,
        optimizeRapidChanges: Bool = false,
        smoothMovement: Bool = false
    ) -> CursorSample? {
        let samples = processedCursorSamples(
            removeShakes: removeShakes,
            shakeThreshold: shakeThreshold,
            optimizeRapidChanges: optimizeRapidChanges
        )
        return cursorSample(
            atTimelineTime: time,
            using: samples,
            freezeBeforeEnd: freezeBeforeEnd,
            loopToStart: loopToStart,
            smoothMovement: smoothMovement
        )
    }

    public func cursorSample(
        atTimelineTime time: TimeInterval,
        using processedSamples: [CursorSample],
        freezeBeforeEnd: TimeInterval,
        loopToStart: Bool = false,
        smoothMovement: Bool = false
    ) -> CursorSample? {
        let samples = processedSamples
        let safeTime = time.clamped(to: 0...duration)
        let freezeStart = max(
            0,
            duration - freezeBeforeEnd.clamped(to: 0...duration)
        )
        let resolvedCursor: (TimeInterval) -> CursorSample? = { time in
            smoothMovement
                ? interpolatedCursor(to: time, in: samples)
                : nearestCursor(to: time, in: samples)
        }
        guard loopToStart else {
            return resolvedCursor(min(safeTime, freezeStart))
        }

        let returnDuration = Self.cursorReturnDuration(
            for: duration
        )
        let returnStart = max(0, duration - returnDuration)
        guard returnDuration > 0, safeTime >= returnStart,
              let opening = resolvedCursor(0),
              let closing = resolvedCursor(
                  min(returnStart, freezeStart)
              ) else {
            return resolvedCursor(min(safeTime, freezeStart))
        }
        let linearProgress = (
            (safeTime - returnStart) / returnDuration
        ).clamped(to: 0...1)
        let progress = linearProgress
            * linearProgress
            * (3 - 2 * linearProgress)
        return CursorSample(
            id: closing.id,
            time: closing.time,
            normalizedX: closing.normalizedX
                + (opening.normalizedX - closing.normalizedX) * progress,
            normalizedY: closing.normalizedY
                + (opening.normalizedY - closing.normalizedY) * progress
        )
    }

    public static func cursorReturnDuration(
        for projectDuration: TimeInterval
    ) -> TimeInterval {
        min(1, max(0, projectDuration) * 0.2)
    }

    public func sourceTime(forTimelineTime time: TimeInterval) -> TimeInterval? {
        var timelineStart: TimeInterval = 0
        for clip in clips {
            let timelineEnd = timelineStart + clip.timelineDuration
            if time >= timelineStart, time <= timelineEnd {
                return clip.sourceStart + (time - timelineStart) * clip.playbackRate
            }
            timelineStart = timelineEnd
        }
        return nil
    }

    public func timelineTime(forSourceTime sourceTime: TimeInterval) -> TimeInterval? {
        var timelineStart: TimeInterval = 0
        for clip in clips {
            if sourceTime >= clip.sourceStart, sourceTime <= clip.sourceEnd {
                return timelineStart + (sourceTime - clip.sourceStart) / clip.playbackRate
            }
            timelineStart += clip.timelineDuration
        }
        return nil
    }

    public mutating func generateZoomsFromClicks(
        scale: CGFloat = 1.8,
        duration: TimeInterval = 3.2,
        minimumSpacing: TimeInterval = 0.8
    ) {
        var generated: [ZoomEvent] = []
        for click in clicks.sorted(by: { $0.time < $1.time }) {
            guard AutomaticZoomTriggerPolicy.shouldTriggerZoom(
                for: click
            ) else {
                continue
            }
            guard let timelineTime = timelineTime(forSourceTime: click.time) else {
                continue
            }
            let heldTimelineDuration: TimeInterval
            if click.button == .right,
               let holdDuration = click.holdDuration,
               holdDuration > 0 {
                let releaseTime = self.timelineTime(
                    forSourceTime: click.time + holdDuration
                )
                heldTimelineDuration = max(
                    0,
                    (releaseTime ?? timelineTime + holdDuration) - timelineTime
                )
            } else {
                heldTimelineDuration = 0
            }
            let zoomStart = max(0, timelineTime - 0.15)
            let requestedDuration = max(
                duration,
                heldTimelineDuration + 1.8
            )
            let zoomDuration = min(
                requestedDuration,
                max(0.1, self.duration - zoomStart)
            )
            let zoomEnd = zoomStart + zoomDuration

            if let lastIndex = generated.indices.last,
               timelineTime - generated[lastIndex].start < minimumSpacing {
                if heldTimelineDuration > 0 {
                    generated[lastIndex].duration =
                        max(generated[lastIndex].end, zoomEnd)
                        - generated[lastIndex].start
                }
                continue
            }
            generated.append(
                ZoomEvent(
                    start: zoomStart,
                    duration: zoomDuration,
                    scale: scale,
                    focusX: click.normalizedX.clamped(to: 0...1),
                    focusY: click.normalizedY.clamped(to: 0...1),
                    followsCursor: true
                )
            )
        }
        zooms = generated
        normalizeZoomRanges()
    }

    public var hasOverlappingZooms: Bool {
        let ordered = zooms.sorted { $0.start < $1.start }
        return zip(ordered, ordered.dropFirst()).contains {
            left, right in
            left.end > right.start + 0.000_001
        }
    }

    public mutating func normalizeZoomRanges(
        minimumDuration: TimeInterval = 0.1
    ) {
        let timelineDuration = duration
        guard timelineDuration >= minimumDuration else {
            zooms.removeAll()
            return
        }
        let ordered = zooms.enumerated().sorted {
            if abs($0.element.start - $1.element.start) < 0.000_001 {
                return $0.offset < $1.offset
            }
            return $0.element.start < $1.element.start
        }
        var normalized: [ZoomEvent] = []
        for (_, original) in ordered
        where original.start < timelineDuration {
            var candidate = original
            candidate.start = candidate.start.clamped(
                to: 0...timelineDuration - minimumDuration
            )
            candidate.duration = candidate.duration.clamped(
                to: minimumDuration...max(
                    minimumDuration,
                    timelineDuration - candidate.start
                )
            )

            while let last = normalized.last,
                  last.end > candidate.start + 0.000_001 {
                let availableDuration = candidate.start - last.start
                if availableDuration >= minimumDuration {
                    normalized[normalized.count - 1].duration =
                        availableDuration
                    break
                }
                normalized.removeLast()
            }
            normalized.append(candidate)
        }
        zooms = normalized
    }

    @discardableResult
    public mutating func insertZoom(
        _ zoom: ZoomEvent,
        minimumDuration: TimeInterval = 0.1
    ) -> Bool {
        let timelineDuration = duration
        guard timelineDuration >= minimumDuration else { return false }
        normalizeZoomRanges(minimumDuration: minimumDuration)

        var candidate = zoom
        candidate.start = candidate.start.clamped(
            to: 0...timelineDuration - minimumDuration
        )
        let ordered = zooms.sorted { $0.start < $1.start }
        guard !ordered.contains(where: {
            candidate.start >= $0.start - 0.000_001
                && candidate.start < $0.end - 0.000_001
        }) else {
            return false
        }
        let nextStart = ordered.first(where: {
            $0.start > candidate.start + 0.000_001
        })?.start ?? timelineDuration
        let availableDuration = nextStart - candidate.start
        guard availableDuration >= minimumDuration else { return false }

        candidate.duration = candidate.duration.clamped(
            to: minimumDuration...availableDuration
        )
        zooms.append(candidate)
        zooms.sort { $0.start < $1.start }
        return true
    }

    @discardableResult
    public mutating func splitZoom(
        id: UUID,
        atTimelineTime time: TimeInterval,
        minimumSegmentDuration: TimeInterval = 0.1
    ) -> UUID? {
        guard let index = zooms.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        let zoom = zooms[index]
        guard time >= zoom.start + minimumSegmentDuration,
              time <= zoom.end - minimumSegmentDuration else {
            return nil
        }

        zooms[index].duration = time - zoom.start
        let right = ZoomEvent(
            start: time,
            duration: zoom.end - time,
            scale: zoom.scale,
            focusX: zoom.focusX,
            focusY: zoom.focusY,
            followsCursor: zoom.followsCursor
        )
        zooms.insert(right, at: index + 1)
        return right.id
    }

    @discardableResult
    public mutating func setZoomRange(
        id: UUID,
        start: TimeInterval,
        duration requestedDuration: TimeInterval,
        edit: ZoomRangeEdit = .resizeTrailing,
        minimumDuration: TimeInterval = 0.1
    ) -> Bool {
        guard self.duration >= minimumDuration,
              zooms.contains(where: { $0.id == id }) else {
            return false
        }
        zooms.sort { $0.start < $1.start }
        guard let index = zooms.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let lowerBound = index > 0 ? zooms[index - 1].end : 0
        let upperBound = index + 1 < zooms.count
            ? zooms[index + 1].start
            : self.duration
        guard upperBound - lowerBound >= minimumDuration else {
            return false
        }

        let maximumDuration = upperBound - lowerBound
        let boundedDuration: TimeInterval
        let boundedStart: TimeInterval
        switch edit {
        case .move:
            boundedDuration = requestedDuration.clamped(
                to: minimumDuration...maximumDuration
            )
            boundedStart = start.clamped(
                to: lowerBound...upperBound - boundedDuration
            )
        case .resizeLeading:
            let requestedEnd = start + requestedDuration
            let boundedEnd = requestedEnd.clamped(
                to: lowerBound + minimumDuration...upperBound
            )
            boundedStart = start.clamped(
                to: lowerBound...boundedEnd - minimumDuration
            )
            boundedDuration = boundedEnd - boundedStart
        case .resizeTrailing:
            boundedStart = start.clamped(
                to: lowerBound...upperBound - minimumDuration
            )
            let requestedEnd = start + requestedDuration
            let boundedEnd = requestedEnd.clamped(
                to: boundedStart + minimumDuration...upperBound
            )
            boundedDuration = boundedEnd - boundedStart
        }
        zooms[index].start = boundedStart
        zooms[index].duration = boundedDuration
        return true
    }
}

public extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
