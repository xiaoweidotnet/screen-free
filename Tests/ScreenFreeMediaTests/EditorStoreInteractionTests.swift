import AppKit
import ScreenFreeCore
import XCTest
@testable import ScreenFree

@MainActor
final class EditorStoreInteractionTests: XCTestCase {
    func testTimelineUndoRoutingDefersToEditableTextResponders() {
        let textView = NSTextView()
        textView.isEditable = true
        let textField = NSTextField()
        textField.isEditable = true

        XCTAssertFalse(
            ScreenFreeUndoRouting.shouldRouteToTimeline(
                firstResponder: textView
            )
        )
        XCTAssertFalse(
            ScreenFreeUndoRouting.shouldRouteToTimeline(
                firstResponder: textField
            )
        )
        XCTAssertTrue(
            ScreenFreeUndoRouting.shouldRouteToTimeline(
                firstResponder: NSButton()
            )
        )
    }

    func testRecordingDefaultsIncludeSystemAudioAndMicrophone() {
        let store = EditorStore()

        XCTAssertEqual(store.systemAudioMode, .all)
        XCTAssertTrue(store.recordMicrophone)
        XCTAssertEqual(store.zoomDuration, 3.2, accuracy: 0.001)
    }

    func testZoomDefaultsFollowCursorWithoutMotionBlur() {
        let store = EditorStore()
        let zoom = ZoomEvent(
            start: 0,
            focusX: 0.5,
            focusY: 0.5
        )

        XCTAssertFalse(
            store.motionBlurEnabled,
            "Motion blur should remain an opt-in zoom effect."
        )
        XCTAssertTrue(
            zoom.resolvedFollowsCursor,
            "New and legacy zooms should follow the recorded cursor by default."
        )

        let fixedFocusZoom = ZoomEvent(
            start: 0,
            focusX: 0.5,
            focusY: 0.5,
            followsCursor: false
        )
        XCTAssertFalse(
            fixedFocusZoom.resolvedFollowsCursor,
            "An explicit fixed-focus choice must override the default."
        )
    }

    func testMultipleMicrophonesRequireAnExplicitChoiceBeforeRecording() {
        XCTAssertFalse(
            MicrophoneSelectionPolicy.requiresPrompt(
                recordsMicrophone: false,
                availableMicrophoneCount: 3,
                selectionWasConfirmed: false
            )
        )
        XCTAssertFalse(
            MicrophoneSelectionPolicy.requiresPrompt(
                recordsMicrophone: true,
                availableMicrophoneCount: 1,
                selectionWasConfirmed: false
            )
        )
        XCTAssertTrue(
            MicrophoneSelectionPolicy.requiresPrompt(
                recordsMicrophone: true,
                availableMicrophoneCount: 3,
                selectionWasConfirmed: false
            )
        )
        XCTAssertFalse(
            MicrophoneSelectionPolicy.requiresPrompt(
                recordsMicrophone: true,
                availableMicrophoneCount: 3,
                selectionWasConfirmed: true
            )
        )
    }

    func testSilentSystemTrackDoesNotAttenuateTheMicrophone() {
        let dualTrackMix = RecordedAudioMixStyle(
            layout: RecordedAudioLayout(
                systemTrackIndex: 0,
                microphoneTrackIndex: 1
            ),
            systemVolume: 1,
            microphoneVolume: 1,
            microphoneMuted: false,
            trackPeaks: [0.000_01, 0.95],
            trackPeakEnvelopes: [
                [0.000_01, 0.000_01],
                [0.2, 0.95]
            ]
        )

        XCTAssertEqual(
            dualTrackMix.gain(forTrackAt: 0),
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            dualTrackMix.gain(forTrackAt: 1),
            1,
            accuracy: 0.001
        )

        let systemOnlyMix = RecordedAudioMixStyle(
            layout: dualTrackMix.layout,
            systemVolume: 1,
            microphoneVolume: 1,
            microphoneMuted: true,
            trackPeaks: [0.000_01, 0.95],
            trackPeakEnvelopes: dualTrackMix.trackPeakEnvelopes
        )
        XCTAssertEqual(
            systemOnlyMix.gain(forTrackAt: 0),
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            systemOnlyMix.gain(forTrackAt: 1),
            0,
            accuracy: 0.001
        )
    }

    func testActuallyLoudTracksReserveOnlyTheHeadroomTheyNeed() {
        let mix = RecordedAudioMixStyle(
            layout: RecordedAudioLayout(
                systemTrackIndex: 0,
                microphoneTrackIndex: 1
            ),
            systemVolume: 1,
            microphoneVolume: 1,
            microphoneMuted: false,
            trackPeaks: [0.8, 0.4],
            trackPeakEnvelopes: [
                [0.8, 0.1],
                [0.4, 0.1]
            ]
        )

        let systemGain = mix.gain(forTrackAt: 0)
        let microphoneGain = mix.gain(forTrackAt: 1)
        let predictedPeak = 0.8 * systemGain + 0.4 * microphoneGain

        XCTAssertGreaterThan(systemGain, 0.7)
        XCTAssertEqual(systemGain, microphoneGain, accuracy: 0.001)
        XCTAssertLessThanOrEqual(predictedPeak, 0.892)
    }

    func testNonConcurrentTrackPeaksDoNotConsumeSharedHeadroom() {
        let mix = RecordedAudioMixStyle(
            layout: RecordedAudioLayout(
                systemTrackIndex: 0,
                microphoneTrackIndex: 1
            ),
            systemVolume: 1,
            microphoneVolume: 1,
            microphoneMuted: false,
            trackPeaks: [0.8, 0.6],
            trackPeakEnvelopes: [
                [0.8, 0.05, 0.02],
                [0.02, 0.05, 0.6]
            ]
        )

        XCTAssertEqual(mix.gain(forTrackAt: 0), 1, accuracy: 0.001)
        XCTAssertEqual(mix.gain(forTrackAt: 1), 1, accuracy: 0.001)
    }

    func testDualTrackVolumeBoostRemainsLouderAfterHeadroomProtection() {
        let mix = RecordedAudioMixStyle(
            layout: RecordedAudioLayout(
                systemTrackIndex: 0,
                microphoneTrackIndex: 1
            ),
            systemVolume: 1,
            microphoneVolume: 1,
            microphoneMuted: false,
            trackPeaks: [0.8, 0.4],
            trackPeakEnvelopes: [
                [0.8, 0.1],
                [0.4, 0.1]
            ]
        )
        let normalGain = mix.gain(
            forTrackAt: 0,
            clipVolume: 1
        )
        let boostedGain = mix.gain(
            forTrackAt: 0,
            clipVolume: 1.6
        )
        let boostedConcurrentPeak = (
            0.8 * boostedGain
                + 0.4 * mix.gain(
                    forTrackAt: 1,
                    clipVolume: 1.6
                )
        )

        XCTAssertGreaterThan(boostedGain, normalGain)
        XCTAssertLessThan(boostedConcurrentPeak, 1)
    }

    func testDualTrackVolumeBoostKeepsFullGainWhenConcurrentPeaksAreSafe() {
        let mix = RecordedAudioMixStyle(
            layout: RecordedAudioLayout(
                systemTrackIndex: 0,
                microphoneTrackIndex: 1
            ),
            systemVolume: 1,
            microphoneVolume: 1,
            microphoneMuted: false,
            trackPeaks: [0.28, 0.22],
            trackPeakEnvelopes: [
                [0.28, 0.05],
                [0.22, 0.05]
            ]
        )

        XCTAssertEqual(
            mix.gain(forTrackAt: 0, clipVolume: 1.6),
            1.6,
            accuracy: 0.001
        )
        XCTAssertEqual(
            mix.gain(forTrackAt: 1, clipVolume: 1.6),
            1.6,
            accuracy: 0.001
        )
    }

    func testSingleTrackHighGainIsCappedAtMinusOneDecibel() {
        let mix = RecordedAudioMixStyle(
            layout: RecordedAudioLayout(
                systemTrackIndex: nil,
                microphoneTrackIndex: 0
            ),
            systemVolume: 1,
            microphoneVolume: 1,
            microphoneMuted: false,
            trackPeaks: [0.8],
            trackPeakEnvelopes: [[0.2, 0.8, 0.3]]
        )

        let gain = mix.gain(forTrackAt: 0, clipVolume: 1.6)

        XCTAssertGreaterThan(gain, 1)
        XCTAssertLessThanOrEqual(0.8 * gain, 0.892)
    }

    func testNearFullScaleSingleTrackStaysUnityAndRejectsUnsafeBoost() {
        let mix = RecordedAudioMixStyle(
            layout: RecordedAudioLayout(
                systemTrackIndex: nil,
                microphoneTrackIndex: 0
            ),
            systemVolume: 1,
            microphoneVolume: 1,
            microphoneMuted: false,
            trackPeaks: [0.95],
            trackPeakEnvelopes: [[0.2, 0.95, 0.3]]
        )

        XCTAssertEqual(mix.gain(forTrackAt: 0), 1, accuracy: 0.001)
        XCTAssertEqual(
            mix.gain(forTrackAt: 0, clipVolume: 1.6),
            1,
            accuracy: 0.001
        )
    }

    func testClipVolumeAboveUnityIsAppliedByTheAudioMix() {
        let mix = RecordedAudioMixStyle(
            layout: RecordedAudioLayout(
                systemTrackIndex: nil,
                microphoneTrackIndex: 0
            ),
            systemVolume: 1,
            microphoneVolume: 1,
            microphoneMuted: false,
            trackPeaks: [0.3]
        )

        XCTAssertEqual(
            mix.gain(forTrackAt: 0, clipVolume: 1.6),
            1.6,
            accuracy: 0.001
        )
    }

    func testDeleteCommandRemovesTheSelectedTimelineBlock() {
        let store = EditorStore()
        let zoom = ZoomEvent(
            start: 1,
            duration: 2,
            scale: 1.8,
            focusX: 0.5,
            focusY: 0.5
        )
        store.project = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 5)],
            zooms: [zoom]
        )
        store.selectedZoomID = zoom.id
        store.inspectorPanel = .zoom

        store.deleteCurrentSelection()

        XCTAssertTrue(store.project.zooms.isEmpty)
        XCTAssertNil(store.selectedZoomID)
    }

    func testDeleteCommandPrefersTheTimelineBlockUnderThePointer() {
        let store = EditorStore()
        let selectedZoom = ZoomEvent(
            start: 0.5,
            duration: 1,
            scale: 1.8,
            focusX: 0.3,
            focusY: 0.4
        )
        let hoveredZoom = ZoomEvent(
            start: 3,
            duration: 1,
            scale: 2,
            focusX: 0.7,
            focusY: 0.6
        )
        store.project = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 6)],
            zooms: [selectedZoom, hoveredZoom]
        )
        store.selectedZoomID = selectedZoom.id
        store.inspectorPanel = .zoom
        store.setHoveredTimelineBlock(.zoom(hoveredZoom.id), hovering: true)

        store.deleteCurrentSelection()

        XCTAssertEqual(store.project.zooms.map(\.id), [selectedZoom.id])
        XCTAssertEqual(store.selectedZoomID, selectedZoom.id)
    }

    func testLeavingAnOldBlockDoesNotClearTheNewHoveredBlock() {
        let store = EditorStore()
        let firstID = UUID()
        let secondID = UUID()

        store.setHoveredTimelineBlock(.clip(firstID), hovering: true)
        store.setHoveredTimelineBlock(.zoom(secondID), hovering: true)
        store.setHoveredTimelineBlock(.clip(firstID), hovering: false)

        XCTAssertEqual(store.hoveredTimelineBlock, .zoom(secondID))
    }

    func testUndoDoesNotRestoreAHoverTargetMissingFromTheProject() {
        let store = EditorStore()
        let clip = TimelineClip(sourceStart: 0, duration: 5)
        store.project = TimelineProject(clips: [clip])
        store.selectedClipID = clip.id
        store.setHoveredTimelineBlock(.zoom(UUID()), hovering: true)

        store.updateSelectedClip(volume: 1.5)
        store.undoTimelineEdit()

        XCTAssertNil(store.hoveredTimelineBlock)
    }

    func testDeleteKeyRemovesTheClipUnderThePointerAndUndoRestoresEverything() {
        let store = EditorStore()
        let first = TimelineClip(sourceStart: 0, duration: 2)
        let second = TimelineClip(sourceStart: 2, duration: 2)
        let third = TimelineClip(sourceStart: 4, duration: 2)
        let trailingZoom = ZoomEvent(
            start: 5,
            duration: 0.8,
            focusX: 0.5,
            focusY: 0.5
        )
        let trailingAnnotation = EmphasisAnnotation(
            kind: .rectangle,
            start: 5,
            duration: 0.8,
            normalizedStartX: 0.2,
            normalizedStartY: 0.2,
            normalizedEndX: 0.8,
            normalizedEndY: 0.8
        )
        let originalProject = TimelineProject(
            clips: [first, second, third],
            zooms: [trailingZoom],
            annotations: [trailingAnnotation]
        )
        store.project = originalProject
        store.selectedClipID = third.id
        store.inspectorPanel = .clip
        store.playhead = 5.5
        store.toggleSplitTool()

        store.setHoveredClip(atTimelineTime: 1)
        XCTAssertEqual(store.hoveredTimelineBlock, .clip(first.id))
        XCTAssertTrue(store.handleDeleteKey())

        XCTAssertEqual(store.project.clips.map(\.id), [second.id, third.id])
        XCTAssertTrue(store.project.zooms.isEmpty)
        XCTAssertTrue(store.project.annotations.isEmpty)
        XCTAssertEqual(store.timelineUndoTitle, "Undo Delete Clip")

        store.undoTimelineEdit()

        XCTAssertEqual(store.project, originalProject)
        XCTAssertEqual(store.selectedClipID, third.id)
        XCTAssertEqual(store.playhead, 5.5, accuracy: 0.001)
        XCTAssertEqual(store.activeTimelineTool, .split)
    }

    func testSplitUndoAndRedoAreSingleAtomicTimelineEdits() {
        let store = EditorStore()
        let originalProject = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 10)]
        )
        store.project = originalProject

        store.split(at: 4)

        let splitProject = store.project
        XCTAssertEqual(splitProject.clips.count, 2)
        XCTAssertEqual(store.timelineUndoTitle, "Undo Split Clip")

        store.undoTimelineEdit()

        XCTAssertEqual(store.project, originalProject)
        XCTAssertEqual(store.timelineRedoTitle, "Redo Split Clip")

        store.redoTimelineEdit()

        XCTAssertEqual(store.project, splitProject)
    }

    func testContinuousClipAdjustmentCreatesOneUndoAfterAnEarlierEdit() {
        let store = EditorStore()
        store.project = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 10)]
        )
        store.split(at: 5)
        let adjustedClipID = try! XCTUnwrap(store.selectedClipID)

        store.beginContinuousTimelineEdit(.clip)
        store.updateSelectedClip(playbackRate: 1.25)
        store.updateSelectedClip(playbackRate: 1.5)
        store.updateSelectedClip(playbackRate: 2)
        store.endContinuousTimelineEdit()

        XCTAssertEqual(store.project.clips.count, 2)
        XCTAssertEqual(
            store.project.clips.first { $0.id == adjustedClipID }?.playbackRate,
            2
        )
        XCTAssertEqual(store.timelineUndoTitle, "Undo Edit Clip")

        store.undoTimelineEdit()

        XCTAssertEqual(store.project.clips.count, 2)
        XCTAssertEqual(
            store.project.clips.first { $0.id == adjustedClipID }?.playbackRate,
            1
        )
        XCTAssertEqual(store.timelineUndoTitle, "Undo Split Clip")
    }

    func testAClipAdjustmentAfterUndoClearsRedoImmediately() {
        let store = EditorStore()
        let clip = TimelineClip(sourceStart: 0, duration: 10)
        store.project = TimelineProject(clips: [clip])
        store.selectedClipID = clip.id

        store.updateSelectedClip(volume: 1.5)
        store.undoTimelineEdit()
        XCTAssertEqual(store.timelineRedoTitle, "Redo Edit Clip")

        store.beginContinuousTimelineEdit(.clip)
        store.updateSelectedClip(volume: 1.25)

        XCTAssertNil(store.timelineRedoTitle)

        store.endContinuousTimelineEdit()
        XCTAssertEqual(store.timelineUndoTitle, "Undo Edit Clip")
    }

    func testDiscreteEditCommitsAnUnfinishedContinuousEditFirst() {
        let store = EditorStore()
        let clip = TimelineClip(sourceStart: 0, duration: 10)
        store.project = TimelineProject(clips: [clip])
        store.selectedClipID = clip.id

        store.beginContinuousTimelineEdit(.clip)
        store.updateSelectedClip(volume: 1.5)
        store.split(at: 5)

        XCTAssertEqual(store.timelineUndoTitle, "Undo Split Clip")

        store.undoTimelineEdit()

        XCTAssertEqual(store.project.clips.count, 1)
        XCTAssertEqual(store.project.clips[0].volume, 1.5)
        XCTAssertEqual(store.timelineUndoTitle, "Undo Edit Clip")

        store.undoTimelineEdit()

        XCTAssertEqual(store.project.clips[0].volume, 1)
    }

    func testContinuousZoomRangeScaleAndFocusAdjustmentIsAtomic() {
        let store = EditorStore()
        let zoom = ZoomEvent(
            start: 1,
            duration: 2,
            scale: 1.8,
            focusX: 0.5,
            focusY: 0.5
        )
        store.project = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 10)],
            zooms: [zoom]
        )
        store.selectedZoomID = zoom.id

        store.beginContinuousTimelineEdit(.zoom)
        store.setZoomRange(
            id: zoom.id,
            start: 2,
            duration: 2,
            edit: .move
        )
        store.setZoomRange(
            id: zoom.id,
            start: 3,
            duration: 2.5,
            edit: .move
        )
        store.updateSelectedZoom(scale: 2.4)
        store.moveSelectedZoomFocus(x: 0.8, y: 0.2)
        store.endContinuousTimelineEdit()

        XCTAssertEqual(store.timelineUndoTitle, "Undo Edit Zoom")

        store.undoTimelineEdit()

        XCTAssertEqual(store.project.zooms, [zoom])
        XCTAssertNil(store.timelineUndoTitle)
    }

    func testRedactionAndAnnotationDragsCreateSeparateAtomicUndos() {
        let store = EditorStore()
        let redaction = PrivacyRedaction(
            start: 1,
            duration: 2,
            normalizedX: 0.5,
            normalizedY: 0.5
        )
        let annotation = EmphasisAnnotation(
            kind: .rectangle,
            start: 2,
            duration: 2,
            normalizedStartX: 0.2,
            normalizedStartY: 0.2,
            normalizedEndX: 0.8,
            normalizedEndY: 0.8
        )
        store.project = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 10)],
            redactions: [redaction],
            annotations: [annotation]
        )
        store.selectedRedactionID = redaction.id
        store.selectedAnnotationID = annotation.id

        store.beginContinuousTimelineEdit(.redaction)
        store.setRedactionRange(id: redaction.id, start: 3, duration: 2.5)
        store.updateSelectedRedaction(width: 0.3, opacity: 0.8)
        store.moveSelectedRedaction(x: 0.7, y: 0.3)
        store.endContinuousTimelineEdit()
        let redactionEditedProject = store.project

        store.beginContinuousTimelineEdit(.annotation)
        store.setAnnotationRange(id: annotation.id, start: 4, duration: 1.5)
        store.setAnnotationRange(id: annotation.id, start: 5, duration: 1)
        store.endContinuousTimelineEdit()

        XCTAssertEqual(store.timelineUndoTitle, "Undo Edit Annotation")

        store.undoTimelineEdit()

        XCTAssertEqual(store.project, redactionEditedProject)
        XCTAssertEqual(store.timelineUndoTitle, "Undo Edit Privacy Block")

        store.undoTimelineEdit()

        XCTAssertEqual(store.project.redactions, [redaction])
        XCTAssertEqual(store.project.annotations, [annotation])
    }

    func testSplitToolStaysActiveAcrossPointSplitsAndEscapeCancelsIt() {
        let store = EditorStore()
        store.project = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 10)]
        )

        store.toggleSplitTool()
        XCTAssertEqual(store.activeTimelineTool, .split)

        store.split(at: 2)
        store.split(at: 6)

        XCTAssertEqual(store.project.clips.count, 3)
        XCTAssertEqual(store.activeTimelineTool, .split)

        store.cancelTimelineTool()

        XCTAssertEqual(store.activeTimelineTool, .selection)
    }

    func testEscapeIsConsumedOnlyWhenAnEditingToolIsActive() {
        let store = EditorStore()

        XCTAssertFalse(store.handleEscape())

        store.toggleSplitTool()

        XCTAssertTrue(store.handleEscape())
        XCTAssertEqual(store.activeTimelineTool, .selection)
        XCTAssertFalse(store.handleEscape())
    }

    func testContiguousClipBoundaryKeepsTheExistingTransportRunning() {
        let first = TimelineClip(
            sourceStart: 0,
            duration: 2,
            playbackRate: 1,
            volume: 1
        )
        let second = TimelineClip(
            sourceStart: 2,
            duration: 3,
            playbackRate: 1,
            volume: 1
        )

        XCTAssertEqual(
            EditorStore.playbackBoundaryAction(from: first, to: second),
            .continueTransport
        )
    }

    func testDiscontinuousClipBoundarySeeksToTheNextSourceRange() {
        let first = TimelineClip(
            sourceStart: 0,
            duration: 2,
            playbackRate: 1,
            volume: 1
        )
        let second = TimelineClip(
            sourceStart: 5,
            duration: 3,
            playbackRate: 1,
            volume: 1
        )

        XCTAssertEqual(
            EditorStore.playbackBoundaryAction(from: first, to: second),
            .seek
        )
    }
}
