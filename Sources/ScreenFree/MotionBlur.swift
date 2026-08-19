import CoreGraphics
import Foundation
import ScreenFreeCore

struct MotionBlurStyle: Codable, Equatable, Sendable {
    var enabled: Bool
    var strength: CGFloat
    var cursorAmount: CGFloat
    var zoomAmount: CGFloat
    var panAmount: CGFloat

    static let disabled = MotionBlurStyle(
        enabled: false,
        strength: 0,
        cursorAmount: 0,
        zoomAmount: 0,
        panAmount: 0
    )

    func clamped() -> MotionBlurStyle {
        MotionBlurStyle(
            enabled: enabled,
            strength: strength.clamped(to: 0...1),
            cursorAmount: cursorAmount.clamped(to: 0...1),
            zoomAmount: zoomAmount.clamped(to: 0...1),
            panAmount: panAmount.clamped(to: 0...1)
        )
    }
}

struct ResolvedMotionBlur: Equatable, Sendable {
    var screenRadius: CGFloat
    var cursorRadius: CGFloat

    static let zero = ResolvedMotionBlur(
        screenRadius: 0,
        cursorRadius: 0
    )
}

enum MotionBlurResolver {
    static let sampleInterval: TimeInterval = 1 / 30

    static func resolve(
        at time: TimeInterval,
        project: TimelineProject,
        zoomMotion: ZoomMotionStyle,
        style: MotionBlurStyle,
        renderSize: CGSize,
        cursorTailFreeze: TimeInterval,
        cursorLoopToStart: Bool,
        removeCursorShakes: Bool,
        cursorShakeThreshold: CGFloat,
        optimizeRapidCursorChanges: Bool,
        smoothCursorMovement: Bool,
        processedCursorSamples: [CursorSample]? = nil
    ) -> ResolvedMotionBlur {
        let style = style.clamped()
        guard style.enabled, style.strength > 0,
              project.duration > 0 else {
            return .zero
        }

        let currentTime = time.clamped(to: 0...project.duration)
        let previousTime = max(0, currentTime - sampleInterval)
        let elapsed = max(1 / 240, currentTime - previousTime)
        let samples = processedCursorSamples
            ?? project.processedCursorSamples(
                removeShakes: removeCursorShakes,
                shakeThreshold: cursorShakeThreshold,
                optimizeRapidChanges: optimizeRapidCursorChanges
            )
        let currentCursor = project.cursorSample(
            atTimelineTime: currentTime,
            using: samples,
            freezeBeforeEnd: cursorTailFreeze,
            loopToStart: cursorLoopToStart,
            smoothMovement: smoothCursorMovement
        )
        let previousCursor = project.cursorSample(
            atTimelineTime: previousTime,
            using: samples,
            freezeBeforeEnd: cursorTailFreeze,
            loopToStart: cursorLoopToStart,
            smoothMovement: smoothCursorMovement
        )
        let cursorVelocity: CGFloat
        if let currentCursor, let previousCursor {
            cursorVelocity = hypot(
                currentCursor.normalizedX - previousCursor.normalizedX,
                currentCursor.normalizedY - previousCursor.normalizedY
            ) / elapsed
        } else {
            cursorVelocity = 0
        }

        let referenceSize = max(
            1,
            min(renderSize.width, renderSize.height)
        )
        return ResolvedMotionBlur(
            screenRadius: screenRadius(
                at: currentTime,
                zooms: project.zooms,
                totalDuration: project.duration,
                zoomMotion: zoomMotion,
                style: style,
                renderSize: renderSize
            ),
            cursorRadius: (
                style.strength
                    * style.cursorAmount
                    * referenceSize
                    * 0.012
                    * min(1.5, cursorVelocity / 2)
            ).clamped(to: 0...24)
        )
    }

    static func screenRadius(
        at time: TimeInterval,
        zooms: [ZoomEvent],
        totalDuration: TimeInterval,
        zoomMotion: ZoomMotionStyle,
        style: MotionBlurStyle,
        renderSize: CGSize
    ) -> CGFloat {
        let style = style.clamped()
        guard style.enabled, style.strength > 0,
              totalDuration > 0 else {
            return 0
        }
        let currentTime = time.clamped(to: 0...totalDuration)
        let previousTime = max(0, currentTime - sampleInterval)
        let elapsed = max(1 / 240, currentTime - previousTime)
        let currentZoom = ZoomMotionResolver.state(
            at: currentTime,
            zooms: zooms,
            totalDuration: totalDuration,
            motion: zoomMotion
        )
        let previousZoom = ZoomMotionResolver.state(
            at: previousTime,
            zooms: zooms,
            totalDuration: totalDuration,
            motion: zoomMotion
        )
        let currentTransform = transformState(
            resolved: currentZoom,
            fallbackFocus: previousZoom?.zoom
        )
        let previousTransform = transformState(
            resolved: previousZoom,
            fallbackFocus: currentZoom?.zoom
        )
        let zoomVelocity = abs(
            currentTransform.scale - previousTransform.scale
        ) / elapsed
        let panVelocity = hypot(
            currentTransform.translationX - previousTransform.translationX,
            currentTransform.translationY - previousTransform.translationY
        ) / elapsed
        let screenMotion = min(1, zoomVelocity / 4) * style.zoomAmount
            + min(1, panVelocity / 1.2) * style.panAmount
        let referenceSize = max(
            1,
            min(renderSize.width, renderSize.height)
        )
        return (
            style.strength
                * referenceSize
                * 0.012
                * min(1.5, screenMotion)
        ).clamped(to: 0...36)
    }

    private static func transformState(
        resolved: ResolvedZoomMotion?,
        fallbackFocus: ZoomEvent?
    ) -> (
        scale: CGFloat,
        translationX: CGFloat,
        translationY: CGFloat
    ) {
        let scale = resolved?.scale ?? 1
        let focusX = resolved?.focusX
            ?? fallbackFocus?.focusX
            ?? 0.5
        let focusY = resolved?.focusY
            ?? fallbackFocus?.focusY
            ?? 0.5
        return (
            scale,
            (1 - scale) * (focusX - 0.5),
            (1 - scale) * (focusY - 0.5)
        )
    }
}
