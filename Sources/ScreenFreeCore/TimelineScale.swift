import CoreGraphics
import Foundation

/// A single source of truth for converting timeline time into horizontal points.
public struct TimelineScale: Equatable, Sendable {
    public static let fitZoom = 1.0
    /// 64× keeps an hour-long recording below one tenth of a second per point
    /// on a typical editor viewport while Fit still shows the whole timeline.
    public static let maximumZoom = 64.0
    public static let stepFactor = Double(2).squareRoot()

    public let zoom: Double

    public init(zoom: Double) {
        self.zoom = zoom.clamped(to: Self.fitZoom...Self.maximumZoom)
    }

    public func contentWidth(viewportWidth: CGFloat) -> CGFloat {
        max(1, viewportWidth) * CGFloat(zoom)
    }

    public func x(
        forTime time: TimeInterval,
        duration: TimeInterval,
        contentWidth: CGFloat
    ) -> CGFloat {
        guard duration > 0 else { return 0 }
        let normalized = (time / duration).clamped(to: 0...1)
        return contentWidth * CGFloat(normalized)
    }

    public func time(
        atX x: CGFloat,
        duration: TimeInterval,
        contentWidth: CGFloat
    ) -> TimeInterval {
        guard contentWidth > 0 else { return 0 }
        let normalized = Double(x / contentWidth).clamped(to: 0...1)
        return duration * normalized
    }

    public func timeDelta(
        forPointDistance distance: CGFloat,
        duration: TimeInterval,
        contentWidth: CGFloat
    ) -> TimeInterval {
        guard contentWidth > 0 else { return 0 }
        return Double(distance / contentWidth) * duration
    }
}

public struct TimelinePlaybackFollowDecision: Equatable, Sendable {
    public var targetScrollX: CGFloat?
    public var isFollowing: Bool

    public init(
        targetScrollX: CGFloat?,
        isFollowing: Bool
    ) {
        self.targetScrollX = targetScrollX
        self.isFollowing = isFollowing
    }
}

public enum TimelinePlaybackFollowPolicy {
    private static let trailingActivationFraction: CGFloat = 0.78
    private static let leadingActivationFraction: CGFloat = 0.12
    private static let followedPlayheadFraction: CGFloat = 0.70

    public static func resolve(
        playheadX: CGFloat,
        visibleMinX: CGFloat,
        viewportWidth: CGFloat,
        contentWidth: CGFloat,
        isPlaying: Bool,
        wasFollowing: Bool
    ) -> TimelinePlaybackFollowDecision {
        let safeViewportWidth = max(1, viewportWidth)
        let safeContentWidth = max(safeViewportWidth, contentWidth)
        guard isPlaying,
              safeContentWidth > safeViewportWidth + 1,
              playheadX.isFinite,
              visibleMinX.isFinite else {
            return TimelinePlaybackFollowDecision(
                targetScrollX: nil,
                isFollowing: false
            )
        }

        let maximumScrollX = safeContentWidth - safeViewportWidth
        let safeVisibleMinX = visibleMinX.clamped(to: 0...maximumScrollX)
        let leadingActivationX = safeVisibleMinX
            + safeViewportWidth * leadingActivationFraction
        let trailingActivationX = safeVisibleMinX
            + safeViewportWidth * trailingActivationFraction
        let shouldStartFollowing = playheadX < leadingActivationX
            || playheadX > trailingActivationX
        let isFollowing = wasFollowing || shouldStartFollowing
        guard isFollowing else {
            return TimelinePlaybackFollowDecision(
                targetScrollX: nil,
                isFollowing: false
            )
        }

        let targetScrollX = (
            playheadX - safeViewportWidth * followedPlayheadFraction
        ).clamped(to: 0...maximumScrollX)
        return TimelinePlaybackFollowDecision(
            targetScrollX: targetScrollX,
            isFollowing: true
        )
    }
}
