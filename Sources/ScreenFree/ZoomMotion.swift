import CoreGraphics
import Foundation
import ScreenFreeCore

enum ZoomMotionPreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case slow = "Slow"
    case mellow = "Mellow"
    case quick = "Quick"
    case rapid = "Rapid"
    case custom = "Customize"

    var id: Self { self }

    var transitionDuration: TimeInterval {
        switch self {
        case .slow: return 1.2
        case .mellow: return 0.95
        case .quick: return 0.46
        case .rapid: return 0.24
        case .custom: return 0.95
        }
    }

    var exportSampleCount: Int {
        switch self {
        case .slow: return 16
        case .mellow: return 12
        case .quick: return 10
        case .rapid: return 8
        case .custom: return 18
        }
    }

    func easedProgress(_ value: CGFloat) -> CGFloat {
        let t = value.clamped(to: 0...1)
        switch self {
        case .slow:
            // Smootherstep: zero velocity and acceleration at both ends.
            return t * t * t * (t * (t * 6 - 15) + 10)
        case .mellow:
            // Screen Studio-style ease: no abrupt velocity at either edge.
            return t * t * t * (t * (t * 6 - 15) + 10)
        case .quick:
            return 1 - pow(1 - t, 3)
        case .rapid:
            return 1 - pow(1 - t, 5)
        case .custom:
            return CubicBezierEasing.defaultCurve.value(at: t)
        }
    }
}

struct CubicBezierEasing: Codable, Equatable, Sendable {
    var x1: CGFloat
    var y1: CGFloat
    var x2: CGFloat
    var y2: CGFloat

    static let defaultCurve = CubicBezierEasing(
        x1: 0.25,
        y1: 0.1,
        x2: 0.25,
        y2: 1
    )

    func clamped() -> CubicBezierEasing {
        CubicBezierEasing(
            x1: x1.clamped(to: 0...1),
            y1: y1.clamped(to: 0...1),
            x2: x2.clamped(to: 0...1),
            y2: y2.clamped(to: 0...1)
        )
    }

    func value(at progress: CGFloat) -> CGFloat {
        let target = progress.clamped(to: 0...1)
        let curve = clamped()
        var parameter = target
        for _ in 0..<8 {
            let error = curve.coordinate(
                parameter,
                first: curve.x1,
                second: curve.x2
            ) - target
            if abs(error) < 0.000_01 { break }
            let derivative = curve.derivative(
                parameter,
                first: curve.x1,
                second: curve.x2
            )
            if abs(derivative) < 0.000_01 { break }
            parameter = (parameter - error / derivative).clamped(to: 0...1)
        }
        if abs(
            curve.coordinate(
                parameter,
                first: curve.x1,
                second: curve.x2
            ) - target
        ) > 0.000_1 {
            var lower: CGFloat = 0
            var upper: CGFloat = 1
            for _ in 0..<14 {
                parameter = (lower + upper) / 2
                if curve.coordinate(
                    parameter,
                    first: curve.x1,
                    second: curve.x2
                ) < target {
                    lower = parameter
                } else {
                    upper = parameter
                }
            }
        }
        return curve.coordinate(
            parameter,
            first: curve.y1,
            second: curve.y2
        ).clamped(to: 0...1)
    }

    private func coordinate(
        _ t: CGFloat,
        first: CGFloat,
        second: CGFloat
    ) -> CGFloat {
        let inverse = 1 - t
        return 3 * inverse * inverse * t * first
            + 3 * inverse * t * t * second
            + t * t * t
    }

    private func derivative(
        _ t: CGFloat,
        first: CGFloat,
        second: CGFloat
    ) -> CGFloat {
        let inverse = 1 - t
        return 3 * inverse * inverse * first
            + 6 * inverse * t * (second - first)
            + 3 * t * t * (1 - second)
    }
}

struct ZoomMotionStyle: Codable, Equatable, Sendable {
    var preset: ZoomMotionPreset
    var customTransitionDuration: TimeInterval
    var customEasing: CubicBezierEasing

    init(
        preset: ZoomMotionPreset,
        customTransitionDuration: TimeInterval = 0.95,
        customEasing: CubicBezierEasing = .defaultCurve
    ) {
        self.preset = preset
        self.customTransitionDuration = customTransitionDuration
        self.customEasing = customEasing
    }

    static let slow = ZoomMotionStyle(preset: .slow)
    static let mellow = ZoomMotionStyle(preset: .mellow)
    static let quick = ZoomMotionStyle(preset: .quick)
    static let rapid = ZoomMotionStyle(preset: .rapid)

    var transitionDuration: TimeInterval {
        preset == .custom
            ? customTransitionDuration.clamped(to: 0.08...1.5)
            : preset.transitionDuration
    }

    var exportSampleCount: Int {
        preset.exportSampleCount
    }

    func easedProgress(_ value: CGFloat) -> CGFloat {
        preset == .custom
            ? customEasing.value(at: value)
            : preset.easedProgress(value)
    }
}

struct ResolvedZoomMotion {
    let zoom: ZoomEvent
    let scale: CGFloat
    let focusX: CGFloat
    let focusY: CGFloat
}

enum ZoomFocusResolver {
    /// 跟随相机的一阶低通时间常数：越大焦点越稳、跟随越迟。
    /// 之前用 0.36s 的 3 抽头平均，鼠标持续滑动时 30fps 轨迹几乎原样
    /// 穿透成焦点，被放大倍数乘性放大成画面晃动（导出/预览同源）。
    private static let followTimeConstant: TimeInterval = 0.3
    private static let simulationStep: TimeInterval = 1.0 / 30.0

    static func focus(
        at time: TimeInterval,
        zoomState: ResolvedZoomMotion,
        project: TimelineProject,
        cursorTailFreeze: TimeInterval,
        cursorLoopToStart: Bool,
        removeCursorShakes: Bool,
        cursorShakeThreshold: CGFloat,
        optimizeRapidCursorChanges: Bool,
        smoothCursorMovement: Bool,
        processedCursorSamples: [CursorSample]? = nil
    ) -> CGPoint {
        guard zoomState.zoom.resolvedFollowsCursor else {
            return CGPoint(
                x: zoomState.focusX,
                y: zoomState.focusY
            )
        }

        let chainStart = continuousChainStart(
            containing: zoomState.zoom,
            zooms: project.zooms
        )
        let cursorSamples = processedCursorSamples
            ?? project.processedCursorSamples(
                removeShakes: removeCursorShakes,
                shakeThreshold: cursorShakeThreshold,
                optimizeRapidChanges: optimizeRapidCursorChanges
            )

        func cursor(at sampleTime: TimeInterval) -> CGPoint? {
            project.cursorSample(
                atTimelineTime: sampleTime,
                using: cursorSamples,
                freezeBeforeEnd: cursorTailFreeze,
                loopToStart: cursorLoopToStart,
                smoothMovement: smoothCursorMovement
            ).map {
                CGPoint(x: $0.normalizedX, y: $0.normalizedY)
            }
        }

        // 从缩放链起点的光标位置初始化相机，再沿时间轴以 30Hz 步进做
        // 因果一阶低通。链内所有缩放共享同一起点与同一条模拟轨迹，
        // 保证相邻缩放边界处焦点连续。
        guard var smoothed = cursor(at: chainStart) else {
            return CGPoint(x: zoomState.focusX, y: zoomState.focusY)
        }
        var simulated = chainStart
        while time - simulated > simulationStep / 2 {
            let step = min(simulationStep, time - simulated)
            simulated += step
            if let target = cursor(at: simulated) {
                let alpha = 1 - exp(-step / followTimeConstant)
                smoothed.x += alpha * (target.x - smoothed.x)
                smoothed.y += alpha * (target.y - smoothed.y)
            }
        }
        return CGPoint(
            x: smoothed.x.clamped(to: 0...1),
            y: smoothed.y.clamped(to: 0...1)
        )
    }

    private static func continuousChainStart(
        containing zoom: ZoomEvent,
        zooms: [ZoomEvent]
    ) -> TimeInterval {
        let ordered = zooms.sorted { $0.start < $1.start }
        guard var index = ordered.firstIndex(where: { $0.id == zoom.id }) else {
            return zoom.start
        }
        while index > 0 {
            let previous = ordered[index - 1]
            let current = ordered[index]
            guard current.start - previous.end
                    <= ZoomMotionResolver.continuityTolerance else {
                break
            }
            index -= 1
        }
        return ordered[index].start
    }
}

enum ZoomMotionResolver {
    static let continuityTolerance: TimeInterval = 1.0 / 30.0

    private struct Segment {
        let zoom: ZoomEvent
        let start: TimeInterval
        let end: TimeInterval
    }

    static func state(
        at time: TimeInterval,
        zooms: [ZoomEvent],
        totalDuration: TimeInterval,
        motion: ZoomMotionStyle
    ) -> ResolvedZoomMotion? {
        let segments = normalizedSegments(
            zooms: zooms,
            totalDuration: totalDuration
        )
        for (index, segment) in segments.enumerated() {
            if index + 1 < segments.count {
                let next = segments[index + 1]
                let gap = next.start - segment.end
                if gap > 0,
                   gap <= continuityTolerance,
                   time > segment.end,
                   time < next.start {
                    let progress = motion.easedProgress(
                        CGFloat((time - segment.end) / gap)
                    )
                    return ResolvedZoomMotion(
                        zoom: next.zoom,
                        scale: interpolateScale(
                            from: segment.zoom.scale,
                            to: next.zoom.scale,
                            progress: progress
                        ),
                        focusX: interpolate(
                            from: segment.zoom.focusX,
                            to: next.zoom.focusX,
                            progress: progress
                        ),
                        focusY: interpolate(
                            from: segment.zoom.focusY,
                            to: next.zoom.focusY,
                            progress: progress
                        )
                    )
                }
            }
            guard time >= segment.start, time <= segment.end else {
                continue
            }

            let previous = index > 0 ? segments[index - 1] : nil
            let next = index + 1 < segments.count
                ? segments[index + 1]
                : nil
            let joinsPrevious = previous.map {
                segment.start - $0.end <= continuityTolerance
            } ?? false
            let joinsNext = next.map {
                $0.start - segment.end <= continuityTolerance
            } ?? false
            let ramp = min(
                motion.transitionDuration,
                (segment.end - segment.start) / 2
            )

            if joinsPrevious, let previous, ramp > 0,
               time < segment.start + ramp {
                let rawProgress = CGFloat(
                    (time - segment.start) / ramp
                ).clamped(to: 0...1)
                let progress = motion.easedProgress(rawProgress)
                return ResolvedZoomMotion(
                    zoom: segment.zoom,
                    scale: interpolateScale(
                        from: CGFloat(previous.zoom.scale),
                        to: CGFloat(segment.zoom.scale),
                        progress: progress
                    ),
                    focusX: interpolate(
                        from: CGFloat(previous.zoom.focusX),
                        to: CGFloat(segment.zoom.focusX),
                        progress: progress
                    ),
                    focusY: interpolate(
                        from: CGFloat(previous.zoom.focusY),
                        to: CGFloat(segment.zoom.focusY),
                        progress: progress
                    )
                )
            }

            let progress: CGFloat
            if !joinsPrevious, ramp > 0, time < segment.start + ramp {
                progress = motion.easedProgress(
                    CGFloat((time - segment.start) / ramp)
                )
            } else if !joinsNext, ramp > 0, time > segment.end - ramp {
                progress = motion.easedProgress(
                    CGFloat((segment.end - time) / ramp)
                )
            } else {
                progress = 1
            }
            return ResolvedZoomMotion(
                zoom: segment.zoom,
                scale: interpolateScale(
                    from: 1,
                    to: segment.zoom.scale,
                    progress: progress
                ),
                focusX: CGFloat(segment.zoom.focusX),
                focusY: CGFloat(segment.zoom.focusY)
            )
        }
        return nil
    }

    static func activeRanges(
        zooms: [ZoomEvent],
        totalDuration: TimeInterval
    ) -> [ClosedRange<TimeInterval>] {
        let segments = normalizedSegments(
            zooms: zooms,
            totalDuration: totalDuration
        )
        var ranges: [ClosedRange<TimeInterval>] = []
        for segment in segments {
            if let last = ranges.last,
               segment.start - last.upperBound <= continuityTolerance {
                ranges[ranges.count - 1] =
                    last.lowerBound...max(last.upperBound, segment.end)
            } else {
                ranges.append(segment.start...segment.end)
            }
        }
        return ranges
    }

    static func state(
        at time: TimeInterval,
        zooms: [ZoomEvent],
        totalDuration: TimeInterval,
        preset: ZoomMotionPreset
    ) -> ResolvedZoomMotion? {
        state(
            at: time,
            zooms: zooms,
            totalDuration: totalDuration,
            motion: ZoomMotionStyle(preset: preset)
        )
    }

    private static func normalizedSegments(
        zooms: [ZoomEvent],
        totalDuration: TimeInterval
    ) -> [Segment] {
        guard totalDuration > 0 else { return [] }
        var lastEnd: TimeInterval = 0
        var segments: [Segment] = []
        for zoom in zooms.sorted(by: { $0.start < $1.start }) {
            let start = max(lastEnd, zoom.start)
                .clamped(to: 0...totalDuration)
            let end = min(totalDuration, zoom.end)
            defer { lastEnd = max(lastEnd, end) }
            guard end - start >= 0.1 - 0.000_001 else { continue }
            segments.append(
                Segment(
                    zoom: zoom,
                    start: start,
                    end: end
                )
            )
        }
        return segments
    }

    private static func interpolate(
        from start: CGFloat,
        to end: CGFloat,
        progress: CGFloat
    ) -> CGFloat {
        start + (end - start) * progress.clamped(to: 0...1)
    }

    /// Magnification is interpolated geometrically (constant relative zoom
    /// speed). Linear scale interpolation shrinks the visible area fastest
    /// right at the start of a zoom-in, which reads as an abrupt lunge.
    private static func interpolateScale(
        from start: CGFloat,
        to end: CGFloat,
        progress: CGFloat
    ) -> CGFloat {
        let clamped = progress.clamped(to: 0...1)
        guard start > 0, end > 0 else {
            return interpolate(from: start, to: end, progress: clamped)
        }
        return start * pow(end / start, clamped)
    }
}

enum AutomaticZoomPolicy {
    static func shouldGenerate(
        enabled: Bool,
        clicks: [MouseClick]
    ) -> Bool {
        enabled && clicks.contains {
            AutomaticZoomTriggerPolicy.shouldTriggerZoom(for: $0)
        }
    }
}
