import Foundation

/// Transition template applied at a cut between two adjacent clips.
/// The transition lives inside the existing clip ranges (half on the
/// outgoing clip, half on the incoming clip), so timeline timing is
/// unchanged and preview/playback mapping stays 1:1.
public enum ClipTransitionStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Dip to black.
    case fade = "Fade"
    /// Dip to white.
    case flash = "Flash"
    /// Scale punch into and out of the cut.
    case zoom = "Zoom"

    public var id: Self { self }

    public var dipsToWhite: Bool { self == .flash }
}

/// A transition anchored to the junction between two adjacent clips,
/// identified by the clips' ids so it survives re-trimming either side.
public struct ClipTransition: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var leftClipID: UUID
    public var rightClipID: UUID
    public var style: ClipTransitionStyle
    public var duration: TimeInterval

    public init(
        id: UUID = UUID(),
        leftClipID: UUID,
        rightClipID: UUID,
        style: ClipTransitionStyle,
        duration: TimeInterval
    ) {
        self.id = id
        self.leftClipID = leftClipID
        self.rightClipID = rightClipID
        self.style = style
        self.duration = duration
    }
}

/// A cut between two adjacent clips with its transition, if one is placed.
public struct TransitionJunction: Equatable, Sendable {
    public var leftClipID: UUID
    public var rightClipID: UUID
    /// Timeline time of the cut.
    public var time: TimeInterval
    public var transition: ClipTransition?

    public init(
        leftClipID: UUID,
        rightClipID: UUID,
        time: TimeInterval,
        transition: ClipTransition?
    ) {
        self.leftClipID = leftClipID
        self.rightClipID = rightClipID
        self.time = time
        self.transition = transition
    }
}

/// Per-instant visual state produced by a transition, shared by the live
/// preview and the export pipeline.
public struct ClipTransitionFrame: Equatable, Sendable {
    /// Opacity of the dip overlay (black or white), 0...1.
    public var dipOpacity: Double
    /// Whether the dip overlay is white (flash) rather than black (fade).
    public var dipIsWhite: Bool
    /// Extra scale multiplier applied to the video content, 1 when idle.
    public var contentScale: Double

    public init(dipOpacity: Double, dipIsWhite: Bool, contentScale: Double) {
        self.dipOpacity = dipOpacity
        self.dipIsWhite = dipIsWhite
        self.contentScale = contentScale
    }

    public static let identity = ClipTransitionFrame(
        dipOpacity: 0,
        dipIsWhite: false,
        contentScale: 1
    )
}

public enum ClipTransitionResolver {
    /// Peak extra scale applied by the zoom template at the cut point.
    public static let maxScaleBoost = 0.15

    public static let minimumDuration = 0.2
    public static let maximumDuration = 1.2

    public static func frame(
        junctions: [TransitionJunction],
        at time: TimeInterval
    ) -> ClipTransitionFrame {
        for junction in junctions {
            guard let transition = junction.transition,
                  transition.duration > 0 else { continue }
            let half = transition.duration / 2
            let delta = time - junction.time
            guard abs(delta) < half else { continue }
            // 0 at the window edges, 1 exactly on the cut.
            let closeness = 1 - abs(delta) / half
            let eased = smoothstep(closeness)
            switch transition.style {
            case .fade, .flash:
                return ClipTransitionFrame(
                    dipOpacity: eased,
                    dipIsWhite: transition.style.dipsToWhite,
                    contentScale: 1
                )
            case .zoom:
                return ClipTransitionFrame(
                    dipOpacity: 0,
                    dipIsWhite: false,
                    contentScale: 1 + maxScaleBoost * eased
                )
            }
        }
        return .identity
    }

    private static func smoothstep(_ x: Double) -> Double {
        let t = min(1, max(0, x))
        return t * t * (3 - 2 * t)
    }
}

extension TimelineProject {
    /// Every cut between adjacent clips, in timeline order, paired with the
    /// transition anchored to it (if any).
    public func transitionJunctions() -> [TransitionJunction] {
        var result: [TransitionJunction] = []
        var cursor: TimeInterval = 0
        for index in clips.indices.dropLast() {
            cursor += clips[index].timelineDuration
            let left = clips[index]
            let right = clips[index + 1]
            let transition = transitions.first {
                $0.leftClipID == left.id && $0.rightClipID == right.id
            }
            result.append(
                TransitionJunction(
                    leftClipID: left.id,
                    rightClipID: right.id,
                    time: cursor,
                    transition: transition
                )
            )
        }
        return result
    }

    /// Inserts or updates the transition anchored to the same junction,
    /// preserving the existing transition's id when replacing it.
    public mutating func setTransition(_ transition: ClipTransition) {
        if let index = transitions.firstIndex(where: {
            $0.leftClipID == transition.leftClipID
                && $0.rightClipID == transition.rightClipID
        }) {
            transitions[index] = ClipTransition(
                id: transitions[index].id,
                leftClipID: transition.leftClipID,
                rightClipID: transition.rightClipID,
                style: transition.style,
                duration: transition.duration
            )
        } else if let index = transitions.firstIndex(where: {
            $0.id == transition.id
        }) {
            transitions[index] = transition
        } else {
            transitions.append(transition)
        }
    }

    /// Drops transitions whose clip pair is no longer adjacent (after
    /// splits, merges, or deletions).
    public mutating func pruneTransitions() {
        guard !transitions.isEmpty else { return }
        var adjacentPairs: Set<String> = []
        for index in clips.indices.dropLast() {
            adjacentPairs.insert(
                "\(clips[index].id.uuidString)|\(clips[index + 1].id.uuidString)"
            )
        }
        transitions.removeAll {
            !adjacentPairs.contains(
                "\($0.leftClipID.uuidString)|\($0.rightClipID.uuidString)"
            )
        }
    }

    /// Removes silent source footage from the very start of the first clip
    /// and the very end of the last clip. Interior silence is preserved.
    /// `waveform` is the normalized per-bin amplitude envelope over the whole
    /// source asset (0 marks silence). Returns true when anything changed.
    @discardableResult
    public mutating func trimSilenceAtEdges(
        waveform: [Float],
        sourceDuration: TimeInterval,
        padding: TimeInterval = 0.15
    ) -> Bool {
        guard sourceDuration > 0, !waveform.isEmpty, !clips.isEmpty else {
            return false
        }
        guard let firstAudibleBin = waveform.firstIndex(where: { $0 > 0 }),
              let lastAudibleBin = waveform.lastIndex(where: { $0 > 0 }) else {
            return false
        }
        let binDuration = sourceDuration / Double(waveform.count)
        let firstAudible = max(
            0,
            Double(firstAudibleBin) * binDuration - padding
        )
        let lastAudible = min(
            sourceDuration,
            Double(lastAudibleBin + 1) * binDuration + padding
        )

        var changed = false
        // Head: drop whole leading clips that end at or before the first
        // audible moment, then trim the new first clip's start.
        while clips.count > 1, clips[0].sourceEnd <= firstAudible + 0.01 {
            clips.removeFirst()
            changed = true
        }
        let firstClip = clips[0]
        if firstAudible > firstClip.sourceStart + 0.01 {
            let newStart = min(firstAudible, firstClip.sourceEnd - 0.1)
            clips[0].duration -= newStart - clips[0].sourceStart
            clips[0].sourceStart = newStart
            changed = true
        }
        // Tail: drop whole trailing clips that start at or after the last
        // audible moment, then trim the new last clip's end.
        while clips.count > 1,
              clips[clips.count - 1].sourceStart >= lastAudible - 0.01 {
            clips.removeLast()
            changed = true
        }
        let lastIndex = clips.count - 1
        let lastClip = clips[lastIndex]
        if lastAudible < lastClip.sourceEnd - 0.01 {
            let newEnd = max(lastAudible, lastClip.sourceStart + 0.1)
            clips[lastIndex].duration = newEnd - clips[lastIndex].sourceStart
            changed = true
        }
        if changed {
            clampTimedEventsToDuration()
        }
        return changed
    }
}
