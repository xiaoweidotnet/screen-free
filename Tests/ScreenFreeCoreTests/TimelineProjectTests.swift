import XCTest
@testable import ScreenFreeCore

final class TimelineProjectTests: XCTestCase {
    func testAnnotationRoundTripActivationAndRangeClamping() throws {
        let annotation = EmphasisAnnotation(
            kind: .rectangle,
            start: 1,
            duration: 2,
            normalizedStartX: 0.2,
            normalizedStartY: 0.25,
            normalizedEndX: 0.8,
            normalizedEndY: 0.7
        )
        var project = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 5)],
            annotations: [annotation]
        )
        XCTAssertTrue(project.activeAnnotations(atTimelineTime: 2).contains(annotation))
        XCTAssertTrue(
            project.setAnnotationRange(
                id: annotation.id,
                start: 4.5,
                duration: 4
            )
        )
        XCTAssertEqual(project.annotations[0].start, 4.5, accuracy: 0.001)
        XCTAssertEqual(project.annotations[0].duration, 0.5, accuracy: 0.001)

        let decoded = try JSONDecoder().decode(
            TimelineProject.self,
            from: JSONEncoder().encode(project)
        )
        XCTAssertEqual(decoded, project)

        let legacy = """
        {"clips":[],"zooms":[],"cursorSamples":[],"clicks":[],"captions":[],"shortcuts":[],"redactions":[]}
        """.data(using: .utf8)!
        XCTAssertTrue(
            try JSONDecoder().decode(
                TimelineProject.self,
                from: legacy
            ).annotations.isEmpty
        )
    }

    func testTimelineScaleFitsZoomsAndPreservesDragMapping() {
        let viewportWidth: CGFloat = 820
        let duration: TimeInterval = 137.5
        let fit = TimelineScale(zoom: TimelineScale.fitZoom)
        let fitWidth = fit.contentWidth(viewportWidth: viewportWidth)
        XCTAssertEqual(fitWidth, viewportWidth, accuracy: 0.001)
        for projectDuration in [0.2, 3_600.0] {
            XCTAssertEqual(
                fit.x(
                    forTime: projectDuration,
                    duration: projectDuration,
                    contentWidth: fitWidth
                ),
                viewportWidth,
                accuracy: 0.001
            )
        }

        let zoomed = TimelineScale(zoom: 4)
        let zoomedWidth = zoomed.contentWidth(viewportWidth: viewportWidth)
        XCTAssertEqual(zoomedWidth, viewportWidth * 4, accuracy: 0.001)

        let time: TimeInterval = 84.25
        let x = zoomed.x(
            forTime: time,
            duration: duration,
            contentWidth: zoomedWidth
        )
        XCTAssertEqual(
            zoomed.time(
                atX: x,
                duration: duration,
                contentWidth: zoomedWidth
            ),
            time,
            accuracy: 0.000_001
        )

        let dragPoints: CGFloat = 96
        let expectedDelta = Double(dragPoints / zoomedWidth) * duration
        XCTAssertEqual(
            zoomed.timeDelta(
                forPointDistance: dragPoints,
                duration: duration,
                contentWidth: zoomedWidth
            ),
            expectedDelta,
            accuracy: 0.000_001
        )
    }

    func testMaximumTimelineZoomAllowsSubTenthSecondEditingForLongVideo() {
        let viewportWidth: CGFloat = 820
        let duration: TimeInterval = 3_600
        let scale = TimelineScale(zoom: TimelineScale.maximumZoom)
        let contentWidth = scale.contentWidth(viewportWidth: viewportWidth)

        XCTAssertLessThanOrEqual(
            scale.timeDelta(
                forPointDistance: 1,
                duration: duration,
                contentWidth: contentWidth
            ),
            0.1
        )
    }

    func testPlaybackFollowMovesTheViewportAndReleasesItWhenPaused() throws {
        let started = TimelinePlaybackFollowPolicy.resolve(
            playheadX: 700,
            visibleMinX: 0,
            viewportWidth: 800,
            contentWidth: 1_720,
            isPlaying: true,
            wasFollowing: false
        )
        XCTAssertTrue(started.isFollowing)
        XCTAssertEqual(
            try XCTUnwrap(started.targetScrollX),
            140,
            accuracy: 0.001
        )

        let continued = TimelinePlaybackFollowPolicy.resolve(
            playheadX: 760,
            visibleMinX: 140,
            viewportWidth: 800,
            contentWidth: 1_720,
            isPlaying: true,
            wasFollowing: true
        )
        XCTAssertTrue(continued.isFollowing)
        XCTAssertEqual(
            try XCTUnwrap(continued.targetScrollX),
            200,
            accuracy: 0.001
        )

        let paused = TimelinePlaybackFollowPolicy.resolve(
            playheadX: 760,
            visibleMinX: 200,
            viewportWidth: 800,
            contentWidth: 1_720,
            isPlaying: false,
            wasFollowing: true
        )
        XCTAssertFalse(paused.isFollowing)
        XCTAssertNil(paused.targetScrollX)
    }

    func testPlaybackFollowReturnsToTheBeginningAfterReplay() throws {
        let replayed = TimelinePlaybackFollowPolicy.resolve(
            playheadX: 0,
            visibleMinX: 920,
            viewportWidth: 800,
            contentWidth: 1_720,
            isPlaying: true,
            wasFollowing: false
        )

        XCTAssertTrue(replayed.isFollowing)
        XCTAssertEqual(
            try XCTUnwrap(replayed.targetScrollX),
            0,
            accuracy: 0.001
        )
    }

    func testPlaybackFollowDoesNotMoveAFittedOrComfortablyVisibleTimeline() {
        let fitted = TimelinePlaybackFollowPolicy.resolve(
            playheadX: 700,
            visibleMinX: 0,
            viewportWidth: 800,
            contentWidth: 800,
            isPlaying: true,
            wasFollowing: false
        )
        XCTAssertFalse(fitted.isFollowing)
        XCTAssertNil(fitted.targetScrollX)

        let comfortablyVisible = TimelinePlaybackFollowPolicy.resolve(
            playheadX: 400,
            visibleMinX: 0,
            viewportWidth: 800,
            contentWidth: 1_720,
            isPlaying: true,
            wasFollowing: false
        )
        XCTAssertFalse(comfortablyVisible.isFollowing)
        XCTAssertNil(comfortablyVisible.targetScrollX)
    }

    func testCursorTailFreezeAndReturnUseResolvedPositions() throws {
        let project = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 10)],
            cursorSamples: [
                CursorSample(time: 2, normalizedX: 0.2, normalizedY: 0.2),
                CursorSample(time: 7, normalizedX: 0.7, normalizedY: 0.7),
                CursorSample(time: 9.5, normalizedX: 0.95, normalizedY: 0.95)
            ]
        )

        let moving = try XCTUnwrap(
            project.cursorSample(
                atTimelineTime: 9.8,
                freezeBeforeEnd: 0
            )
        )
        XCTAssertEqual(moving.normalizedX, 0.95, accuracy: 0.001)

        let smoothed = try XCTUnwrap(
            project.cursorSample(
                atTimelineTime: 4.5,
                freezeBeforeEnd: 0,
                smoothMovement: true
            )
        )
        XCTAssertEqual(smoothed.normalizedX, 0.45, accuracy: 0.001)
        XCTAssertEqual(smoothed.normalizedY, 0.45, accuracy: 0.001)
        let unsmoothed = try XCTUnwrap(
            project.cursorSample(
                atTimelineTime: 4.5,
                freezeBeforeEnd: 0,
                smoothMovement: false
            )
        )
        XCTAssertNotEqual(
            unsmoothed.normalizedX,
            smoothed.normalizedX,
            accuracy: 0.001
        )

        let frozen = try XCTUnwrap(
            project.cursorSample(
                atTimelineTime: 9.8,
                freezeBeforeEnd: 2
            )
        )
        XCTAssertEqual(frozen.normalizedX, 0.7, accuracy: 0.001)
        XCTAssertEqual(frozen.normalizedY, 0.7, accuracy: 0.001)

        let returning = try XCTUnwrap(
            project.cursorSample(
                atTimelineTime: 9.5,
                freezeBeforeEnd: 2,
                loopToStart: true
            )
        )
        XCTAssertEqual(returning.normalizedX, 0.45, accuracy: 0.001)
        XCTAssertEqual(returning.normalizedY, 0.45, accuracy: 0.001)

        let returned = try XCTUnwrap(
            project.cursorSample(
                atTimelineTime: 10,
                freezeBeforeEnd: 2,
                loopToStart: true
            )
        )
        XCTAssertEqual(returned.normalizedX, 0.2, accuracy: 0.001)
        XCTAssertEqual(returned.normalizedY, 0.2, accuracy: 0.001)
        XCTAssertEqual(
            TimelineProject.cursorReturnDuration(for: 2),
            0.4,
            accuracy: 0.001
        )
        XCTAssertEqual(
            TimelineProject.cursorReturnDuration(for: 30),
            1,
            accuracy: 0.001
        )

        let jitterProject = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 1)],
            cursorSamples: [
                CursorSample(time: 0, normalizedX: 0, normalizedY: 0),
                CursorSample(time: 0.05, normalizedX: 0.6, normalizedY: 0.6),
                CursorSample(time: 0.1, normalizedX: 0.005, normalizedY: 0.005),
                CursorSample(time: 1, normalizedX: 0.4, normalizedY: 0.4)
            ]
        )
        let cleaned = jitterProject.processedCursorSamples(
            removeShakes: true,
            shakeThreshold: 0.02,
            optimizeRapidChanges: false
        )
        XCTAssertEqual(cleaned.count, 3)
        XCTAssertFalse(cleaned.contains { $0.time == 0.05 })

        let rapidProject = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 1)],
            cursorSamples: [
                CursorSample(time: 0, normalizedX: 0, normalizedY: 0.4),
                CursorSample(time: 0.03, normalizedX: 1, normalizedY: 0.4),
                CursorSample(time: 0.06, normalizedX: 1, normalizedY: 0.4)
            ]
        )
        let optimized = rapidProject.processedCursorSamples(
            removeShakes: false,
            shakeThreshold: 0.02,
            optimizeRapidChanges: true
        )
        XCTAssertEqual(optimized[1].normalizedX, 0.8, accuracy: 0.001)
        XCTAssertEqual(optimized[1].normalizedY, 0.4, accuracy: 0.001)
    }

    func testZoomRangeCanResizeFromEitherEdgeAndClampsToTimeline() {
        let zoom = ZoomEvent(
            start: 2,
            duration: 2,
            scale: 1.8,
            focusX: 0.5,
            focusY: 0.5
        )
        var project = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 10)],
            zooms: [zoom]
        )

        XCTAssertTrue(project.setZoomRange(id: zoom.id, start: 1, duration: 5))
        XCTAssertEqual(project.zooms[0].start, 1, accuracy: 0.001)
        XCTAssertEqual(project.zooms[0].duration, 5, accuracy: 0.001)

        XCTAssertTrue(project.setZoomRange(id: zoom.id, start: 9.9, duration: 4))
        XCTAssertEqual(project.zooms[0].start, 9.9, accuracy: 0.001)
        XCTAssertEqual(project.zooms[0].duration, 0.1, accuracy: 0.001)
    }

    func testZoomRangeEditsStopAtNeighborBoundaries() throws {
        let first = ZoomEvent(
            start: 1,
            duration: 2,
            scale: 1.8,
            focusX: 0.3,
            focusY: 0.4
        )
        let second = ZoomEvent(
            start: 4,
            duration: 2,
            scale: 1.8,
            focusX: 0.7,
            focusY: 0.6
        )
        var project = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 10)],
            zooms: [first, second]
        )

        XCTAssertTrue(
            project.setZoomRange(
                id: first.id,
                start: first.start,
                duration: 5,
                edit: .resizeTrailing
            )
        )
        XCTAssertEqual(project.zooms[0].end, 4, accuracy: 0.001)

        XCTAssertTrue(
            project.setZoomRange(
                id: second.id,
                start: 2,
                duration: 2,
                edit: .move
            )
        )
        let movedSecond = try XCTUnwrap(
            project.zooms.first { $0.id == second.id }
        )
        XCTAssertEqual(movedSecond.start, 4, accuracy: 0.001)
        XCTAssertEqual(movedSecond.duration, 2, accuracy: 0.001)

        XCTAssertTrue(
            project.setZoomRange(
                id: second.id,
                start: 2,
                duration: 4,
                edit: .resizeLeading
            )
        )
        let resizedSecond = try XCTUnwrap(
            project.zooms.first { $0.id == second.id }
        )
        XCTAssertEqual(resizedSecond.start, 4, accuracy: 0.001)
        XCTAssertEqual(resizedSecond.end, 6, accuracy: 0.001)
    }

    func testInsertingZoomRejectsOccupiedStartAndStopsAtNextZoom() throws {
        let existing = ZoomEvent(
            start: 2,
            duration: 2,
            scale: 1.8,
            focusX: 0.5,
            focusY: 0.5
        )
        var project = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 10)],
            zooms: [existing]
        )

        let occupied = ZoomEvent(
            start: 3,
            duration: 1,
            scale: 2,
            focusX: 0.7,
            focusY: 0.4
        )
        XCTAssertFalse(project.insertZoom(occupied))
        XCTAssertEqual(project.zooms.count, 1)

        let before = ZoomEvent(
            start: 0.5,
            duration: 4,
            scale: 2,
            focusX: 0.2,
            focusY: 0.3
        )
        XCTAssertTrue(project.insertZoom(before))
        let inserted = try XCTUnwrap(
            project.zooms.first { $0.id == before.id }
        )
        XCTAssertEqual(inserted.start, 0.5, accuracy: 0.001)
        XCTAssertEqual(inserted.end, existing.start, accuracy: 0.001)
    }

    func testLegacyOverlappingZoomsNormalizeToAdjacentRanges() {
        let first = ZoomEvent(
            start: 1,
            duration: 4,
            scale: 1.8,
            focusX: 0.3,
            focusY: 0.4
        )
        let second = ZoomEvent(
            start: 3,
            duration: 3,
            scale: 2,
            focusX: 0.7,
            focusY: 0.6
        )

        let project = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 8)],
            zooms: [first, second]
        )

        XCTAssertEqual(project.zooms.count, 2)
        XCTAssertEqual(project.zooms[0].end, project.zooms[1].start, accuracy: 0.001)
        XCTAssertFalse(project.hasOverlappingZooms)
    }

    func testZoomCanSplitIntoEditableSegmentsWithoutChangingItsLook() throws {
        let zoom = ZoomEvent(
            start: 1,
            duration: 5,
            scale: 2.1,
            focusX: 0.72,
            focusY: 0.34,
            followsCursor: false
        )
        var project = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 8)],
            zooms: [zoom]
        )

        let rightID = try XCTUnwrap(
            project.splitZoom(id: zoom.id, atTimelineTime: 3.25)
        )

        XCTAssertEqual(project.zooms.count, 2)
        XCTAssertEqual(project.zooms[0].start, 1, accuracy: 0.001)
        XCTAssertEqual(project.zooms[0].duration, 2.25, accuracy: 0.001)
        XCTAssertEqual(project.zooms[1].id, rightID)
        XCTAssertEqual(project.zooms[1].start, 3.25, accuracy: 0.001)
        XCTAssertEqual(project.zooms[1].duration, 2.75, accuracy: 0.001)
        XCTAssertEqual(project.zooms[1].scale, 2.1, accuracy: 0.001)
        XCTAssertEqual(project.zooms[1].focusX, 0.72, accuracy: 0.001)
        XCTAssertEqual(project.zooms[1].focusY, 0.34, accuracy: 0.001)
        XCTAssertEqual(project.zooms[1].followsCursor, false)
    }

    func testPrivacyRedactionRangeResizesAndClampsToTimeline() throws {
        let redaction = PrivacyRedaction(
            start: 2,
            duration: 2,
            normalizedX: 0.7,
            normalizedY: 0.3
        )
        var project = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 10)],
            redactions: [redaction]
        )

        XCTAssertTrue(
            project.setRedactionRange(
                id: redaction.id,
                start: 1,
                duration: 5
            )
        )
        XCTAssertEqual(project.redactions[0].start, 1, accuracy: 0.001)
        XCTAssertEqual(project.redactions[0].duration, 5, accuracy: 0.001)
        XCTAssertEqual(
            project.activeRedactions(atTimelineTime: 3).map(\.id),
            [redaction.id]
        )

        XCTAssertTrue(
            project.setRedactionRange(
                id: redaction.id,
                start: 9.95,
                duration: 4
            )
        )
        XCTAssertEqual(project.redactions[0].start, 9.9, accuracy: 0.001)
        XCTAssertEqual(project.redactions[0].duration, 0.1, accuracy: 0.001)
        XCTAssertTrue(project.activeRedactions(atTimelineTime: 4).isEmpty)

        project.clips[0].duration = 5
        project.clampTimedEventsToDuration()
        XCTAssertTrue(project.redactions.isEmpty)

        let spotlight = PrivacyRedaction(
            start: 1,
            presentation: .spotlight,
            highlightHue: 0.6
        )
        project.redactions.append(spotlight)
        let decoded = try JSONDecoder().decode(
            TimelineProject.self,
            from: JSONEncoder().encode(project)
        )
        XCTAssertEqual(
            decoded.redactions.last?.resolvedPresentation,
            .spotlight
        )
        XCTAssertEqual(
            decoded.redactions.last?.resolvedHighlightHue,
            0.6
        )
    }

    func testProjectRoundTripsForCrashRecovery() throws {
        let project = TimelineProject(
            clips: [
                TimelineClip(
                    sourceStart: 1.25,
                    duration: 8,
                    playbackRate: 1.4,
                    volume: 0.72
                )
            ],
            zooms: [
                ZoomEvent(
                    start: 2,
                    duration: 3.4,
                    scale: 2,
                    focusX: 0.2,
                    focusY: 0.8
                )
            ],
            cursorSamples: [
                CursorSample(time: 1, normalizedX: 0.4, normalizedY: 0.6)
            ],
            clicks: [
                MouseClick(time: 1.1, normalizedX: 0.4, normalizedY: 0.6)
            ],
            shortcuts: [
                ShortcutEvent(time: 1.2, label: "⌘K")
            ],
            redactions: [
                PrivacyRedaction(
                    start: 1.3,
                    duration: 0.8,
                    normalizedX: 0.4,
                    normalizedY: 0.6
                )
            ]
        )

        let decoded = try JSONDecoder().decode(
            TimelineProject.self,
            from: JSONEncoder().encode(project)
        )
        XCTAssertEqual(decoded, project)

        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(project)
            ) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "shortcuts")
        legacyObject.removeValue(forKey: "redactions")
        let legacyData = try JSONSerialization.data(
            withJSONObject: legacyObject
        )
        let legacy = try JSONDecoder().decode(
            TimelineProject.self,
            from: legacyData
        )
        XCTAssertTrue(legacy.shortcuts.isEmpty)
        XCTAssertTrue(legacy.redactions.isEmpty)
    }

    func testSplitPreservesDurationAndSourceContinuity() {
        let clip = TimelineClip(sourceStart: 4, duration: 10)
        var project = TimelineProject(clips: [clip])

        XCTAssertTrue(project.split(clipID: clip.id, atTimelineTime: 3.5))
        XCTAssertEqual(project.clips.count, 2)
        XCTAssertEqual(project.duration, 10, accuracy: 0.001)
        XCTAssertEqual(project.clips[0].sourceStart, 4, accuracy: 0.001)
        XCTAssertEqual(project.clips[1].sourceStart, 7.5, accuracy: 0.001)
    }

    func testMergeRestoresContiguousClipsWithoutLosingSettings() throws {
        let clip = TimelineClip(
            sourceStart: 4,
            duration: 10,
            playbackRate: 1.4,
            volume: 0.72
        )
        var project = TimelineProject(clips: [clip])
        XCTAssertTrue(project.split(clipID: clip.id, atTimelineTime: 3))
        let firstID = try XCTUnwrap(project.clips.first?.id)

        let mergedID = try XCTUnwrap(
            project.merge(clipID: firstID, withNext: true)
        )
        XCTAssertEqual(project.clips.count, 1)
        XCTAssertEqual(project.clips[0].id, mergedID)
        XCTAssertEqual(project.clips[0].sourceStart, 4, accuracy: 0.001)
        XCTAssertEqual(project.clips[0].duration, 10, accuracy: 0.001)
        XCTAssertEqual(project.clips[0].playbackRate, 1.4, accuracy: 0.001)
        XCTAssertEqual(project.clips[0].volume, 0.72, accuracy: 0.001)

        XCTAssertTrue(project.split(clipID: mergedID, atTimelineTime: 2))
        project.clips[1].volume = 0.5
        let before = project.clips
        XCTAssertNil(
            project.merge(
                clipID: try XCTUnwrap(project.clips.first?.id),
                withNext: true
            )
        )
        XCTAssertEqual(project.clips, before)
    }

    func testPlaybackRateChangesTimelineDurationAndSplitSourcePoint() {
        let clip = TimelineClip(sourceStart: 0, duration: 10, playbackRate: 2)
        var project = TimelineProject(clips: [clip])

        XCTAssertEqual(project.duration, 5, accuracy: 0.001)
        XCTAssertTrue(project.split(clipID: clip.id, atTimelineTime: 2))
        XCTAssertEqual(project.clips[0].duration, 4, accuracy: 0.001)
        XCTAssertEqual(project.clips[1].sourceStart, 4, accuracy: 0.001)
    }

    func testTrimStartMovesSourceAndShortensClip() {
        let clip = TimelineClip(sourceStart: 2, duration: 5)
        var project = TimelineProject(clips: [clip])

        XCTAssertTrue(project.trimStart(clipID: clip.id, by: 0.5))
        XCTAssertEqual(project.clips[0].sourceStart, 2.5, accuracy: 0.001)
        XCTAssertEqual(project.clips[0].duration, 4.5, accuracy: 0.001)
    }

    func testResetTrimRestoresOnlyTheAvailableSourceRange() throws {
        let clip = TimelineClip(
            sourceStart: 0,
            duration: 10,
            playbackRate: 1.4,
            volume: 0.72
        )
        var project = TimelineProject(clips: [clip])
        XCTAssertTrue(project.trimStart(clipID: clip.id, by: 1))
        XCTAssertTrue(project.trimEnd(clipID: clip.id, by: 1))
        XCTAssertTrue(
            project.resetTrim(
                clipID: clip.id,
                sourceDuration: 10
            )
        )
        XCTAssertEqual(project.clips[0].sourceStart, 0, accuracy: 0.001)
        XCTAssertEqual(project.clips[0].duration, 10, accuracy: 0.001)
        XCTAssertEqual(project.clips[0].playbackRate, 1.4, accuracy: 0.001)
        XCTAssertEqual(project.clips[0].volume, 0.72, accuracy: 0.001)

        let restoredID = project.clips[0].id
        XCTAssertTrue(
            project.split(
                clipID: restoredID,
                atTimelineTime: 4 / 1.4
            )
        )
        let firstID = try XCTUnwrap(project.clips.first?.id)
        XCTAssertTrue(project.trimEnd(clipID: firstID, by: 0.5))
        XCTAssertTrue(
            project.resetTrim(
                clipID: firstID,
                sourceDuration: 10
            )
        )
        XCTAssertEqual(project.clips[0].sourceEnd, 4, accuracy: 0.001)
        XCTAssertEqual(project.clips[1].sourceStart, 4, accuracy: 0.001)
    }

    func testAutomaticZoomsFollowClicksAndCoalesceBursts() {
        var project = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 5)],
            clicks: [
                MouseClick(time: 1, normalizedX: 0.2, normalizedY: 0.3),
                MouseClick(time: 1.2, normalizedX: 0.25, normalizedY: 0.35),
                MouseClick(time: 3, normalizedX: 0.8, normalizedY: 0.7)
            ]
        )

        project.generateZoomsFromClicks()

        XCTAssertEqual(project.zooms.count, 2)
        XCTAssertEqual(project.zooms[0].focusX, 0.2, accuracy: 0.001)
        XCTAssertEqual(project.zooms[1].focusY, 0.7, accuracy: 0.001)
        XCTAssertTrue(project.zooms.allSatisfy(\.resolvedFollowsCursor))
        XCTAssertFalse(project.hasOverlappingZooms)
        XCTAssertLessThanOrEqual(
            project.zooms[0].end,
            project.zooms[1].start
        )
    }

    func testRightMouseHoldKeepsAutomaticZoomActiveUntilRelease() {
        var project = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 10)],
            clicks: [
                MouseClick(
                    time: 2,
                    normalizedX: 0.65,
                    normalizedY: 0.35,
                    button: .right,
                    holdDuration: 4
                )
            ]
        )

        project.generateZoomsFromClicks(duration: 3.2)

        XCTAssertEqual(project.zooms.count, 1)
        XCTAssertEqual(project.zooms[0].start, 1.85, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(
            project.zooms[0].end,
            7.6,
            "A held right button should stay zoomed through release and ease out."
        )
    }

    func testRightMouseHoldExtendsANearbyClickZoomUntilRelease() {
        var project = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 10)],
            clicks: [
                MouseClick(
                    time: 1,
                    normalizedX: 0.3,
                    normalizedY: 0.4,
                    button: .left
                ),
                MouseClick(
                    time: 1.2,
                    normalizedX: 0.65,
                    normalizedY: 0.35,
                    button: .right,
                    holdDuration: 4
                )
            ]
        )

        project.generateZoomsFromClicks(duration: 3.2)

        XCTAssertEqual(project.zooms.count, 1)
        XCTAssertGreaterThanOrEqual(
            project.zooms[0].end,
            6.8,
            "A coalesced right hold must extend the active zoom through release."
        )
    }

    func testCursorMovementAndShortRightClicksDoNotCreateAutomaticZooms() {
        var movementOnly = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 5)],
            cursorSamples: [
                CursorSample(time: 0.5, normalizedX: 0.1, normalizedY: 0.2),
                CursorSample(time: 1.0, normalizedX: 0.5, normalizedY: 0.6),
                CursorSample(time: 1.5, normalizedX: 0.9, normalizedY: 0.3)
            ]
        )

        movementOnly.generateZoomsFromClicks()

        XCTAssertTrue(
            movementOnly.zooms.isEmpty,
            "Cursor movement records focus positions, not zoom triggers."
        )

        var shortRightClick = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 5)],
            clicks: [
                MouseClick(
                    time: 1,
                    normalizedX: 0.5,
                    normalizedY: 0.5,
                    button: .right,
                    holdDuration: 0.12
                )
            ]
        )

        shortRightClick.generateZoomsFromClicks()

        XCTAssertTrue(
            shortRightClick.zooms.isEmpty,
            "A normal right click must not be treated as a long-press zoom."
        )
    }

    func testSourceEventsRemapAfterTrim() {
        let clip = TimelineClip(sourceStart: 5, duration: 4)
        var project = TimelineProject(
            clips: [clip],
            clicks: [MouseClick(time: 6, normalizedX: 0.4, normalizedY: 0.6)]
        )

        project.generateZoomsFromClicks()

        XCTAssertEqual(project.zooms.count, 1)
        XCTAssertEqual(project.zooms[0].start, 0.85, accuracy: 0.001)
        XCTAssertEqual(
            try XCTUnwrap(project.sourceTime(forTimelineTime: 2)),
            7,
            accuracy: 0.001
        )
    }
}
