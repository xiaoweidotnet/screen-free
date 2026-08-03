import XCTest
@testable import ScreenFreeCore

private func twoClips() -> [TimelineClip] {
    [
        TimelineClip(sourceStart: 0, duration: 4),
        TimelineClip(sourceStart: 4, duration: 4)
    ]
}

private func fadeJunction(
    left: TimelineClip,
    right: TimelineClip,
    time: TimeInterval,
    style: ClipTransitionStyle = .fade,
    duration: TimeInterval = 0.4
) -> TransitionJunction {
    TransitionJunction(
        leftClipID: left.id,
        rightClipID: right.id,
        time: time,
        transition: ClipTransition(
            leftClipID: left.id,
            rightClipID: right.id,
            style: style,
            duration: duration
        )
    )
}

final class ClipTransitionResolverTests: XCTestCase {
    func testJunctionWithoutTransitionIsIdentity() {
        let clips = twoClips()
        let junction = TransitionJunction(
            leftClipID: clips[0].id,
            rightClipID: clips[1].id,
            time: 4,
            transition: nil
        )
        XCTAssertEqual(
            ClipTransitionResolver.frame(junctions: [junction], at: 4),
            .identity
        )
    }

    func testFadePeaksAtCutAndIsZeroOutsideWindow() {
        let clips = twoClips()
        let junctions = [fadeJunction(left: clips[0], right: clips[1], time: 4)]

        let atCut = ClipTransitionResolver.frame(junctions: junctions, at: 4)
        XCTAssertEqual(atCut.dipOpacity, 1, accuracy: 0.001)
        XCTAssertFalse(atCut.dipIsWhite)
        XCTAssertEqual(atCut.contentScale, 1, accuracy: 0.001)

        let halfWayIn = ClipTransitionResolver.frame(
            junctions: junctions,
            at: 3.9
        )
        XCTAssertGreaterThan(halfWayIn.dipOpacity, 0)
        XCTAssertLessThan(halfWayIn.dipOpacity, 1)

        let outside = ClipTransitionResolver.frame(
            junctions: junctions,
            at: 3.7
        )
        XCTAssertEqual(outside, .identity)
    }

    func testFlashDipsToWhite() {
        let clips = twoClips()
        let junctions = [
            fadeJunction(
                left: clips[0],
                right: clips[1],
                time: 4,
                style: .flash
            )
        ]
        let frame = ClipTransitionResolver.frame(junctions: junctions, at: 4)
        XCTAssertTrue(frame.dipIsWhite)
        XCTAssertEqual(frame.dipOpacity, 1, accuracy: 0.001)
    }

    func testZoomScalesUpTowardsCut() {
        let clips = twoClips()
        let junctions = [
            fadeJunction(
                left: clips[0],
                right: clips[1],
                time: 4,
                style: .zoom
            )
        ]
        let atCut = ClipTransitionResolver.frame(junctions: junctions, at: 4)
        XCTAssertEqual(
            atCut.contentScale,
            1 + ClipTransitionResolver.maxScaleBoost,
            accuracy: 0.001
        )
        XCTAssertEqual(atCut.dipOpacity, 0)

        let before = ClipTransitionResolver.frame(junctions: junctions, at: 3.9)
        let after = ClipTransitionResolver.frame(junctions: junctions, at: 4.1)
        XCTAssertEqual(before.contentScale, after.contentScale, accuracy: 0.001)
    }
}

final class TransitionJunctionTests: XCTestCase {
    func testJunctionsMapTransitionsToAdjacentClipPairs() {
        let clips = twoClips()
        let transition = ClipTransition(
            leftClipID: clips[0].id,
            rightClipID: clips[1].id,
            style: .fade,
            duration: 0.4
        )
        let project = TimelineProject(
            clips: clips,
            transitions: [transition]
        )

        let junctions = project.transitionJunctions()

        XCTAssertEqual(junctions.count, 1)
        XCTAssertEqual(junctions[0].time, 4, accuracy: 0.001)
        XCTAssertEqual(junctions[0].transition, transition)
    }

    func testSetTransitionReplacesSameJunctionKeepingID() {
        let clips = twoClips()
        var project = TimelineProject(clips: clips)
        let first = ClipTransition(
            leftClipID: clips[0].id,
            rightClipID: clips[1].id,
            style: .fade,
            duration: 0.4
        )
        project.setTransition(first)
        let replacement = ClipTransition(
            leftClipID: clips[0].id,
            rightClipID: clips[1].id,
            style: .zoom,
            duration: 0.6
        )
        project.setTransition(replacement)

        XCTAssertEqual(project.transitions.count, 1)
        XCTAssertEqual(project.transitions[0].id, first.id)
        XCTAssertEqual(project.transitions[0].style, .zoom)
    }

    func testPruneTransitionsDropsNonAdjacentPairs() {
        let clips = twoClips()
        var project = TimelineProject(
            clips: clips,
            transitions: [
                ClipTransition(
                    leftClipID: clips[0].id,
                    rightClipID: clips[1].id,
                    style: .fade,
                    duration: 0.4
                )
            ]
        )
        // Splitting the first clip invalidates the junction.
        XCTAssertTrue(
            project.split(clipID: clips[0].id, atTimelineTime: 2)
        )
        project.pruneTransitions()

        XCTAssertTrue(project.transitions.isEmpty)
    }

    func testTransitionsRoundTripThroughCodable() throws {
        let clips = twoClips()
        let project = TimelineProject(
            clips: clips,
            transitions: [
                ClipTransition(
                    leftClipID: clips[0].id,
                    rightClipID: clips[1].id,
                    style: .flash,
                    duration: 0.8
                )
            ]
        )
        let data = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(
            TimelineProject.self,
            from: data
        )

        XCTAssertEqual(decoded.transitions, project.transitions)
    }
}

final class TrimSilenceAtEdgesTests: XCTestCase {
    func testSilentHeadAndTailAreTrimmed() {
        var project = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 10)]
        )
        // 10 bins over 10s: bins 0-1 silent, 2-7 audible, 8-9 silent.
        let waveform: [Float] = [0, 0, 1, 1, 1, 1, 1, 1, 0, 0]

        let changed = project.trimSilenceAtEdges(
            waveform: waveform,
            sourceDuration: 10,
            padding: 0
        )

        XCTAssertTrue(changed)
        XCTAssertEqual(project.clips[0].sourceStart, 2, accuracy: 0.001)
        XCTAssertEqual(project.clips[0].duration, 6, accuracy: 0.001)
    }

    func testPaddingKeepsLeadInAndTail() {
        var project = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 10)]
        )
        let waveform: [Float] = [0, 0, 1, 1, 1, 1, 1, 1, 0, 0]

        project.trimSilenceAtEdges(
            waveform: waveform,
            sourceDuration: 10,
            padding: 0.5
        )

        XCTAssertEqual(project.clips[0].sourceStart, 1.5, accuracy: 0.001)
        XCTAssertEqual(project.clips[0].sourceEnd, 8.5, accuracy: 0.001)
    }

    func testFullySilentEdgeClipsAreRemoved() {
        var project = TimelineProject(
            clips: [
                TimelineClip(sourceStart: 0, duration: 2),
                TimelineClip(sourceStart: 2, duration: 6),
                TimelineClip(sourceStart: 8, duration: 2)
            ]
        )
        let waveform: [Float] = [0, 0, 1, 1, 1, 1, 1, 1, 0, 0]

        project.trimSilenceAtEdges(
            waveform: waveform,
            sourceDuration: 10,
            padding: 0
        )

        // The silent leading and trailing clips are dropped entirely.
        XCTAssertEqual(project.clips.count, 1)
        XCTAssertEqual(project.clips[0].sourceStart, 2, accuracy: 0.001)
        XCTAssertEqual(project.clips[0].sourceEnd, 8, accuracy: 0.001)
    }

    func testFullyAudibleRecordingDoesNothing() {
        var project = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 10)]
        )
        let waveform: [Float] = Array(repeating: 1, count: 10)

        XCTAssertFalse(
            project.trimSilenceAtEdges(
                waveform: waveform,
                sourceDuration: 10,
                padding: 0
            )
        )
        XCTAssertEqual(project.clips[0].duration, 10, accuracy: 0.001)
    }

    func testEmptyOrSilentWaveformDoesNothing() {
        var project = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 10)]
        )
        XCTAssertFalse(
            project.trimSilenceAtEdges(
                waveform: [],
                sourceDuration: 10,
                padding: 0
            )
        )
        XCTAssertFalse(
            project.trimSilenceAtEdges(
                waveform: [0, 0, 0, 0],
                sourceDuration: 10,
                padding: 0
            )
        )
    }
}
