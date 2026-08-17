import AppKit
import AVFoundation
import CoreImage
import CoreVideo
import ImageIO
import XCTest
@testable import ScreenFree
import ScreenFreeCore

final class VideoExporterTests: XCTestCase {
    @MainActor
    func testCursorPositionMatchesBetweenEditorFrameAndMP4Export() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.mp4")
        let cursorURL = directory.appendingPathComponent("cursor.mp4")
        let cleanURL = directory.appendingPathComponent("clean.mp4")
        try await makeSyntheticMedia(at: sourceURL)

        let project = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 1)],
            cursorSamples: [
                CursorSample(time: 0, normalizedX: 0.22, normalizedY: 0.76),
                CursorSample(time: 1, normalizedX: 0.22, normalizedY: 0.76)
            ]
        )
        var cursorStyle = CanvasRenderStyle.plain
        cursorStyle.cursorReplacement = .pointer
        cursorStyle.smoothCursorMovement = false
        var cleanStyle = cursorStyle
        cleanStyle.showCursor = false

        let exporter = VideoExporter()
        let editorFrame = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: project,
            timelineTime: 0.5,
            canvasStyle: cursorStyle,
            frameRate: 30
        )
        let cleanEditorFrame = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: project,
            timelineTime: 0.5,
            canvasStyle: cleanStyle,
            frameRate: 30
        )
        try await exporter.export(
            sourceURL: sourceURL,
            project: project,
            canvasStyle: cursorStyle,
            destinationURL: cursorURL,
            frameRate: 30
        )
        try await exporter.export(
            sourceURL: sourceURL,
            project: project,
            canvasStyle: cleanStyle,
            destinationURL: cleanURL,
            frameRate: 30
        )

        let time = CMTime(seconds: 0.5, preferredTimescale: 600)
        let cursorGenerator = AVAssetImageGenerator(
            asset: AVURLAsset(url: cursorURL)
        )
        cursorGenerator.requestedTimeToleranceBefore = .zero
        cursorGenerator.requestedTimeToleranceAfter = .zero
        let cleanGenerator = AVAssetImageGenerator(
            asset: AVURLAsset(url: cleanURL)
        )
        cleanGenerator.requestedTimeToleranceBefore = .zero
        cleanGenerator.requestedTimeToleranceAfter = .zero
        let exportedFrame = try await cursorGenerator.image(at: time).image
        let cleanExportedFrame = try await cleanGenerator.image(at: time).image

        let editorBounds = try XCTUnwrap(
            differenceBounds(editorFrame, cleanEditorFrame),
            "The editor frame must contain the editable cursor."
        )
        let exportedBounds = try XCTUnwrap(
            differenceBounds(exportedFrame, cleanExportedFrame),
            "The exported MP4 must contain the editable cursor."
        )
        XCTAssertEqual(editorBounds.midX, exportedBounds.midX, accuracy: 3)
        XCTAssertEqual(editorBounds.midY, exportedBounds.midY, accuracy: 3)
    }

    func testExportedVideoURLCanBeWrittenToPasteboard() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let videoURL = directory.appendingPathComponent("export.mp4")
        try Data("video".utf8).write(to: videoURL)
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("ScreenFreeTests.\(UUID().uuidString)")
        )
        defer { pasteboard.releaseGlobally() }

        try VideoPasteboardWriter().write(
            fileURL: videoURL,
            to: pasteboard
        )

        let copiedURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        XCTAssertEqual(
            copiedURLs?.first?.standardizedFileURL,
            videoURL.standardizedFileURL
        )
    }

    func testRapidZoomRendersFasterThanMellowZoom() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.mp4")
        try await makeSyntheticMedia(at: sourceURL)
        let project = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 1)],
            zooms: [
                ZoomEvent(
                    start: 0,
                    duration: 1,
                    scale: 2,
                    focusX: 0.8,
                    focusY: 0.4
                )
            ]
        )
        var mellowStyle = CanvasRenderStyle.plain
        mellowStyle.zoomMotion = .mellow
        var rapidStyle = CanvasRenderStyle.plain
        rapidStyle.zoomMotion = .rapid
        var customStyle = CanvasRenderStyle.plain
        customStyle.zoomMotion = ZoomMotionStyle(
            preset: .custom,
            customTransitionDuration: 0.6,
            customEasing: CubicBezierEasing(
                x1: 0.8,
                y1: 0,
                x2: 1,
                y2: 0.2
            )
        )
        let exporter = VideoExporter()
        let time = 1.0 / 15.0
        let mellowFrame = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: project,
            timelineTime: time,
            canvasStyle: mellowStyle,
            frameRate: 30
        )
        let rapidFrame = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: project,
            timelineTime: time,
            canvasStyle: rapidStyle,
            frameRate: 30
        )
        let customFrame = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: project,
            timelineTime: time,
            canvasStyle: customStyle,
            frameRate: 30
        )
        let mellowPixels = rgbaPixels(from: mellowFrame)
        let rapidPixels = rgbaPixels(from: rapidFrame)
        let difference = zip(mellowPixels, rapidPixels).reduce(0) {
            $0 + abs(Int($1.0) - Int($1.1))
        }
        XCTAssertGreaterThan(
            difference / max(1, mellowPixels.count),
            3,
            "Rapid and mellow presets should render materially different early zoom frames."
        )
        let customPixels = rgbaPixels(from: customFrame)
        let customDifference = zip(rapidPixels, customPixels).reduce(0) {
            $0 + abs(Int($1.0) - Int($1.1))
        }
        XCTAssertGreaterThan(
            customDifference / max(1, rapidPixels.count),
            3,
            "A custom cubic Bézier should reach the real renderer."
        )

        var blurredStyle = rapidStyle
        blurredStyle.motionBlur = MotionBlurStyle(
            enabled: true,
            strength: 1,
            cursorAmount: 0,
            zoomAmount: 1,
            panAmount: 1
        )
        let blurredFrame = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: project,
            timelineTime: time,
            canvasStyle: blurredStyle,
            frameRate: 30
        )
        let blurDifference = zip(
            rapidPixels,
            rgbaPixels(from: blurredFrame)
        ).reduce(0) {
            $0 + abs(Int($1.0) - Int($1.1))
        }
        XCTAssertGreaterThan(
            blurDifference,
            20_000,
            "Motion-dependent screen blur should reach current-frame rendering."
        )

        let sharpMP4 = directory.appendingPathComponent("sharp.mp4")
        let blurredMP4 = directory.appendingPathComponent("blurred.mp4")
        try await exporter.export(
            sourceURL: sourceURL,
            project: project,
            canvasStyle: rapidStyle,
            destinationURL: sharpMP4,
            frameRate: 30
        )
        try await exporter.export(
            sourceURL: sourceURL,
            project: project,
            canvasStyle: blurredStyle,
            destinationURL: blurredMP4,
            frameRate: 30
        )
        let sharpGenerator = AVAssetImageGenerator(
            asset: AVURLAsset(url: sharpMP4)
        )
        sharpGenerator.requestedTimeToleranceBefore = .zero
        sharpGenerator.requestedTimeToleranceAfter = .zero
        let blurredGenerator = AVAssetImageGenerator(
            asset: AVURLAsset(url: blurredMP4)
        )
        blurredGenerator.requestedTimeToleranceBefore = .zero
        blurredGenerator.requestedTimeToleranceAfter = .zero
        let requestedTime = CMTime(
            seconds: time,
            preferredTimescale: 600
        )
        let sharpExportFrame = try await sharpGenerator.image(
            at: requestedTime
        ).image
        let blurredExportFrame = try await blurredGenerator.image(
            at: requestedTime
        ).image
        let exportedBlurDifference = zip(
            rgbaPixels(from: sharpExportFrame),
            rgbaPixels(from: blurredExportFrame)
        ).reduce(0) {
            $0 + abs(Int($1.0) - Int($1.1))
        }
        XCTAssertGreaterThan(
            exportedBlurDifference,
            20_000,
            "Motion blur must be baked into the actual MP4."
        )

        let exitTime = 14.0 / 15.0
        let mellowExit = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: project,
            timelineTime: exitTime,
            canvasStyle: mellowStyle,
            frameRate: 30
        )
        let rapidExit = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: project,
            timelineTime: exitTime,
            canvasStyle: rapidStyle,
            frameRate: 30
        )
        let exitDifference = zip(
            rgbaPixels(from: mellowExit),
            rgbaPixels(from: rapidExit)
        ).reduce(0) {
            $0 + abs(Int($1.0) - Int($1.1))
        }
        XCTAssertGreaterThan(
            exitDifference / max(1, mellowPixels.count),
            3,
            "Rapid and mellow presets should keep their distinct easing while zooming out."
        )
    }

    func testAdjacentZoomsExportAsOneContinuousMagnifiedRegion() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.mp4")
        try await makeSyntheticMedia(at: sourceURL)
        let clip = TimelineClip(sourceStart: 0, duration: 1)
        let continuous = TimelineProject(
            clips: [clip],
            zooms: [
                ZoomEvent(
                    start: 0,
                    duration: 1,
                    scale: 2,
                    focusX: 0.72,
                    focusY: 0.38
                )
            ]
        )
        let adjacent = TimelineProject(
            clips: [clip],
            zooms: [
                ZoomEvent(
                    start: 0,
                    duration: 0.5,
                    scale: 2,
                    focusX: 0.72,
                    focusY: 0.38
                ),
                ZoomEvent(
                    start: 0.5,
                    duration: 0.5,
                    scale: 2,
                    focusX: 0.72,
                    focusY: 0.38
                )
            ]
        )
        let subframeGap = 1.0 / 240.0
        let visuallyAdjacent = TimelineProject(
            clips: [clip],
            zooms: [
                ZoomEvent(
                    start: 0,
                    duration: 0.5,
                    scale: 2,
                    focusX: 0.72,
                    focusY: 0.38
                ),
                ZoomEvent(
                    start: 0.5 + subframeGap,
                    duration: 0.5 - subframeGap,
                    scale: 2,
                    focusX: 0.72,
                    focusY: 0.38
                )
            ]
        )
        var style = CanvasRenderStyle.plain
        style.zoomMotion = .mellow
        let exporter = VideoExporter()
        let continuousFrame = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: continuous,
            timelineTime: 0.5,
            canvasStyle: style,
            frameRate: 30
        )
        let adjacentFrame = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: adjacent,
            timelineTime: 0.5,
            canvasStyle: style,
            frameRate: 30
        )
        let continuousPixels = rgbaPixels(from: continuousFrame)
        let adjacentPixels = rgbaPixels(from: adjacentFrame)
        let difference = zip(continuousPixels, adjacentPixels).reduce(0) {
            $0 + abs(Int($1.0) - Int($1.1))
        }

        XCTAssertLessThan(
            difference / max(1, continuousPixels.count),
            1,
            "Adjacent zooms should export like one continuous zoom at their boundary."
        )

        let gapTime = 0.5 + subframeGap / 2
        let continuousGapFrame = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: continuous,
            timelineTime: gapTime,
            canvasStyle: style,
            frameRate: 60
        )
        let visuallyAdjacentFrame = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: visuallyAdjacent,
            timelineTime: gapTime,
            canvasStyle: style,
            frameRate: 60
        )
        let continuousGapPixels = rgbaPixels(from: continuousGapFrame)
        let visuallyAdjacentPixels = rgbaPixels(from: visuallyAdjacentFrame)
        let gapDifference = zip(
            continuousGapPixels,
            visuallyAdjacentPixels
        ).reduce(0) {
            $0 + abs(Int($1.0) - Int($1.1))
        }
        XCTAssertLessThan(
            gapDifference / max(1, continuousGapPixels.count),
            1,
            "A subframe timeline gap must not render an identity-scale flash."
        )
    }

    func testSelectedApplicationAudioIsMixedAsAnAlignedTrack() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.mp4")
        try await makeSyntheticMedia(at: sourceURL)
        let mixedURL = try await RecordingAudioMixer().mix(
            primaryURL: sourceURL,
            supplemental: SupplementalAudioRecording(
                url: sourceURL,
                firstPresentationTime: .zero
            ),
            primaryFirstPresentationTime: .zero
        )

        let mixedAsset = AVURLAsset(url: mixedURL)
        let duration = try await mixedAsset.load(.duration).seconds
        let videoTracks = try await mixedAsset.loadTracks(withMediaType: .video)
        let audioTracks = try await mixedAsset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(duration, 1, accuracy: 0.08)
        XCTAssertEqual(videoTracks.count, 1)
        XCTAssertEqual(audioTracks.count, 2)
        let analysis = try await AudioAnalyzer().analyze(
            url: mixedURL,
            bins: 16
        )
        XCTAssertEqual(
            analysis.trackPeaks.count,
            2,
            "Per-track peaks must stay aligned with the editable audio tracks."
        )
        XCTAssertTrue(
            analysis.trackPeaks.allSatisfy { $0 == 0 },
            "The synthetic silent tracks should retain two zero-valued peaks."
        )
        XCTAssertEqual(
            analysis.trackPeakEnvelopes.count,
            2,
            "Peak envelopes must stay aligned with editable audio tracks."
        )
        XCTAssertTrue(
            analysis.trackPeakEnvelopes.allSatisfy {
                $0.count == 16 && $0.allSatisfy { $0 == 0 }
            },
            "Silent tracks should have aligned, zero-valued time bins."
        )
        let resumedURL = try await RecordingSegmentMerger().merge(
            [mixedURL, mixedURL],
            fileExtension: "mp4"
        )
        let resumedAsset = AVURLAsset(url: resumedURL)
        let resumedDuration = try await resumedAsset.load(.duration).seconds
        let resumedAudioTracks = try await resumedAsset.loadTracks(
            withMediaType: .audio
        )
        XCTAssertEqual(resumedDuration, 2, accuracy: 0.08)
        XCTAssertEqual(
            resumedAudioTracks.count,
            2,
            "Pause/resume merging must preserve both deterministic source roles."
        )

        XCTAssertEqual(
            RecordedAudioLayout.recording(
                systemAudioMode: .all,
                recordMicrophone: true
            ),
            RecordedAudioLayout(
                systemTrackIndex: 0,
                microphoneTrackIndex: 1
            )
        )
        XCTAssertEqual(
            RecordedAudioLayout.recording(
                systemAudioMode: .selected,
                recordMicrophone: true
            ),
            RecordedAudioLayout(
                systemTrackIndex: 1,
                microphoneTrackIndex: 0
            )
        )
        XCTAssertEqual(
            RecordedAudioLayout.recording(
                systemAudioMode: .off,
                recordMicrophone: true
            ),
            RecordedAudioLayout(
                systemTrackIndex: nil,
                microphoneTrackIndex: 0
            )
        )
        XCTAssertEqual(
            RecordedAudioLayout.recording(
                systemAudioMode: .off,
                recordMicrophone: false
            ),
            RecordedAudioLayout(
                systemTrackIndex: nil,
                microphoneTrackIndex: nil
            )
        )

        let project = TimelineProject(
            clips: [
                TimelineClip(
                    sourceStart: 0,
                    duration: 1,
                    volume: 0.8
                )
            ]
        )
        let recordedAudioMix = RecordedAudioMixStyle(
            layout: RecordedAudioLayout(
                systemTrackIndex: 1,
                microphoneTrackIndex: 0
            ),
            systemVolume: 0.5,
            microphoneVolume: 1.5,
            microphoneMuted: true
        )
        let prepared = try await VideoExporter().prepare(
            sourceURL: mixedURL,
            recordedAudioMix: recordedAudioMix,
            project: project,
            frameRate: 15
        )
        let preparedAudioTracks = try await prepared.composition.loadTracks(
            withMediaType: .audio
        )
        XCTAssertEqual(preparedAudioTracks.count, 2)
        let preparedMix = try XCTUnwrap(prepared.audioMix)

        func volume(
            for track: AVAssetTrack
        ) throws -> Float {
            let parameters = try XCTUnwrap(
                preparedMix.inputParameters.first {
                    $0.trackID == track.trackID
                }
            )
            var startVolume: Float = -1
            var endVolume: Float = -1
            var timeRange = CMTimeRange.invalid
            XCTAssertTrue(
                parameters.getVolumeRamp(
                    for: .zero,
                    startVolume: &startVolume,
                    endVolume: &endVolume,
                    timeRange: &timeRange
                )
            )
            XCTAssertEqual(startVolume, endVolume, accuracy: 0.001)
            return startVolume
        }

        XCTAssertEqual(
            try volume(for: preparedAudioTracks[0]),
            Float(
                recordedAudioMix.gain(
                    forTrackAt: 0,
                    clipVolume: 0.8
                )
            ),
            accuracy: 0.001
        )
        XCTAssertEqual(
            try volume(for: preparedAudioTracks[1]),
            Float(
                recordedAudioMix.gain(
                    forTrackAt: 1,
                    clipVolume: 0.8
                )
            ),
            accuracy: 0.001
        )

        let outputURL = directory.appendingPathComponent("track-mix.mp4")
        try await VideoExporter().export(
            sourceURL: mixedURL,
            recordedAudioMix: recordedAudioMix,
            project: project,
            canvasStyle: .plain,
            destinationURL: outputURL,
            frameRate: 15
        )
        let exportedAudioTracks = try await AVURLAsset(url: outputURL)
            .loadTracks(withMediaType: .audio)
        XCTAssertEqual(
            exportedAudioTracks.count,
            1,
            "The two editable source tracks should become one consumer-ready MP4 mix."
        )
    }

    func testBackgroundMusicLoopsAcrossTimelineAndExports() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.mp4")
        let musicURL = directory.appendingPathComponent("music.caf")
        let outputURL = directory.appendingPathComponent("with-music.mp4")
        try await makeSyntheticMedia(at: sourceURL)
        try makeSilentAudio(at: musicURL, duration: 0.24)

        let project = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 1)]
        )
        let exporter = VideoExporter()
        let prepared = try await exporter.prepare(
            sourceURL: sourceURL,
            backgroundMusicURL: musicURL,
            backgroundMusicVolume: 0.35,
            project: project,
            frameRate: 15
        )
        let audioTracks = try await prepared.composition.loadTracks(
            withMediaType: .audio
        )
        XCTAssertEqual(audioTracks.count, 2)
        let musicTrack = try XCTUnwrap(audioTracks.last)
        let musicRange = try await musicTrack.load(.timeRange)
        XCTAssertEqual(musicRange.duration.seconds, 1, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(musicTrack.segments.count, 4)

        let musicParameters = try XCTUnwrap(
            prepared.audioMix?.inputParameters.first {
                $0.trackID == musicTrack.trackID
            }
        )
        var startVolume: Float = 0
        var endVolume: Float = 0
        var volumeRange = CMTimeRange.invalid
        XCTAssertTrue(
            musicParameters.getVolumeRamp(
                for: .zero,
                startVolume: &startVolume,
                endVolume: &endVolume,
                timeRange: &volumeRange
            )
        )
        XCTAssertEqual(startVolume, 0.35, accuracy: 0.001)
        XCTAssertEqual(endVolume, 0.35, accuracy: 0.001)

        try await exporter.export(
            sourceURL: sourceURL,
            backgroundMusicURL: musicURL,
            backgroundMusicVolume: 0.35,
            project: project,
            canvasStyle: .plain,
            destinationURL: outputURL,
            frameRate: 15
        )
        let exportedAsset = AVURLAsset(url: outputURL)
        let exportedAudioTracks = try await exportedAsset.loadTracks(
            withMediaType: .audio
        )
        let exportedDuration = try await exportedAsset.load(.duration).seconds
        XCTAssertFalse(exportedAudioTracks.isEmpty)
        XCTAssertEqual(exportedDuration, 1, accuracy: 0.08)
    }

    @MainActor
    func testPrivacyRedactionRendersIntoCurrentFrameAndMP4() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.mp4")
        let outputURL = directory.appendingPathComponent("redacted.mp4")
        let spotlightURL = directory.appendingPathComponent("spotlight.mp4")
        try await makeSyntheticMedia(
            at: sourceURL,
            highFrequencyPattern: true
        )
        let project = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 1)],
            redactions: [
                PrivacyRedaction(
                    start: 0.15,
                    duration: 0.5,
                    normalizedX: 0.5,
                    normalizedY: 0.5,
                    normalizedWidth: 0.32,
                    normalizedHeight: 0.28,
                    opacity: 1,
                    effect: .blur
                )
            ]
        )
        let exporter = VideoExporter()
        let currentFrame = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: project,
            timelineTime: 0.4,
            canvasStyle: .plain,
            frameRate: 15
        )
        let plainFrame = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: TimelineProject(
                clips: [TimelineClip(sourceStart: 0, duration: 1)]
            ),
            timelineTime: 0.4,
            canvasStyle: .plain,
            frameRate: 15
        )
        let currentCenter = pixel(
            in: rgbaPixels(from: currentFrame),
            width: currentFrame.width,
            x: currentFrame.width / 2,
            y: currentFrame.height / 2
        )
        XCTAssertGreaterThan(
            Int(currentCenter.red)
                + Int(currentCenter.green)
                + Int(currentCenter.blue),
            45,
            "A privacy mask should blur the source instead of replacing it with a black rectangle."
        )
        let currentPixels = rgbaPixels(from: currentFrame)
        let plainPixelsAtSameTime = rgbaPixels(from: plainFrame)
        let currentContrast = meanHorizontalContrast(
            currentPixels,
            width: currentFrame.width,
            height: currentFrame.height,
            normalizedRect: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        )
        let plainContrast = meanHorizontalContrast(
            plainPixelsAtSameTime,
            width: plainFrame.width,
            height: plainFrame.height,
            normalizedRect: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        )
        XCTAssertLessThan(
            currentContrast,
            plainContrast * 0.45,
            "The active privacy region must remove high-frequency detail in the current-frame renderer."
        )

        try await exporter.export(
            sourceURL: sourceURL,
            project: project,
            canvasStyle: .plain,
            destinationURL: outputURL,
            frameRate: 15
        )
        let generator = AVAssetImageGenerator(
            asset: AVURLAsset(url: outputURL)
        )
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let activeFrame = try await generator.image(
            at: CMTime(seconds: 0.4, preferredTimescale: 600)
        ).image
        let inactiveFrame = try await generator.image(
            at: CMTime(seconds: 0.9, preferredTimescale: 600)
        ).image
        let activeCenter = pixel(
            in: rgbaPixels(from: activeFrame),
            width: activeFrame.width,
            x: activeFrame.width / 2,
            y: activeFrame.height / 2
        )
        let inactiveCenter = pixel(
            in: rgbaPixels(from: inactiveFrame),
            width: inactiveFrame.width,
            x: inactiveFrame.width / 2,
            y: inactiveFrame.height / 2
        )
        XCTAssertGreaterThan(
            Int(activeCenter.red)
                + Int(activeCenter.green)
                + Int(activeCenter.blue),
            45,
            "The encoded MP4 must contain the same blurred privacy mask as the preview frame."
        )
        XCTAssertGreaterThan(
            Int(inactiveCenter.red)
                + Int(inactiveCenter.green)
                + Int(inactiveCenter.blue),
            80
        )
        XCTAssertLessThan(
            meanHorizontalContrast(
                rgbaPixels(from: activeFrame),
                width: activeFrame.width,
                height: activeFrame.height,
                normalizedRect: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
            ),
            meanHorizontalContrast(
                rgbaPixels(from: inactiveFrame),
                width: inactiveFrame.width,
                height: inactiveFrame.height,
                normalizedRect: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
            ) * 0.55,
            "The encoded MP4 must preserve the timed blur instead of only drawing an editor overlay."
        )

        let spotlightProject = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 1)],
            redactions: [
                PrivacyRedaction(
                    start: 0.15,
                    duration: 0.5,
                    normalizedX: 0.5,
                    normalizedY: 0.5,
                    normalizedWidth: 0.42,
                    normalizedHeight: 0.34,
                    opacity: 0.82,
                    presentation: .spotlight,
                    highlightHue: 0.13
                )
            ]
        )
        let spotlightCurrent = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: spotlightProject,
            timelineTime: 0.4,
            canvasStyle: .plain,
            frameRate: 15
        )
        let plainCurrent = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: spotlightProject,
            timelineTime: 0.9,
            canvasStyle: .plain,
            frameRate: 15
        )
        let spotlightPixels = rgbaPixels(from: spotlightCurrent)
        let plainPixels = rgbaPixels(from: plainCurrent)
        let spotlightCenter = pixel(
            in: spotlightPixels,
            width: spotlightCurrent.width,
            x: spotlightCurrent.width / 2,
            y: spotlightCurrent.height / 2
        )
        let plainCenter = pixel(
            in: plainPixels,
            width: plainCurrent.width,
            x: plainCurrent.width / 2,
            y: plainCurrent.height / 2
        )
        XCTAssertLessThan(
            abs(Int(spotlightCenter.green) - Int(plainCenter.green)),
            25,
            "The spotlight hole should preserve the source."
        )
        let spotlightCorner = pixel(
            in: spotlightPixels,
            width: spotlightCurrent.width,
            x: 24,
            y: 24
        )
        let plainCorner = pixel(
            in: plainPixels,
            width: plainCurrent.width,
            x: 24,
            y: 24
        )
        XCTAssertLessThan(
            Int(spotlightCorner.red)
                + Int(spotlightCorner.green)
                + Int(spotlightCorner.blue),
            (Int(plainCorner.red)
                + Int(plainCorner.green)
                + Int(plainCorner.blue)) / 2
        )

        try await exporter.export(
            sourceURL: sourceURL,
            project: spotlightProject,
            canvasStyle: .plain,
            destinationURL: spotlightURL,
            frameRate: 15
        )
        let spotlightGenerator = AVAssetImageGenerator(
            asset: AVURLAsset(url: spotlightURL)
        )
        spotlightGenerator.requestedTimeToleranceBefore = .zero
        spotlightGenerator.requestedTimeToleranceAfter = .zero
        let spotlightActiveVideoFrame = try await spotlightGenerator.image(
            at: CMTime(seconds: 0.4, preferredTimescale: 600)
        ).image
        let spotlightInactiveVideoFrame = try await spotlightGenerator.image(
            at: CMTime(seconds: 0.9, preferredTimescale: 600)
        ).image
        let activeVideoCorner = pixel(
            in: rgbaPixels(from: spotlightActiveVideoFrame),
            width: spotlightActiveVideoFrame.width,
            x: 24,
            y: 24
        )
        let inactiveVideoCorner = pixel(
            in: rgbaPixels(from: spotlightInactiveVideoFrame),
            width: spotlightInactiveVideoFrame.width,
            x: 24,
            y: 24
        )
        XCTAssertLessThan(
            Int(activeVideoCorner.red)
                + Int(activeVideoCorner.green)
                + Int(activeVideoCorner.blue),
            (Int(inactiveVideoCorner.red)
                + Int(inactiveVideoCorner.green)
                + Int(inactiveVideoCorner.blue)) / 2,
            "The timed spotlight must be baked into the MP4."
        )
    }

    func testRecordingAnnotationRendersIntoCurrentFrameAndMP4() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.mp4")
        let outputURL = directory.appendingPathComponent("annotated.mp4")
        try await makeSyntheticMedia(
            at: sourceURL,
            highFrequencyPattern: true
        )
        let annotation = Annotation(
            kind: .line,
            start: 0.15,
            duration: 0.5,
            normalizedStartX: 0.3,
            normalizedStartY: 0.3,
            normalizedEndX: 0.7,
            normalizedEndY: 0.7,
            lineWidth: 6,
            color: .red
        )
        let project = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 1)],
            annotations: [annotation]
        )
        let exporter = VideoExporter()
        let activeFrame = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: project,
            timelineTime: 0.4,
            canvasStyle: .plain,
            frameRate: 15
        )
        let plainFrame = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: TimelineProject(
                clips: [TimelineClip(sourceStart: 0, duration: 1)]
            ),
            timelineTime: 0.4,
            canvasStyle: .plain,
            frameRate: 15
        )
        let activeCenter = pixel(
            in: rgbaPixels(from: activeFrame),
            width: activeFrame.width,
            x: activeFrame.width / 2,
            y: activeFrame.height / 2
        )
        let plainCenter = pixel(
            in: rgbaPixels(from: plainFrame),
            width: plainFrame.width,
            x: plainFrame.width / 2,
            y: plainFrame.height / 2
        )
        XCTAssertGreaterThan(
            Int(activeCenter.red),
            Int(plainCenter.red) + 40,
            "A red annotation stroke must render across the center of the current-frame output."
        )

        try await exporter.export(
            sourceURL: sourceURL,
            project: project,
            canvasStyle: .plain,
            destinationURL: outputURL,
            frameRate: 15
        )
        let generator = AVAssetImageGenerator(
            asset: AVURLAsset(url: outputURL)
        )
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let activeMP4Frame = try await generator.image(
            at: CMTime(seconds: 0.4, preferredTimescale: 600)
        ).image
        let inactiveMP4Frame = try await generator.image(
            at: CMTime(seconds: 0.9, preferredTimescale: 600)
        ).image
        let activeMP4Center = pixel(
            in: rgbaPixels(from: activeMP4Frame),
            width: activeMP4Frame.width,
            x: activeMP4Frame.width / 2,
            y: activeMP4Frame.height / 2
        )
        let inactiveMP4Center = pixel(
            in: rgbaPixels(from: inactiveMP4Frame),
            width: inactiveMP4Frame.width,
            x: inactiveMP4Frame.width / 2,
            y: inactiveMP4Frame.height / 2
        )
        XCTAssertGreaterThan(
            Int(activeMP4Center.red),
            Int(inactiveMP4Center.red) + 40,
            "The annotation must be baked into the exported MP4 during its fade window."
        )
    }

    func testAnnotationPartialProgressReplaysTheDrawingGesture() {
        let transform: (CGFloat, CGFloat) -> CGPoint = { x, y in
            CGPoint(x: 1000 * x, y: 1000 * y)
        }
        let box = Annotation(
            kind: .rectangle,
            start: 0,
            normalizedStartX: 0.2,
            normalizedStartY: 0.2,
            normalizedEndX: 0.8,
            normalizedEndY: 0.8
        )
        let fullBox = annotationCGPath(for: box, transform: transform)
        let halfBox = annotationCGPath(
            for: box,
            progress: 0.5,
            transform: transform
        )
        XCTAssertEqual(fullBox.boundingBox.width, 600, accuracy: 1)
        XCTAssertEqual(halfBox.boundingBox.width, 300, accuracy: 1)

        let brush = Annotation(
            kind: .brush,
            start: 0,
            points: [
                NormalizedPoint(x: 0.1, y: 0.1),
                NormalizedPoint(x: 0.5, y: 0.1),
                NormalizedPoint(x: 0.9, y: 0.1)
            ]
        )
        let fullStroke = annotationCGPath(for: brush, transform: transform)
        let midStroke = annotationCGPath(
            for: brush,
            progress: 0.5,
            transform: transform
        )
        XCTAssertEqual(fullStroke.boundingBox.width, 800, accuracy: 1)
        XCTAssertEqual(midStroke.boundingBox.width, 400, accuracy: 1)

        let arrow = Annotation(
            kind: .arrow,
            start: 0,
            normalizedStartX: 0.2,
            normalizedStartY: 0.2,
            normalizedEndX: 0.8,
            normalizedEndY: 0.2
        )
        let partialArrow = annotationCGPath(
            for: arrow,
            progress: 0.5,
            transform: transform
        )
        XCTAssertEqual(
            partialArrow.boundingBox.maxX,
            500,
            accuracy: 1,
            "A half-drawn arrow must stop at the interpolated tip position."
        )
    }

    func testRecordingAnnotationReplaysDrawingProgressInFrameAndMP4()
        async throws
    {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.mp4")
        let outputURL = directory.appendingPathComponent("replay.mp4")
        try await makeSyntheticMedia(
            at: sourceURL,
            highFrequencyPattern: true
        )
        // Drawn from 0.1 s to 0.5 s, then held for 0.4 s (gone by 0.9 s).
        let annotation = Annotation(
            kind: .rectangle,
            start: 0.1,
            duration: 0.4,
            drawDuration: 0.4,
            normalizedStartX: 0.25,
            normalizedStartY: 0.25,
            normalizedEndX: 0.75,
            normalizedEndY: 0.75,
            lineWidth: 8,
            color: .red
        )
        let project = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 1)],
            annotations: [annotation]
        )
        let exporter = VideoExporter()
        let midDrawFrame = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: project,
            timelineTime: 0.3,
            canvasStyle: .plain,
            frameRate: 15
        )
        let completedFrame = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: project,
            timelineTime: 0.7,
            canvasStyle: .plain,
            frameRate: 15
        )
        let beforeFrame = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: project,
            timelineTime: 0.05,
            canvasStyle: .plain,
            frameRate: 15
        )
        let midDrawRed = redPixelCount(in: midDrawFrame)
        let completedRed = redPixelCount(in: completedFrame)
        let beforeRed = redPixelCount(in: beforeFrame)
        XCTAssertGreaterThan(
            completedRed,
            midDrawRed + 40,
            "Halfway through the drawing gesture the box must cover fewer pixels than the finished shape."
        )
        XCTAssertGreaterThan(
            midDrawRed,
            beforeRed + 40,
            "The stroke must already be partially visible mid-draw."
        )

        try await exporter.export(
            sourceURL: sourceURL,
            project: project,
            canvasStyle: .plain,
            destinationURL: outputURL,
            frameRate: 15
        )
        let generator = AVAssetImageGenerator(
            asset: AVURLAsset(url: outputURL)
        )
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let exportedFrame: (Double) async throws -> CGImage = { seconds in
            try await generator.image(
                at: CMTime(seconds: seconds, preferredTimescale: 600)
            ).image
        }
        let midMP4 = redPixelCount(
            in: try await exportedFrame(0.3)
        )
        let completedMP4 = redPixelCount(
            in: try await exportedFrame(0.7)
        )
        XCTAssertGreaterThan(
            completedMP4,
            midMP4 + 40,
            "The exported MP4 must replay the drawing gesture, not jump to the finished shape."
        )
    }

    private func redPixelCount(in image: CGImage) -> Int {
        let pixels = rgbaPixels(from: image)
        var count = 0
        for offset in stride(from: 0, to: pixels.count, by: 4)
        where pixels[offset] > 140
            && pixels[offset + 1] < 110
            && pixels[offset + 2] < 110 {
            count += 1
        }
        return count
    }

    func testLegacyProjectWithoutCanvasCropFieldsStillLoads() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.mp4")
        try await makeSyntheticMedia(at: sourceURL)
        let snapshot = ScreenFreeProjectSnapshot(
            version: ScreenFreeProjectSnapshot.currentVersion,
            sourcePath: sourceURL.path,
            cameraPath: nil,
            project: TimelineProject(
                clips: [TimelineClip(sourceStart: 0, duration: 1)]
            ),
            canvasAspectRatio: .square,
            canvasPadding: 18,
            cornerRadius: 12,
            backgroundHue: 0.68,
            backgroundMode: .wallpaper,
            wallpaperPreset: .ocean,
            backgroundImagePath: nil,
            backgroundBlur: 12,
            shadowStrength: 0.4,
            cursorSize: 1,
            cursorReplacement: .pointer,
            showCursor: true,
            hideCursorWhenIdle: false,
            cursorIdleTimeout: 2,
            cursorTailFreeze: 1.5,
            cursorLoopToStart: true,
            removeCursorShakes: true,
            cursorShakeThreshold: 0.018,
            optimizeRapidCursorChanges: true,
            smoothCursorMovement: true,
            backgroundMusicPath: sourceURL.path,
            backgroundMusicVolume: 0.35,
            recordedAudioLayout: RecordedAudioLayout(
                systemTrackIndex: 0,
                microphoneTrackIndex: 1
            ),
            systemAudioVolume: 0.45,
            microphoneAudioVolume: 1.25,
            microphoneAudioMuted: true,
            showClickRipple: true,
            clickEffectPreset: .rotation,
            showShortcutOverlay: true,
            showCaptions: true,
            captionFontSize: 34,
            captionLanguage: "en-US",
            captionVocabulary: "ScreenFree, AVFoundation",
            zoomScale: 1.8,
            zoomDuration: 2.2,
            zoomMotionPreset: .mellow,
            zoomCustomTransitionDuration: 0.62,
            zoomCustomX1: 0.8,
            zoomCustomY1: 0,
            zoomCustomX2: 1,
            zoomCustomY2: 0.2,
            motionBlurEnabled: true,
            motionBlurStrength: 0.72,
            cursorMotionBlur: 0.64,
            zoomMotionBlur: 0.82,
            panMotionBlur: 0.48,
            cameraSize: 0.24,
            cameraCornerRadius: 18,
            cameraMirrored: true,
            cameraPosition: .bottomRight,
            updatedAt: Date()
        )
        let currentURL = directory.appendingPathComponent("current.screenfree")
        try ProjectPersistence().save(snapshot, to: currentURL)
        let current = try ProjectPersistence().load(from: currentURL)
        XCTAssertEqual(current.clickEffectPreset, .rotation)
        XCTAssertEqual(current.showShortcutOverlay, true)
        XCTAssertEqual(current.cursorTailFreeze, 1.5)
        XCTAssertEqual(current.cursorLoopToStart, true)
        XCTAssertEqual(current.removeCursorShakes, true)
        XCTAssertEqual(current.cursorShakeThreshold, 0.018)
        XCTAssertEqual(current.optimizeRapidCursorChanges, true)
        XCTAssertEqual(current.smoothCursorMovement, true)
        XCTAssertEqual(current.cursorReplacement, .pointer)
        XCTAssertEqual(current.zoomCustomTransitionDuration, 0.62)
        XCTAssertEqual(current.zoomCustomX1, 0.8)
        XCTAssertEqual(current.zoomCustomY2, 0.2)
        XCTAssertEqual(current.wallpaperPreset, .ocean)
        XCTAssertEqual(current.backgroundMusicPath, sourceURL.path)
        XCTAssertEqual(current.backgroundMusicVolume, 0.35)
        XCTAssertEqual(
            current.recordedAudioLayout,
            RecordedAudioLayout(
                systemTrackIndex: 0,
                microphoneTrackIndex: 1
            )
        )
        XCTAssertEqual(current.systemAudioVolume, 0.45)
        XCTAssertEqual(current.microphoneAudioVolume, 1.25)
        XCTAssertEqual(current.microphoneAudioMuted, true)
        XCTAssertEqual(current.motionBlurEnabled, true)
        XCTAssertEqual(current.motionBlurStrength, 0.72)
        XCTAssertEqual(current.cursorMotionBlur, 0.64)
        XCTAssertEqual(current.zoomMotionBlur, 0.82)
        XCTAssertEqual(current.panMotionBlur, 0.48)
        XCTAssertEqual(
            current.captionVocabulary,
            "ScreenFree, AVFoundation"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(snapshot)
        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "canvasAspectRatio")
        legacyObject.removeValue(forKey: "backgroundBlur")
        legacyObject.removeValue(forKey: "wallpaperPreset")
        legacyObject.removeValue(forKey: "zoomMotionPreset")
        legacyObject.removeValue(forKey: "clickEffectPreset")
        legacyObject.removeValue(forKey: "showShortcutOverlay")
        legacyObject.removeValue(forKey: "cursorTailFreeze")
        legacyObject.removeValue(forKey: "cursorLoopToStart")
        legacyObject.removeValue(forKey: "removeCursorShakes")
        legacyObject.removeValue(forKey: "cursorShakeThreshold")
        legacyObject.removeValue(forKey: "optimizeRapidCursorChanges")
        legacyObject.removeValue(forKey: "smoothCursorMovement")
        legacyObject.removeValue(forKey: "cursorReplacement")
        legacyObject.removeValue(forKey: "zoomCustomTransitionDuration")
        legacyObject.removeValue(forKey: "zoomCustomX1")
        legacyObject.removeValue(forKey: "zoomCustomY1")
        legacyObject.removeValue(forKey: "zoomCustomX2")
        legacyObject.removeValue(forKey: "zoomCustomY2")
        legacyObject.removeValue(forKey: "backgroundMusicPath")
        legacyObject.removeValue(forKey: "backgroundMusicVolume")
        legacyObject.removeValue(forKey: "recordedAudioLayout")
        legacyObject.removeValue(forKey: "systemAudioVolume")
        legacyObject.removeValue(forKey: "microphoneAudioVolume")
        legacyObject.removeValue(forKey: "microphoneAudioMuted")
        legacyObject.removeValue(forKey: "motionBlurEnabled")
        legacyObject.removeValue(forKey: "motionBlurStrength")
        legacyObject.removeValue(forKey: "cursorMotionBlur")
        legacyObject.removeValue(forKey: "zoomMotionBlur")
        legacyObject.removeValue(forKey: "panMotionBlur")
        legacyObject.removeValue(forKey: "captionVocabulary")
        if var projectObject = legacyObject["project"] as? [String: Any] {
            projectObject.removeValue(forKey: "shortcuts")
            projectObject.removeValue(forKey: "redactions")
            legacyObject["project"] = projectObject
        }
        let legacyURL = directory.appendingPathComponent("legacy.screenfree")
        try JSONSerialization.data(
            withJSONObject: legacyObject
        ).write(to: legacyURL)

        let restored = try ProjectPersistence().load(from: legacyURL)
        XCTAssertNil(restored.canvasAspectRatio)
        XCTAssertNil(restored.backgroundBlur)
        XCTAssertNil(restored.wallpaperPreset)
        XCTAssertNil(restored.zoomMotionPreset)
        XCTAssertNil(restored.clickEffectPreset)
        XCTAssertNil(restored.showShortcutOverlay)
        XCTAssertNil(restored.cursorTailFreeze)
        XCTAssertNil(restored.cursorLoopToStart)
        XCTAssertNil(restored.removeCursorShakes)
        XCTAssertNil(restored.cursorShakeThreshold)
        XCTAssertNil(restored.optimizeRapidCursorChanges)
        XCTAssertNil(restored.smoothCursorMovement)
        XCTAssertNil(restored.cursorReplacement)
        XCTAssertNil(restored.zoomCustomTransitionDuration)
        XCTAssertNil(restored.zoomCustomX1)
        XCTAssertNil(restored.zoomCustomY1)
        XCTAssertNil(restored.zoomCustomX2)
        XCTAssertNil(restored.zoomCustomY2)
        XCTAssertNil(restored.backgroundMusicPath)
        XCTAssertNil(restored.backgroundMusicVolume)
        XCTAssertNil(restored.recordedAudioLayout)
        XCTAssertNil(restored.systemAudioVolume)
        XCTAssertNil(restored.microphoneAudioVolume)
        XCTAssertNil(restored.microphoneAudioMuted)
        XCTAssertNil(restored.motionBlurEnabled)
        XCTAssertNil(restored.motionBlurStrength)
        XCTAssertNil(restored.cursorMotionBlur)
        XCTAssertNil(restored.zoomMotionBlur)
        XCTAssertNil(restored.panMotionBlur)
        XCTAssertNil(restored.captionVocabulary)
        XCTAssertTrue(restored.project.shortcuts.isEmpty)
        XCTAssertTrue(restored.project.redactions.isEmpty)
        XCTAssertEqual(restored.project.duration, 1, accuracy: 0.001)
    }

    @MainActor
    func testOpeningRecordingHistoryRestoresEditableCursorAndZoomMetadata()
        async throws
    {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("Recording-test.mp4")
        try await makeSyntheticMedia(at: sourceURL)
        let cursor = CursorSample(
            time: 0.5,
            normalizedX: 0.82,
            normalizedY: 0.31
        )
        let project = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 1)],
            zooms: [
                ZoomEvent(
                    start: 0,
                    duration: 1,
                    scale: 1.8,
                    focusX: 0.5,
                    focusY: 0.5,
                    followsCursor: true
                )
            ],
            cursorSamples: [cursor]
        )
        let snapshot = ScreenFreeProjectSnapshot(
            version: ScreenFreeProjectSnapshot.currentVersion,
            sourcePath: sourceURL.path,
            cameraPath: nil,
            project: project,
            canvasAspectRatio: .source,
            canvasContentMode: .fit,
            canvasPadding: 0,
            cornerRadius: 0,
            backgroundHue: 0.68,
            backgroundMode: .solid,
            wallpaperPreset: .aurora,
            backgroundImagePath: nil,
            backgroundBlur: 0,
            shadowStrength: 0,
            cursorSize: 1.3,
            cursorReplacement: .arrow,
            showCursor: true,
            hideCursorWhenIdle: false,
            cursorIdleTimeout: 2,
            cursorTailFreeze: 0,
            cursorLoopToStart: false,
            removeCursorShakes: false,
            cursorShakeThreshold: 0.012,
            optimizeRapidCursorChanges: false,
            smoothCursorMovement: true,
            backgroundMusicPath: nil,
            backgroundMusicVolume: 0.2,
            recordedAudioLayout: nil,
            systemAudioVolume: 1,
            microphoneAudioVolume: 1,
            microphoneAudioMuted: false,
            showClickRipple: true,
            clickEffectPreset: .ripple,
            showShortcutOverlay: true,
            showCaptions: true,
            captionFontSize: 34,
            captionLanguage: "zh-CN",
            captionVocabulary: "",
            zoomScale: 1.8,
            zoomDuration: 3.2,
            zoomMotionPreset: .mellow,
            zoomCustomTransitionDuration: 0.82,
            zoomCustomX1: 0.25,
            zoomCustomY1: 0.1,
            zoomCustomX2: 0.25,
            zoomCustomY2: 1,
            motionBlurEnabled: false,
            motionBlurStrength: 0.42,
            cursorMotionBlur: 0.58,
            zoomMotionBlur: 0.45,
            panMotionBlur: 0.34,
            cameraSize: 0.24,
            cameraCornerRadius: 18,
            cameraMirrored: true,
            cameraPosition: .bottomRight,
            transitionStyle: .fade,
            transitionDuration: 0.4,
            updatedAt: Date()
        )
        let sidecarURL = RecordingProjectSidecar.url(for: sourceURL)
        try ProjectPersistence().save(snapshot, to: sidecarURL)

        let store = EditorStore()
        await store.openRecordingFromHistory(
            RecordingHistoryItem(
                url: sourceURL,
                modifiedAt: Date(),
                fileSize: 1
            )
        )

        XCTAssertEqual(store.project.cursorSamples, [cursor])
        XCTAssertEqual(store.project.zooms.count, 1)
        let restoredCursor = try XCTUnwrap(
            store.project.cursorSample(
                atTimelineTime: 0.5,
                freezeBeforeEnd: store.cursorTailFreeze,
                smoothMovement: store.smoothCursorMovement
            )
        )
        XCTAssertEqual(restoredCursor.normalizedX, 0.82, accuracy: 0.001)
        XCTAssertEqual(restoredCursor.normalizedY, 0.31, accuracy: 0.001)
        let zoomState = try XCTUnwrap(store.activeZoomMotion(at: 0.5))
        let focus = ZoomFocusResolver.focus(
            at: 0.5,
            zoomState: zoomState,
            project: store.project,
            cursorTailFreeze: store.cursorTailFreeze,
            cursorLoopToStart: store.cursorLoopToStart,
            removeCursorShakes: store.removeCursorShakes,
            cursorShakeThreshold: store.cursorShakeThreshold,
            optimizeRapidCursorChanges: store.optimizeRapidCursorChanges,
            smoothCursorMovement: store.smoothCursorMovement
        )
        XCTAssertEqual(focus.x, restoredCursor.normalizedX, accuracy: 0.001)
        XCTAssertEqual(focus.y, restoredCursor.normalizedY, accuracy: 0.001)
    }

    @MainActor
    func testRecordingHistoryRecoversCursorFromMP4WhenSidecarIsMissing()
        async throws
    {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("Recording-test.mp4")
        try await makeSyntheticMedia(at: sourceURL)
        let originalDuration = try await AVURLAsset(url: sourceURL)
            .load(.duration).seconds
        let cursorSamples = [
            CursorSample(
                time: 0.2,
                normalizedX: 0.24,
                normalizedY: 0.72
            ),
            CursorSample(
                time: 0.7,
                normalizedX: 0.78,
                normalizedY: 0.31
            )
        ]
        let clicks = [
            MouseClick(
                time: 0.7,
                normalizedX: 0.78,
                normalizedY: 0.31,
                button: .right,
                holdDuration: 0.8
            )
        ]
        let shortcuts = [ShortcutEvent(time: 0.4, label: "⌘K")]
        let archive = RecordingInteractionArchive(
            cursorSamples: cursorSamples,
            clicks: clicks,
            shortcuts: shortcuts
        )
        try await RecordingInteractionMetadata.write(
            archive,
            to: sourceURL
        )

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: RecordingProjectSidecar.url(for: sourceURL).path
            )
        )
        let reopenedAsset = AVURLAsset(url: sourceURL)
        let reopenedVideoTracks = try await reopenedAsset.loadTracks(
            withMediaType: .video
        )
        let reopenedAudioTracks = try await reopenedAsset.loadTracks(
            withMediaType: .audio
        )
        let reopenedDuration = try await reopenedAsset.load(.duration).seconds
        XCTAssertEqual(reopenedVideoTracks.count, 1)
        XCTAssertEqual(reopenedAudioTracks.count, 1)
        XCTAssertEqual(reopenedDuration, originalDuration, accuracy: 0.001)

        let store = EditorStore(
            recordingHistoryCatalog: RecordingHistoryCatalog(
                directory: directory
            )
        )
        await store.openRecordingFromHistory(
            RecordingHistoryItem(
                url: sourceURL,
                modifiedAt: Date(),
                fileSize: 1
            )
        )

        XCTAssertEqual(store.project.cursorSamples, cursorSamples)
        XCTAssertEqual(store.project.clicks, clicks)
        XCTAssertEqual(store.project.shortcuts, shortcuts)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: RecordingProjectSidecar.url(for: sourceURL).path
            ),
            "Recovered interaction data should immediately receive a new editable sidecar."
        )

        var cursorStyle = CanvasRenderStyle.plain
        cursorStyle.showCursor = true
        let exporter = VideoExporter()
        let cursorFrame = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: store.project,
            timelineTime: 0.7,
            canvasStyle: cursorStyle,
            frameRate: 30
        )
        cursorStyle.showCursor = false
        let frameWithoutCursor = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: store.project,
            timelineTime: 0.7,
            canvasStyle: cursorStyle,
            frameRate: 30
        )
        let difference = zip(
            rgbaPixels(from: cursorFrame),
            rgbaPixels(from: frameWithoutCursor)
        ).reduce(0) {
            $0 + abs(Int($1.0) - Int($1.1))
        }
        XCTAssertGreaterThan(
            difference,
            25_000,
            "Recovered cursor metadata must draw a visible cursor in the real preview renderer."
        )

        let importedStore = EditorStore()
        try await importedStore.loadVideo(sourceURL)
        XCTAssertEqual(importedStore.project.cursorSamples, cursorSamples)
        XCTAssertEqual(importedStore.project.clicks, clicks)
        XCTAssertEqual(importedStore.project.shortcuts, shortcuts)
    }

    @MainActor
    func testHistoryUsesMatchingRecoveryInsteadOfOverwritingItWithEmptyCursorData()
        async throws
    {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("Recording-legacy.mp4")
        try await makeSyntheticMedia(at: sourceURL)
        let cursor = CursorSample(
            time: 0.55,
            normalizedX: 0.63,
            normalizedY: 0.27
        )
        let recoveryURL = directory.appendingPathComponent(
            "Recovery.screenfree"
        )
        let persistence = ProjectPersistence(recoveryURL: recoveryURL)
        try persistence.save(
            makeTestSnapshot(
                sourceURL: sourceURL,
                project: TimelineProject(
                    clips: [TimelineClip(sourceStart: 0, duration: 1)],
                    cursorSamples: [cursor]
                )
            ),
            to: recoveryURL
        )
        let sidecarURL = RecordingProjectSidecar.url(for: sourceURL)
        try persistence.save(
            makeTestSnapshot(
                sourceURL: sourceURL,
                project: TimelineProject(
                    clips: [TimelineClip(sourceStart: 0, duration: 1)]
                )
            ),
            to: sidecarURL
        )

        let store = EditorStore(
            recordingHistoryCatalog: RecordingHistoryCatalog(
                directory: directory
            ),
            persistence: persistence
        )
        await store.openRecordingFromHistory(
            RecordingHistoryItem(
                url: sourceURL,
                modifiedAt: Date(),
                fileSize: 1
            )
        )

        XCTAssertEqual(store.project.cursorSamples, [cursor])
        XCTAssertEqual(
            try persistence.load(from: sidecarURL).project.cursorSamples,
            [cursor],
            "A matching Recovery project must repair the empty sidecar rather than being overwritten by it."
        )
    }

    func testSidecarAutosaveCannotReplaceRecordedCursorWithTransientEmptyState()
        throws
    {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("Recording-safe.mp4")
        try Data([0]).write(to: sourceURL)
        let sidecarURL = RecordingProjectSidecar.url(for: sourceURL)
        let backupURL = RecordingProjectSidecar.backupURL(for: sourceURL)
        let persistence = ProjectPersistence(
            recoveryURL: directory.appendingPathComponent(
                "Recovery.screenfree"
            )
        )
        let cursor = CursorSample(
            time: 0.4,
            normalizedX: 0.7,
            normalizedY: 0.2
        )
        try persistence.save(
            makeTestSnapshot(
                sourceURL: sourceURL,
                project: TimelineProject(
                    clips: [TimelineClip(sourceStart: 0, duration: 1)],
                    cursorSamples: [cursor]
                )
            ),
            to: sidecarURL
        )
        try persistence.savePreservingRecordedInteractions(
            makeTestSnapshot(
                sourceURL: sourceURL,
                project: TimelineProject(
                    clips: [TimelineClip(sourceStart: 0, duration: 1)]
                )
            ),
            to: sidecarURL,
            backupURL: backupURL
        )

        XCTAssertEqual(
            try persistence.load(from: sidecarURL).project.cursorSamples,
            [cursor]
        )
        XCTAssertEqual(
            try persistence.load(from: backupURL).project.cursorSamples,
            [cursor]
        )
    }

    @MainActor
    func testVideoLoadingOnlyKeepsCursorMetadataForRecordingFinalization()
        async throws
    {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.mp4")
        try await makeSyntheticMedia(at: sourceURL)
        let capturedCursor = CursorSample(
            time: 0.4,
            normalizedX: 0.76,
            normalizedY: 0.28
        )
        let store = EditorStore()
        store.project = TimelineProject(cursorSamples: [capturedCursor])

        try await store.loadVideo(
            sourceURL,
            preservingCapturedMetadata: true
        )
        XCTAssertEqual(store.project.cursorSamples, [capturedCursor])

        let staleCursor = CursorSample(
            time: 0.2,
            normalizedX: 0.1,
            normalizedY: 0.9
        )
        store.project = TimelineProject(cursorSamples: [staleCursor])
        try await store.loadVideo(sourceURL)

        XCTAssertTrue(
            store.project.cursorSamples.isEmpty,
            "A fresh import or sidecar-less history item must not inherit another video's cursor path."
        )
    }

    @MainActor
    func testRecordingFinalizationKeepsDrawnAnnotationsInTimelineProject()
        async throws
    {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.mp4")
        try await makeSyntheticMedia(at: sourceURL)
        let drawnBox = Annotation(
            kind: .rectangle,
            start: 0.2,
            normalizedStartX: 0.3,
            normalizedStartY: 0.3,
            normalizedEndX: 0.7,
            normalizedEndY: 0.7,
            color: .red
        )
        let store = EditorStore()
        store.project = TimelineProject(annotations: [drawnBox])

        try await store.loadVideo(
            sourceURL,
            preservingCapturedMetadata: true
        )

        XCTAssertEqual(
            store.project.annotations,
            [drawnBox],
            "Stopping a recording must carry drawn annotations into the editor project."
        )
        XCTAssertEqual(
            store.activeAnnotations(at: 1.0),
            [drawnBox],
            "The editor preview must still see the annotation inside its fade window."
        )
        XCTAssertTrue(
            store.activeAnnotations(at: 3.5).isEmpty,
            "Annotations are visible only inside their fade window."
        )
    }

    @MainActor
    func testMP4AndGIFExportsContainRenderedMedia() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.mp4")
        let mp4URL = directory.appendingPathComponent("edited.mp4")
        let noShortcutMP4URL = directory.appendingPathComponent(
            "edited-no-shortcut.mp4"
        )
        let noReturnMP4URL = directory.appendingPathComponent(
            "edited-no-return.mp4"
        )
        let noBlurMP4URL = directory.appendingPathComponent(
            "edited-no-blur.mp4"
        )
        let noSmoothMP4URL = directory.appendingPathComponent(
            "edited-no-smoothing.mp4"
        )
        let pointerMP4URL = directory.appendingPathComponent(
            "edited-pointer.mp4"
        )
        let customSizeMP4URL = directory.appendingPathComponent(
            "edited-custom-size.mp4"
        )
        let gifURL = directory.appendingPathComponent("edited.gif")
        try await makeSyntheticMedia(at: sourceURL)

        let mergedURL = try await RecordingSegmentMerger().merge(
            [sourceURL, sourceURL],
            fileExtension: "mp4"
        )
        let mergedDuration = try await AVURLAsset(url: mergedURL)
            .load(.duration)
            .seconds
        let mergedAudioTracks = try await AVURLAsset(url: mergedURL)
            .loadTracks(withMediaType: .audio)
        XCTAssertEqual(mergedDuration, 2, accuracy: 0.08)
        XCTAssertEqual(mergedAudioTracks.count, 1)

        let project = TimelineProject(
            clips: [
                TimelineClip(
                    sourceStart: 0,
                    duration: 1,
                    playbackRate: 1,
                    volume: 1
                )
            ],
            zooms: [
                ZoomEvent(
                    start: 0.2,
                    duration: 0.5,
                    scale: 1.35,
                    focusX: 0.72,
                    focusY: 0.35
                )
            ],
            cursorSamples: [
                CursorSample(
                    time: 0,
                    normalizedX: 0.45,
                    normalizedY: 0.5
                ),
                CursorSample(
                    time: 0.32,
                    normalizedX: 0.66,
                    normalizedY: 0.42
                ),
                CursorSample(
                    time: 0.34,
                    normalizedX: 0.78,
                    normalizedY: 0.1
                ),
                CursorSample(
                    time: 1,
                    normalizedX: 0.72,
                    normalizedY: 0.38
                )
            ],
            clicks: [
                MouseClick(
                    time: 0.32,
                    normalizedX: 0.66,
                    normalizedY: 0.42
                )
            ],
            captions: [
                CaptionCue(
                    sourceStart: 0.1,
                    duration: 0.7,
                    text: "ScreenFree"
                )
            ],
            shortcuts: [
                ShortcutEvent(time: 0.25, label: "⌘K")
            ]
        )
        var style = CanvasRenderStyle.plain
        style.aspectRatio = .square
        style.contentMode = .crop
        style.padding = 18
        style.cornerRadius = 12
        style.shadowOpacity = 0.4
        style.backgroundBlur = 12
        style.backgroundMode = .wallpaper
        style.wallpaperPreset = .sunset
        style.showCaptions = true
        style.clickEffect = .circle
        style.showShortcuts = true
        style.cursorLoopToStart = true
        style.optimizeRapidCursorChanges = true
        style.smoothCursorMovement = true
        style.motionBlur = MotionBlurStyle(
            enabled: true,
            strength: 1,
            cursorAmount: 1,
            zoomAmount: 0,
            panAmount: 0
        )

        let exporter = VideoExporter()
        let currentFrame = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: project,
            timelineTime: 0.4,
            canvasStyle: style,
            frameRate: 30
        )
        XCTAssertEqual(currentFrame.width, currentFrame.height)
        XCTAssertGreaterThan(currentFrame.width, 100)
        let blurredCursorFrame = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: project,
            timelineTime: 0.34,
            canvasStyle: style,
            frameRate: 30
        )
        var noBlurStyle = style
        noBlurStyle.motionBlur = .disabled
        let sharpCursorFrame = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: project,
            timelineTime: 0.34,
            canvasStyle: noBlurStyle,
            frameRate: 30
        )
        let cursorBlurDifference = zip(
            rgbaPixels(from: blurredCursorFrame),
            rgbaPixels(from: sharpCursorFrame)
        ).reduce(0) {
            $0 + abs(Int($1.0) - Int($1.1))
        }
        XCTAssertGreaterThan(
            cursorBlurDifference,
            1_000,
            "Cursor-velocity blur should reach current-frame rendering."
        )
        let smoothCursorFrame = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: project,
            timelineTime: 0.33,
            canvasStyle: noBlurStyle,
            frameRate: 60
        )
        var noSmoothStyle = noBlurStyle
        noSmoothStyle.smoothCursorMovement = false
        let steppedCursorFrame = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: project,
            timelineTime: 0.33,
            canvasStyle: noSmoothStyle,
            frameRate: 60
        )
        let currentSmoothingDifference = zip(
            rgbaPixels(from: smoothCursorFrame),
            rgbaPixels(from: steppedCursorFrame)
        ).reduce(0) {
            $0 + abs(Int($1.0) - Int($1.1))
        }
        XCTAssertGreaterThan(
            currentSmoothingDifference,
            1_000,
            "Current-frame cursor output should honor sample interpolation."
        )
        var pointerStyle = noBlurStyle
        pointerStyle.cursorReplacement = .pointer
        let pointerCursorFrame = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: project,
            timelineTime: 0.34,
            canvasStyle: pointerStyle,
            frameRate: 30
        )
        let currentReplacementDifference = zip(
            rgbaPixels(from: sharpCursorFrame),
            rgbaPixels(from: pointerCursorFrame)
        ).reduce(0) {
            $0 + abs(Int($1.0) - Int($1.1))
        }
        XCTAssertGreaterThan(
            currentReplacementDifference,
            5_000,
            "Current-frame rendering should use the selected cursor replacement."
        )
        var noClickStyle = style
        noClickStyle.clickEffect = .none
        let noClickFrame = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: project,
            timelineTime: 0.4,
            canvasStyle: noClickStyle,
            frameRate: 30
        )
        let clickDifference = zip(
            rgbaPixels(from: currentFrame),
            rgbaPixels(from: noClickFrame)
        ).reduce(0) {
            $0 + abs(Int($1.0) - Int($1.1))
        }
        XCTAssertGreaterThan(
            clickDifference,
            5_000,
            "The selected click effect should be rendered into composed frames."
        )
        var gradientStyle = style
        gradientStyle.backgroundMode = .gradient
        let gradientFrame = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: project,
            timelineTime: 0.4,
            canvasStyle: gradientStyle,
            frameRate: 30
        )
        let wallpaperDifference = zip(
            rgbaPixels(from: currentFrame),
            rgbaPixels(from: gradientFrame)
        ).reduce(0) {
            $0 + abs(Int($1.0) - Int($1.1))
        }
        XCTAssertGreaterThan(
            wallpaperDifference,
            20_000,
            "The selected wallpaper should reach the real frame composition."
        )
        var noShortcutStyle = noClickStyle
        noShortcutStyle.showShortcuts = false
        let noShortcutFrame = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: project,
            timelineTime: 0.4,
            canvasStyle: noShortcutStyle,
            frameRate: 30
        )
        let shortcutDifference = zip(
            rgbaPixels(from: noClickFrame),
            rgbaPixels(from: noShortcutFrame)
        ).reduce(0) {
            $0 + abs(Int($1.0) - Int($1.1))
        }
        XCTAssertGreaterThan(
            shortcutDifference,
            10_000,
            "Current-frame output should include the active shortcut label."
        )

        var noOverlayStyle = noShortcutStyle
        noOverlayStyle.showCursor = false
        noOverlayStyle.showCaptions = false
        let noOverlayFrame = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: project,
            timelineTime: 0.4,
            canvasStyle: noOverlayStyle,
            frameRate: 30
        )
        let dynamicOverlayDifference = zip(
            rgbaPixels(from: noClickFrame),
            rgbaPixels(from: noOverlayFrame)
        ).reduce(0) {
            $0 + abs(Int($1.0) - Int($1.1))
        }
        XCTAssertGreaterThan(
            dynamicOverlayDifference,
            10_000,
            "Current-frame output should include the playhead cursor and active caption."
        )
        let returnedCurrentFrame = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: project,
            timelineTime: 0.9,
            canvasStyle: style,
            frameRate: 30
        )
        var noReturnStyle = style
        noReturnStyle.cursorLoopToStart = false
        let ordinaryCurrentFrame = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: project,
            timelineTime: 0.9,
            canvasStyle: noReturnStyle,
            frameRate: 30
        )
        let currentFrameReturnDifference = zip(
            rgbaPixels(from: returnedCurrentFrame),
            rgbaPixels(from: ordinaryCurrentFrame)
        ).reduce(0) {
            $0 + abs(Int($1.0) - Int($1.1))
        }
        XCTAssertGreaterThan(
            currentFrameReturnDifference,
            5_000,
            "Current-frame rendering should use the same eased cursor return."
        )
        let optimizedCurrentFrame = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: project,
            timelineTime: 0.34,
            canvasStyle: style,
            frameRate: 30
        )
        var rawPathStyle = style
        rawPathStyle.optimizeRapidCursorChanges = false
        let rawCurrentFrame = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: project,
            timelineTime: 0.34,
            canvasStyle: rawPathStyle,
            frameRate: 30
        )
        let optimizedCurrentFrameDifference = zip(
            rgbaPixels(from: optimizedCurrentFrame),
            rgbaPixels(from: rawCurrentFrame)
        ).reduce(0) {
            $0 + abs(Int($1.0) - Int($1.1))
        }
        XCTAssertGreaterThan(
            optimizedCurrentFrameDifference,
            5_000,
            "Current-frame rendering should use the processed cursor path."
        )

        var mp4Progress: [Double] = []
        try await exporter.export(
            sourceURL: sourceURL,
            project: project,
            canvasStyle: style,
            destinationURL: mp4URL,
            format: .mp4,
            frameRate: 30,
            progress: { mp4Progress.append($0) }
        )
        var videoNoShortcutStyle = style
        videoNoShortcutStyle.showShortcuts = false
        try await exporter.export(
            sourceURL: sourceURL,
            project: project,
            canvasStyle: videoNoShortcutStyle,
            destinationURL: noShortcutMP4URL,
            format: .mp4,
            frameRate: 30
        )
        var videoNoReturnStyle = videoNoShortcutStyle
        videoNoReturnStyle.cursorLoopToStart = false
        videoNoReturnStyle.optimizeRapidCursorChanges = false
        try await exporter.export(
            sourceURL: sourceURL,
            project: project,
            canvasStyle: videoNoReturnStyle,
            destinationURL: noReturnMP4URL,
            format: .mp4,
            frameRate: 30
        )
        try await exporter.export(
            sourceURL: sourceURL,
            project: project,
            canvasStyle: noBlurStyle,
            destinationURL: noBlurMP4URL,
            format: .mp4,
            frameRate: 30
        )
        try await exporter.export(
            sourceURL: sourceURL,
            project: project,
            canvasStyle: noSmoothStyle,
            destinationURL: noSmoothMP4URL,
            format: .mp4,
            frameRate: 30
        )
        try await exporter.export(
            sourceURL: sourceURL,
            project: project,
            canvasStyle: pointerStyle,
            destinationURL: pointerMP4URL,
            format: .mp4,
            frameRate: 30
        )
        try await exporter.export(
            sourceURL: sourceURL,
            project: project,
            canvasStyle: noBlurStyle,
            destinationURL: customSizeMP4URL,
            format: .mp4,
            frameRate: 30,
            renderSizeOverride: CGSize(width: 642, height: 358)
        )
        var gifProgress: [Double] = []
        try await exporter.export(
            sourceURL: sourceURL,
            project: project,
            canvasStyle: style,
            destinationURL: gifURL,
            format: .gif,
            frameRate: 10,
            progress: { gifProgress.append($0) }
        )
        XCTAssertEqual(mp4Progress.last ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(gifProgress.last ?? 0, 1, accuracy: 0.001)

        let exportedAsset = AVURLAsset(url: mp4URL)
        let exportedDuration = try await exportedAsset.load(.duration).seconds
        let videoTracks = try await exportedAsset.loadTracks(withMediaType: .video)
        XCTAssertEqual(videoTracks.count, 1)
        let exportedTrack = try XCTUnwrap(videoTracks.first)
        let exportedSize = try await exportedTrack.load(.naturalSize)
        XCTAssertEqual(exportedSize.width, exportedSize.height, accuracy: 1)
        let customSizeTracks = try await AVURLAsset(url: customSizeMP4URL)
            .loadTracks(withMediaType: .video)
        let customSizeTrack = try XCTUnwrap(
            customSizeTracks.first
        )
        let customSize = try await customSizeTrack.load(.naturalSize)
        XCTAssertEqual(customSize.width, 642, accuracy: 1)
        XCTAssertEqual(customSize.height, 358, accuracy: 1)
        let cropFrame = try await AVAssetImageGenerator(
            asset: exportedAsset
        ).image(at: .zero).image
        let shortcutGenerator = AVAssetImageGenerator(asset: exportedAsset)
        shortcutGenerator.requestedTimeToleranceBefore = .zero
        shortcutGenerator.requestedTimeToleranceAfter = .zero
        let shortcutFrame = try await shortcutGenerator.image(
            at: CMTime(seconds: 0.4, preferredTimescale: 600)
        ).image
        let noShortcutGenerator = AVAssetImageGenerator(
            asset: AVURLAsset(url: noShortcutMP4URL)
        )
        noShortcutGenerator.requestedTimeToleranceBefore = .zero
        noShortcutGenerator.requestedTimeToleranceAfter = .zero
        let exportedNoShortcutFrame = try await noShortcutGenerator.image(
            at: CMTime(seconds: 0.4, preferredTimescale: 600)
        ).image
        let exportedShortcutDifference = zip(
            rgbaPixels(from: shortcutFrame),
            rgbaPixels(from: exportedNoShortcutFrame)
        ).reduce(0) {
            $0 + abs(Int($1.0) - Int($1.1))
        }
        XCTAssertGreaterThan(
            exportedShortcutDifference,
            10_000,
            "Video export should render the active shortcut label."
        )
        let blurredCursorExportFrame = try await shortcutGenerator.image(
            at: CMTime(seconds: 0.34, preferredTimescale: 600)
        ).image
        let noBlurGenerator = AVAssetImageGenerator(
            asset: AVURLAsset(url: noBlurMP4URL)
        )
        noBlurGenerator.requestedTimeToleranceBefore = .zero
        noBlurGenerator.requestedTimeToleranceAfter = .zero
        let sharpCursorExportFrame = try await noBlurGenerator.image(
            at: CMTime(seconds: 0.34, preferredTimescale: 600)
        ).image
        let exportedCursorBlurDifference = zip(
            rgbaPixels(from: blurredCursorExportFrame),
            rgbaPixels(from: sharpCursorExportFrame)
        ).reduce(0) {
            $0 + abs(Int($1.0) - Int($1.1))
        }
        XCTAssertGreaterThan(
            exportedCursorBlurDifference,
            1_000,
            "Cursor motion blur must be baked into the actual MP4."
        )
        let smoothExportFrame = try await noBlurGenerator.image(
            at: CMTime(seconds: 0.33, preferredTimescale: 600)
        ).image
        let noSmoothGenerator = AVAssetImageGenerator(
            asset: AVURLAsset(url: noSmoothMP4URL)
        )
        noSmoothGenerator.requestedTimeToleranceBefore = .zero
        noSmoothGenerator.requestedTimeToleranceAfter = .zero
        let steppedExportFrame = try await noSmoothGenerator.image(
            at: CMTime(seconds: 0.33, preferredTimescale: 600)
        ).image
        let exportedSmoothingDifference = zip(
            rgbaPixels(from: smoothExportFrame),
            rgbaPixels(from: steppedExportFrame)
        ).reduce(0) {
            $0 + abs(Int($1.0) - Int($1.1))
        }
        XCTAssertGreaterThan(
            exportedSmoothingDifference,
            1_000,
            "MP4 cursor output should honor sample interpolation."
        )
        let pointerGenerator = AVAssetImageGenerator(
            asset: AVURLAsset(url: pointerMP4URL)
        )
        pointerGenerator.requestedTimeToleranceBefore = .zero
        pointerGenerator.requestedTimeToleranceAfter = .zero
        let pointerExportFrame = try await pointerGenerator.image(
            at: CMTime(seconds: 0.34, preferredTimescale: 600)
        ).image
        let exportedReplacementDifference = zip(
            rgbaPixels(from: sharpCursorExportFrame),
            rgbaPixels(from: pointerExportFrame)
        ).reduce(0) {
            $0 + abs(Int($1.0) - Int($1.1))
        }
        XCTAssertGreaterThan(
            exportedReplacementDifference,
            5_000,
            "MP4 rendering should bake in the selected cursor replacement."
        )
        let returnFrame = try await noShortcutGenerator.image(
            at: CMTime(seconds: 0.9, preferredTimescale: 600)
        ).image
        let noReturnGenerator = AVAssetImageGenerator(
            asset: AVURLAsset(url: noReturnMP4URL)
        )
        noReturnGenerator.requestedTimeToleranceBefore = .zero
        noReturnGenerator.requestedTimeToleranceAfter = .zero
        let noReturnFrame = try await noReturnGenerator.image(
            at: CMTime(seconds: 0.9, preferredTimescale: 600)
        ).image
        let cursorReturnDifference = zip(
            rgbaPixels(from: returnFrame),
            rgbaPixels(from: noReturnFrame)
        ).reduce(0) {
            $0 + abs(Int($1.0) - Int($1.1))
        }
        XCTAssertGreaterThan(
            cursorReturnDifference,
            5_000,
            "Video export should render the eased cursor return near the end."
        )
        let optimizedCursorFrame = try await noShortcutGenerator.image(
            at: CMTime(seconds: 0.34, preferredTimescale: 600)
        ).image
        let rawCursorFrame = try await noReturnGenerator.image(
            at: CMTime(seconds: 0.34, preferredTimescale: 600)
        ).image
        let optimizedCursorDifference = zip(
            rgbaPixels(from: optimizedCursorFrame),
            rgbaPixels(from: rawCursorFrame)
        ).reduce(0) {
            $0 + abs(Int($1.0) - Int($1.1))
        }
        XCTAssertGreaterThan(
            optimizedCursorDifference,
            5_000,
            "Video export should render the processed rapid cursor path."
        )
        let cropPixels = rgbaPixels(from: cropFrame)
        let cropWidth = Int(exportedSize.width)
        let cropHeight = Int(exportedSize.height)
        let leftBlue = pixel(
            in: cropPixels,
            width: cropWidth,
            x: cropWidth / 5,
            y: cropHeight / 2
        ).blue
        let rightBlue = pixel(
            in: cropPixels,
            width: cropWidth,
            x: cropWidth * 4 / 5,
            y: cropHeight / 2
        ).blue
        XCTAssertGreaterThan(
            Int(rightBlue) - Int(leftBlue),
            70,
            "Square export should center-crop the horizontal source, not stretch or letterbox it."
        )
        XCTAssertEqual(exportedDuration, 1, accuracy: 0.08)
        XCTAssertGreaterThan(
            try fileSize(at: mp4URL),
            2_000
        )

        let gifSource = try XCTUnwrap(
            CGImageSourceCreateWithURL(gifURL as CFURL, nil)
        )
        XCTAssertGreaterThanOrEqual(CGImageSourceGetCount(gifSource), 8)
        XCTAssertGreaterThan(try fileSize(at: gifURL), 2_000)
    }

    @MainActor
    func testCameraPictureInPictureUsesRealRoundedMask() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("green.mp4")
        let cameraURL = directory.appendingPathComponent("red.mp4")
        try await makeSyntheticVideoOnly(
            at: sourceURL,
            solidRGB: (red: 0, green: 255, blue: 0)
        )
        try await makeSyntheticVideoOnly(
            at: cameraURL,
            solidRGB: (red: 255, green: 0, blue: 0)
        )
        let project = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 1)]
        )
        let exporter = VideoExporter()
        let cameraStyle = CameraOverlayStyle(
            position: .bottomRight,
            sizeFraction: 0.5,
            mirrored: true,
            cornerRadius: 24
        )
        let image = try await exporter.renderFrame(
            sourceURL: sourceURL,
            cameraURL: cameraURL,
            project: project,
            timelineTime: 0.4,
            canvasStyle: .plain,
            cameraStyle: cameraStyle,
            frameRate: 15
        )
        try assertRoundedRedCamera(in: image)

        let exportedURL = directory.appendingPathComponent("rounded-camera.mp4")
        try await exporter.export(
            sourceURL: sourceURL,
            cameraURL: cameraURL,
            project: project,
            canvasStyle: .plain,
            cameraStyle: cameraStyle,
            destinationURL: exportedURL,
            frameRate: 15
        )
        let generator = AVAssetImageGenerator(
            asset: AVURLAsset(url: exportedURL)
        )
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let exportedFrame = try await generator.image(
            at: CMTime(seconds: 0.4, preferredTimescale: 600)
        ).image
        try assertRoundedRedCamera(in: exportedFrame)
    }

    private func assertRoundedRedCamera(in image: CGImage) throws {
        let pixels = rgbaPixels(from: image)
        var redCoordinates: [(x: Int, y: Int)] = []
        for y in 0..<image.height {
            for x in 0..<image.width {
                let value = pixel(in: pixels, width: image.width, x: x, y: y)
                if value.red > 180, value.green < 80, value.blue < 80 {
                    redCoordinates.append((x, y))
                }
            }
        }
        XCTAssertGreaterThan(redCoordinates.count, 1_000)
        let minX = try XCTUnwrap(redCoordinates.map(\.x).min())
        let maxX = try XCTUnwrap(redCoordinates.map(\.x).max())
        let minY = try XCTUnwrap(redCoordinates.map(\.y).min())
        let maxY = try XCTUnwrap(redCoordinates.map(\.y).max())
        let center = pixel(
            in: pixels,
            width: image.width,
            x: (minX + maxX) / 2,
            y: (minY + maxY) / 2
        )
        XCTAssertGreaterThan(center.red, 180)
        XCTAssertLessThan(center.green, 80)

        for corner in [
            (x: minX, y: minY),
            (x: maxX, y: minY),
            (x: minX, y: maxY),
            (x: maxX, y: maxY)
        ] {
            let value = pixel(
                in: pixels,
                width: image.width,
                x: corner.x,
                y: corner.y
            )
            XCTAssertGreaterThan(
                value.green,
                150,
                "The camera corner must reveal the screen beneath it."
            )
            XCTAssertLessThan(value.red, 100)
        }
    }

    @MainActor
    func testGIFExportCancellationRemovesPartialFile() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.mp4")
        let destinationURL = directory.appendingPathComponent("cancelled.gif")
        try await makeSyntheticMedia(at: sourceURL)
        let project = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 1)]
        )
        let exportTask = Task {
            try await VideoExporter().export(
                sourceURL: sourceURL,
                project: project,
                canvasStyle: .plain,
                destinationURL: destinationURL,
                format: .gif,
                frameRate: 20
            )
        }
        try await Task.sleep(for: .milliseconds(20))
        exportTask.cancel()

        do {
            try await exportTask.value
            XCTFail("A cancelled GIF export should not complete.")
        } catch is CancellationError {
            XCTAssertFalse(FileManager.default.fileExists(atPath: destinationURL.path))
        } catch {
            XCTFail("Expected CancellationError, received \(error).")
        }
    }

    func testFadeTransitionDipsToBlackAtCut() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.mp4")
        try await makeSyntheticMedia(at: sourceURL)
        let clips = [
            TimelineClip(sourceStart: 0, duration: 0.5),
            TimelineClip(sourceStart: 0.5, duration: 0.5)
        ]
        let project = TimelineProject(
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
        let exporter = VideoExporter()

        let atCut = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: project,
            timelineTime: 0.5,
            canvasStyle: .plain,
            frameRate: 30
        )
        let awayFromCut = try await exporter.renderFrame(
            sourceURL: sourceURL,
            project: project,
            timelineTime: 0.1,
            canvasStyle: .plain,
            frameRate: 30
        )

        let cutLuma = averageLuma(atCut)
        let normalLuma = averageLuma(awayFromCut)
        XCTAssertGreaterThan(normalLuma, 20)
        XCTAssertLessThan(cutLuma, normalLuma * 0.3)
    }

    func testZoomTransitionRendersAroundCutAlongsideRegularZoom() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.mp4")
        try await makeSyntheticMedia(at: sourceURL)
        // A regular zoom overlapping the transition window exercises the
        // merged transform-ramp path.
        let clips = [
            TimelineClip(sourceStart: 0, duration: 0.5),
            TimelineClip(sourceStart: 0.5, duration: 0.5)
        ]
        let project = TimelineProject(
            clips: clips,
            zooms: [
                ZoomEvent(
                    start: 0.2,
                    duration: 0.6,
                    scale: 1.6,
                    focusX: 0.5,
                    focusY: 0.5
                )
            ],
            transitions: [
                ClipTransition(
                    leftClipID: clips[0].id,
                    rightClipID: clips[1].id,
                    style: .zoom,
                    duration: 0.4
                )
            ]
        )
        let exporter = VideoExporter()

        for time in [0.05, 0.4, 0.5, 0.6, 0.95] {
            let frame = try await exporter.renderFrame(
                sourceURL: sourceURL,
                project: project,
                timelineTime: time,
                canvasStyle: .plain,
                frameRate: 30
            )
            XCTAssertGreaterThan(frame.width, 0)
            XCTAssertGreaterThan(averageLuma(frame), 5)
        }
    }

    private func averageLuma(_ image: CGImage) -> Double {
        let ciImage = CIImage(cgImage: image)
        guard let filter = CIFilter(
            name: "CIAreaAverage",
            parameters: [
                kCIInputImageKey: ciImage,
                kCIInputExtentKey: CIVector(cgRect: ciImage.extent)
            ]
        ), let output = filter.outputImage else {
            return 0
        }
        var bitmap = [UInt8](repeating: 0, count: 4)
        CIContext().render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )
        return (
            Double(bitmap[0]) + Double(bitmap[1]) + Double(bitmap[2])
        ) / 3
    }

    private func makeTestSnapshot(
        sourceURL: URL,
        project: TimelineProject
    ) -> ScreenFreeProjectSnapshot {
        ScreenFreeProjectSnapshot(
            version: ScreenFreeProjectSnapshot.currentVersion,
            sourcePath: sourceURL.path,
            cameraPath: nil,
            project: project,
            canvasAspectRatio: .source,
            canvasContentMode: .fit,
            canvasPadding: 0,
            cornerRadius: 0,
            backgroundHue: 0.68,
            backgroundMode: .solid,
            wallpaperPreset: .aurora,
            backgroundImagePath: nil,
            backgroundBlur: 0,
            shadowStrength: 0,
            cursorSize: 1.3,
            cursorReplacement: .arrow,
            showCursor: true,
            hideCursorWhenIdle: false,
            cursorIdleTimeout: 2,
            cursorTailFreeze: 0,
            cursorLoopToStart: false,
            removeCursorShakes: false,
            cursorShakeThreshold: 0.012,
            optimizeRapidCursorChanges: false,
            smoothCursorMovement: true,
            backgroundMusicPath: nil,
            backgroundMusicVolume: 0.2,
            recordedAudioLayout: nil,
            systemAudioVolume: 1,
            microphoneAudioVolume: 1,
            microphoneAudioMuted: false,
            showClickRipple: true,
            clickEffectPreset: .ripple,
            showShortcutOverlay: true,
            showCaptions: true,
            captionFontSize: 34,
            captionLanguage: "zh-CN",
            captionVocabulary: "",
            zoomScale: 1.8,
            zoomDuration: 3.2,
            zoomMotionPreset: .mellow,
            zoomCustomTransitionDuration: 0.82,
            zoomCustomX1: 0.25,
            zoomCustomY1: 0.1,
            zoomCustomX2: 0.25,
            zoomCustomY2: 1,
            motionBlurEnabled: false,
            motionBlurStrength: 0.42,
            cursorMotionBlur: 0.58,
            zoomMotionBlur: 0.45,
            panMotionBlur: 0.34,
            cameraSize: 0.24,
            cameraCornerRadius: 18,
            cameraMirrored: true,
            cameraPosition: .bottomRight,
            transitionStyle: .fade,
            transitionDuration: 0.4,
            updatedAt: Date()
        )
    }

    private func makeSyntheticMedia(
        at url: URL,
        highFrequencyPattern: Bool = false
    ) async throws {
        let videoOnlyURL = url
            .deletingLastPathComponent()
            .appendingPathComponent("video-only.mp4")
        let audioURL = url
            .deletingLastPathComponent()
            .appendingPathComponent("audio.caf")
        try await makeSyntheticVideoOnly(
            at: videoOnlyURL,
            highFrequencyPattern: highFrequencyPattern
        )
        try makeSilentAudio(at: audioURL)

        let videoAsset = AVURLAsset(url: videoOnlyURL)
        let audioAsset = AVURLAsset(url: audioURL)
        let composition = AVMutableComposition()
        let range = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: 1, preferredTimescale: 600)
        )
        let sourceVideoTracks = try await videoAsset.loadTracks(
            withMediaType: .video
        )
        let sourceAudioTracks = try await audioAsset.loadTracks(
            withMediaType: .audio
        )
        let sourceVideoTrack = try XCTUnwrap(sourceVideoTracks.first)
        let sourceAudioTrack = try XCTUnwrap(sourceAudioTracks.first)
        let videoTrack = try XCTUnwrap(
            composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        )
        let audioTrack = try XCTUnwrap(
            composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        )
        try videoTrack.insertTimeRange(range, of: sourceVideoTrack, at: .zero)
        try audioTrack.insertTimeRange(range, of: sourceAudioTrack, at: .zero)

        let session = try XCTUnwrap(
            AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetHighestQuality
            )
        )
        session.outputURL = url
        session.outputFileType = .mp4
        await session.export()
        XCTAssertEqual(session.status, .completed)
    }

    private func makeSyntheticVideoOnly(
        at url: URL,
        solidRGB: (red: UInt8, green: UInt8, blue: UInt8)? = nil,
        highFrequencyPattern: Bool = false
    ) async throws {
        let width = 320
        let height = 180
        let frameRate: Int32 = 15
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height
            ]
        )
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )
        XCTAssertTrue(writer.canAdd(input))
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        for frameIndex in 0..<15 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(2))
            }
            let pixelBuffer = try XCTUnwrap(makePixelBuffer(
                width: width,
                height: height,
                frameIndex: frameIndex,
                solidRGB: solidRGB,
                highFrequencyPattern: highFrequencyPattern
            ))
            XCTAssertTrue(
                adaptor.append(
                    pixelBuffer,
                    withPresentationTime: CMTime(
                        value: Int64(frameIndex),
                        timescale: frameRate
                    )
                )
            )
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
    }

    private func makeSilentAudio(
        at url: URL,
        duration: TimeInterval = 1
    ) throws {
        let frameCount = AVAudioFrameCount(
            max(1, (48_000 * duration).rounded())
        )
        let format = try XCTUnwrap(
            AVAudioFormat(
                standardFormatWithSampleRate: 48_000,
                channels: 2
            )
        )
        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings
        )
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: frameCount
            )
        )
        buffer.frameLength = frameCount
        try file.write(from: buffer)
    }

    private func makePixelBuffer(
        width: Int,
        height: Int,
        frameIndex: Int,
        solidRGB: (red: UInt8, green: UInt8, blue: UInt8)? = nil,
        highFrequencyPattern: Bool = false
    ) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true
            ] as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        for y in 0..<height {
            let row = baseAddress
                .advanced(by: y * bytesPerRow)
                .assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                let offset = x * 4
                if let solidRGB {
                    row[offset] = solidRGB.blue
                    row[offset + 1] = solidRGB.green
                    row[offset + 2] = solidRGB.red
                } else if highFrequencyPattern {
                    let value: UInt8 = ((x / 2 + y / 2) % 2 == 0)
                        ? 238 : 18
                    row[offset] = value
                    row[offset + 1] = value
                    row[offset + 2] = value
                } else {
                    row[offset] = UInt8((x + frameIndex * 9) % 255)
                    row[offset + 1] = UInt8((y * 2 + frameIndex * 5) % 255)
                    row[offset + 2] = UInt8((frameIndex * 17) % 255)
                }
                row[offset + 3] = 255
            }
        }
        return pixelBuffer
    }

    private func fileSize(at url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values.fileSize ?? 0)
    }

    private func rgbaPixels(from image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        CIContext().render(
            CIImage(cgImage: image),
            toBitmap: &bytes,
            rowBytes: width * 4,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return bytes
    }

    private func pixel(
        in bytes: [UInt8],
        width: Int,
        x: Int,
        y: Int
    ) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        let offset = (y * width + x) * 4
        return (
            bytes[offset],
            bytes[offset + 1],
            bytes[offset + 2],
            bytes[offset + 3]
        )
    }

    private func meanHorizontalContrast(
        _ bytes: [UInt8],
        width: Int,
        height: Int,
        normalizedRect: CGRect
    ) -> Double {
        let minX = max(1, Int(normalizedRect.minX * Double(width)))
        let maxX = min(width - 1, Int(normalizedRect.maxX * Double(width)))
        let minY = max(0, Int(normalizedRect.minY * Double(height)))
        let maxY = min(height - 1, Int(normalizedRect.maxY * Double(height)))
        guard minX <= maxX, minY <= maxY else { return 0 }
        var total = 0.0
        var count = 0
        for y in minY...maxY {
            for x in minX...maxX {
                let offset = (y * width + x) * 4
                let previous = offset - 4
                let value = (
                    Double(bytes[offset])
                        + Double(bytes[offset + 1])
                        + Double(bytes[offset + 2])
                ) / 3
                let previousValue = (
                    Double(bytes[previous])
                        + Double(bytes[previous + 1])
                        + Double(bytes[previous + 2])
                ) / 3
                total += abs(value - previousValue)
                count += 1
            }
        }
        return total / Double(max(1, count))
    }

    private func differenceBounds(
        _ first: CGImage,
        _ second: CGImage
    ) -> CGRect? {
        guard first.width == second.width, first.height == second.height else {
            return nil
        }
        let firstPixels = rgbaPixels(from: first)
        let secondPixels = rgbaPixels(from: second)
        var minX = first.width
        var minY = first.height
        var maxX = -1
        var maxY = -1
        for y in 0..<first.height {
            for x in 0..<first.width {
                let offset = (y * first.width + x) * 4
                let difference = (0..<3).reduce(0) {
                    $0 + abs(
                        Int(firstPixels[offset + $1])
                            - Int(secondPixels[offset + $1])
                    )
                }
                guard difference > 72 else { continue }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX + 1,
            height: maxY - minY + 1
        )
    }
}
