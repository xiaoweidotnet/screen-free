import AppKit
import AVFoundation
import CoreImage
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import QuartzCore
import ScreenFreeCore
import UniformTypeIdentifiers

enum VideoExportError: LocalizedError {
    case missingVideoTrack
    case cannotCreateCompositionTrack
    case cannotCreateExportSession
    case cannotReadComposedFrame
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .missingVideoTrack:
            return "The source does not contain a video track."
        case .cannotCreateCompositionTrack:
            return "The editable timeline could not be created."
        case .cannotCreateExportSession:
            return "The export session could not be created."
        case .cannotReadComposedFrame:
            return "The composed frame could not be read."
        case .exportFailed:
            return "Video export failed."
        }
    }
}

struct CanvasRenderStyle: Sendable {
    var aspectRatio: CanvasAspectRatio
    var contentMode: CanvasContentMode
    var padding: CGFloat
    var cornerRadius: CGFloat
    var backgroundHue: CGFloat
    var backgroundMode: CanvasBackgroundMode
    var wallpaperPreset: WallpaperPreset
    var backgroundImageURL: URL?
    var backgroundBlur: CGFloat
    var shadowOpacity: CGFloat
    var cursorSize: CGFloat
    var cursorReplacement: CursorReplacementStyle
    var showCursor: Bool
    var hideCursorWhenIdle: Bool
    var cursorIdleTimeout: TimeInterval
    var cursorTailFreeze: TimeInterval
    var cursorLoopToStart: Bool
    var removeCursorShakes: Bool
    var cursorShakeThreshold: CGFloat
    var optimizeRapidCursorChanges: Bool
    var smoothCursorMovement: Bool
    var clickEffect: ClickEffectPreset
    var showShortcuts: Bool
    var showCaptions: Bool
    var captionFontSize: CGFloat
    var zoomMotion: ZoomMotionStyle
    var motionBlur: MotionBlurStyle

    static let plain = CanvasRenderStyle(
        aspectRatio: .source,
        contentMode: .fit,
        padding: 0,
        cornerRadius: 0,
        backgroundHue: 0.68,
        backgroundMode: .gradient,
        wallpaperPreset: .aurora,
        backgroundImageURL: nil,
        backgroundBlur: 0,
        shadowOpacity: 0,
        cursorSize: 1,
        cursorReplacement: .arrow,
        showCursor: true,
        hideCursorWhenIdle: false,
        cursorIdleTimeout: 2,
        cursorTailFreeze: 0,
        cursorLoopToStart: false,
        removeCursorShakes: false,
        cursorShakeThreshold: 0.012,
        optimizeRapidCursorChanges: false,
        smoothCursorMovement: false,
        clickEffect: .none,
        showShortcuts: false,
        showCaptions: true,
        captionFontSize: 34,
        zoomMotion: ZoomMotionStyle(preset: .mellow),
        motionBlur: .disabled
    )
}

struct VideoExporter {
    struct PreparedComposition {
        let composition: AVMutableComposition
        let videoComposition: AVMutableVideoComposition
        let audioMix: AVAudioMix?
        let cropGeometry: CanvasCropGeometry
    }

    func prepare(
        sourceURL: URL,
        cameraURL: URL? = nil,
        backgroundMusicURL: URL? = nil,
        backgroundMusicVolume: Double = 0.2,
        recordedAudioMix: RecordedAudioMixStyle? = nil,
        project: TimelineProject,
        frameRate: Int = 60,
        renderSizeOverride: CGSize? = nil,
        canvasStyle: CanvasRenderStyle = .plain,
        cameraStyle: CameraOverlayStyle = CameraOverlayStyle(
            position: .bottomRight,
            sizeFraction: 0.24,
            mirrored: true
        )
    ) async throws -> PreparedComposition {
        let sourceAsset = AVURLAsset(url: sourceURL)
        guard let sourceVideoTrack = try await sourceAsset.loadTracks(
            withMediaType: .video
        ).first else {
            throw VideoExportError.missingVideoTrack
        }

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw VideoExportError.cannotCreateCompositionTrack
        }

        let sourceAudioTracks = try await sourceAsset.loadTracks(
            withMediaType: .audio
        )
        let audioTrackPairs: [(AVAssetTrack, AVMutableCompositionTrack)] = sourceAudioTracks.compactMap {
            sourceTrack in
            guard let compositionTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                return nil
            }
            return (sourceTrack, compositionTrack)
        }
        var audioParameters = audioTrackPairs.map {
            AVMutableAudioMixInputParameters(track: $0.1)
        }

        var cameraAsset: AVURLAsset?
        var cameraSourceTrack: AVAssetTrack?
        var cameraCompositionTrack: AVMutableCompositionTrack?
        var cameraTrackTimeRange = CMTimeRange.invalid
        if let cameraURL {
            let loadedCameraAsset = AVURLAsset(url: cameraURL)
            cameraAsset = loadedCameraAsset
            cameraSourceTrack = try await loadedCameraAsset.loadTracks(
                withMediaType: .video
            ).first
            if let cameraSourceTrack {
                cameraTrackTimeRange = try await cameraSourceTrack.load(.timeRange)
                cameraCompositionTrack = composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                )
            }
        }

        var insertionTime = CMTime.zero
        for clip in project.clips {
            let sourceRange = CMTimeRange(
                start: CMTime(seconds: clip.sourceStart, preferredTimescale: 600),
                duration: CMTime(seconds: clip.duration, preferredTimescale: 600)
            )
            try compositionVideoTrack.insertTimeRange(
                sourceRange,
                of: sourceVideoTrack,
                at: insertionTime
            )
            for (index, pair) in audioTrackPairs.enumerated() {
                let (sourceAudioTrack, compositionAudioTrack) = pair
                try? compositionAudioTrack.insertTimeRange(
                    sourceRange,
                    of: sourceAudioTrack,
                    at: insertionTime
                )
                let combinedGain = recordedAudioMix?.gain(
                    forTrackAt: index,
                    clipVolume: clip.volume
                ) ?? clip.volume
                // The mix style already prevents clipping via its own peak
                // ceiling; 16 only guards against pathological inputs while
                // still letting automatic loudness repair through.
                audioParameters[index].setVolume(
                    Float(
                        combinedGain.clamped(to: 0...16)
                    ),
                    at: insertionTime
                )
            }
            if let cameraSourceTrack, let cameraCompositionTrack {
                let cameraSourceStart = max(
                    cameraTrackTimeRange.start.seconds,
                    clip.sourceStart
                )
                let availableDuration = max(
                    0,
                    min(
                        clip.duration,
                        cameraTrackTimeRange.end.seconds - cameraSourceStart
                    )
                )
                if availableDuration > 0.02 {
                    let cameraRange = CMTimeRange(
                        start: CMTime(
                            seconds: cameraSourceStart,
                            preferredTimescale: 600
                        ),
                        duration: CMTime(
                            seconds: availableDuration,
                            preferredTimescale: 600
                        )
                    )
                    try cameraCompositionTrack.insertTimeRange(
                        cameraRange,
                        of: cameraSourceTrack,
                        at: insertionTime
                    )
                }
            }

            let insertedRange = CMTimeRange(
                start: insertionTime,
                duration: sourceRange.duration
            )
            let targetDuration = CMTime(
                seconds: clip.timelineDuration,
                preferredTimescale: 600
            )
            if abs(clip.playbackRate - 1) > 0.001 {
                compositionVideoTrack.scaleTimeRange(
                    insertedRange,
                    toDuration: targetDuration
                )
                for (_, compositionAudioTrack) in audioTrackPairs {
                    compositionAudioTrack.scaleTimeRange(
                        insertedRange,
                        toDuration: targetDuration
                    )
                }
                cameraCompositionTrack?.scaleTimeRange(
                    insertedRange,
                    toDuration: targetDuration
                )
            }
            insertionTime = insertionTime + targetDuration
        }
        _ = cameraAsset

        var backgroundMusicAsset: AVURLAsset?
        if let backgroundMusicURL {
            let musicAsset = AVURLAsset(url: backgroundMusicURL)
            backgroundMusicAsset = musicAsset
            if let sourceMusicTrack = try await musicAsset.loadTracks(
                withMediaType: .audio
            ).first {
                let sourceRange = try await sourceMusicTrack.load(.timeRange)
                if sourceRange.duration.seconds > 0.02,
                   let musicTrack = composition.addMutableTrack(
                       withMediaType: .audio,
                       preferredTrackID: kCMPersistentTrackID_Invalid
                   ) {
                    var musicInsertionTime = CMTime.zero
                    while musicInsertionTime < insertionTime {
                        let remaining = insertionTime - musicInsertionTime
                        let segmentDuration = CMTimeMinimum(
                            sourceRange.duration,
                            remaining
                        )
                        let segmentRange = CMTimeRange(
                            start: sourceRange.start,
                            duration: segmentDuration
                        )
                        try musicTrack.insertTimeRange(
                            segmentRange,
                            of: sourceMusicTrack,
                            at: musicInsertionTime
                        )
                        musicInsertionTime = musicInsertionTime + segmentDuration
                    }
                    let musicParameters = AVMutableAudioMixInputParameters(
                        track: musicTrack
                    )
                    musicParameters.setVolume(
                        Float(backgroundMusicVolume.clamped(to: 0...1)),
                        at: .zero
                    )
                    audioParameters.append(musicParameters)
                }
            }
        }
        _ = backgroundMusicAsset

        let naturalSize = try await sourceVideoTrack.load(.naturalSize)
        let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(
            preferredTransform
        )
        let sourceRenderSize = CGSize(
            width: abs(transformedRect.width),
            height: abs(transformedRect.height)
        )
        let cropGeometry = if let renderSizeOverride {
            CanvasCropGeometry(
                sourceSize: sourceRenderSize,
                targetSize: renderSizeOverride,
                contentMode: canvasStyle.contentMode
            )
        } else {
            CanvasCropGeometry(
                sourceSize: sourceRenderSize,
                aspectRatio: canvasStyle.aspectRatio,
                contentMode: canvasStyle.contentMode
            )
        }
        let renderSize = cropGeometry.renderSize
        let normalization = CGAffineTransform(
            translationX: -transformedRect.minX,
            y: -transformedRect.minY
        )
        let baseTransform = preferredTransform
            .concatenating(normalization)
            .concatenating(cropGeometry.transform)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(
            assetTrack: compositionVideoTrack
        )
        layerInstruction.setTransform(baseTransform, at: .zero)
        applyZooms(
            project.zooms,
            to: layerInstruction,
            baseTransform: baseTransform,
            cropGeometry: cropGeometry,
            totalDuration: project.duration,
            project: project,
            style: canvasStyle
        )

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(
            start: .zero,
            duration: insertionTime
        )
        var roundedCameraInstruction: RoundedCameraCompositionInstruction?
        var compositorCameraTrackID: CMPersistentTrackID?
        var compositorCameraLayerInstruction:
            AVVideoCompositionLayerInstruction?
        var compositorCameraFrame = CGRect.zero
        var compositorCameraCornerRadius: CGFloat = 0
        if let cameraSourceTrack, let cameraCompositionTrack {
            let cameraLayerInstruction = AVMutableVideoCompositionLayerInstruction(
                assetTrack: cameraCompositionTrack
            )
            let cameraNaturalSize = try await cameraSourceTrack.load(.naturalSize)
            let cameraPreferredTransform = try await cameraSourceTrack.load(
                .preferredTransform
            )
            let cameraRect = CGRect(origin: .zero, size: cameraNaturalSize)
                .applying(cameraPreferredTransform)
            let cameraNormalization = CGAffineTransform(
                translationX: -cameraRect.minX,
                y: -cameraRect.minY
            )
            let cameraBase = cameraPreferredTransform.concatenating(
                cameraNormalization
            )
            let normalizedCameraSize = CGSize(
                width: abs(cameraRect.width),
                height: abs(cameraRect.height)
            )
            let maximumWidth = renderSize.width
                * cameraStyle.sizeFraction.clamped(to: 0.12...0.5)
            let maximumHeight = renderSize.height * 0.30
            let cameraScale = min(
                maximumWidth / max(1, normalizedCameraSize.width),
                maximumHeight / max(1, normalizedCameraSize.height)
            )
            let displayedSize = CGSize(
                width: normalizedCameraSize.width * cameraScale,
                height: normalizedCameraSize.height * cameraScale
            )
            let margin = max(24, canvasStyle.padding + 16)
            let origin: CGPoint
            switch cameraStyle.position {
            case .topLeft:
                origin = CGPoint(
                    x: margin,
                    y: renderSize.height - displayedSize.height - margin
                )
            case .topRight:
                origin = CGPoint(
                    x: renderSize.width - displayedSize.width - margin,
                    y: renderSize.height - displayedSize.height - margin
                )
            case .bottomLeft:
                origin = CGPoint(x: margin, y: margin)
            case .bottomRight:
                origin = CGPoint(
                    x: renderSize.width - displayedSize.width - margin,
                    y: margin
                )
            }
            var orientedCameraBase = cameraBase
            if cameraStyle.mirrored {
                orientedCameraBase = orientedCameraBase
                    .concatenating(
                        CGAffineTransform(scaleX: -1, y: 1)
                    )
                    .concatenating(
                        CGAffineTransform(
                            translationX: normalizedCameraSize.width,
                            y: 0
                        )
                    )
            }
            let cameraTransform = orientedCameraBase
                .concatenating(
                    CGAffineTransform(scaleX: cameraScale, y: cameraScale)
                )
                .concatenating(
                    CGAffineTransform(
                        translationX: origin.x,
                        y: origin.y
                    )
                )
            cameraLayerInstruction.setTransform(cameraTransform, at: .zero)
            instruction.layerInstructions = [cameraLayerInstruction, layerInstruction]
            let cameraFrame = CGRect(origin: origin, size: displayedSize)
            let cameraRadius = cameraStyle.cornerRadius.clamped(
                to: 0...min(displayedSize.width, displayedSize.height) / 2
            )
            compositorCameraTrackID = cameraCompositionTrack.trackID
            compositorCameraLayerInstruction = cameraLayerInstruction
            compositorCameraFrame = cameraFrame
            compositorCameraCornerRadius = cameraRadius
        } else {
            instruction.layerInstructions = [layerInstruction]
        }

        let blurRedactions = project.redactions.filter {
            $0.resolvedPresentation == .redaction
                && $0.resolvedEffect == .blur
        }
        if compositorCameraCornerRadius > 0 || !blurRedactions.isEmpty {
            roundedCameraInstruction = RoundedCameraCompositionInstruction(
                timeRange: instruction.timeRange,
                screenTrackID: compositionVideoTrack.trackID,
                cameraTrackID: compositorCameraTrackID,
                screenLayerInstruction: layerInstruction,
                cameraLayerInstruction: compositorCameraLayerInstruction,
                cameraFrame: compositorCameraFrame,
                cameraCornerRadius: compositorCameraCornerRadius,
                privacyRedactions: blurRedactions
            )
        }

        let videoComposition = AVMutableVideoComposition()
        if let roundedCameraInstruction {
            videoComposition.instructions = [roundedCameraInstruction]
            videoComposition.customVideoCompositorClass =
                RoundedCameraVideoCompositor.self
        } else {
            videoComposition.instructions = [instruction]
        }
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(
            value: 1,
            timescale: CMTimeScale(frameRate.clamped(to: 15...120))
        )
        applyCanvasAndCursor(
            canvasStyle,
            project: project,
            to: videoComposition,
            renderSize: renderSize,
            cropGeometry: cropGeometry
        )

        let audioMix: AVAudioMix?
        if audioParameters.isEmpty {
            audioMix = nil
        } else {
            let mutableAudioMix = AVMutableAudioMix()
            mutableAudioMix.inputParameters = audioParameters
            audioMix = mutableAudioMix
        }

        return PreparedComposition(
            composition: composition,
            videoComposition: videoComposition,
            audioMix: audioMix,
            cropGeometry: cropGeometry
        )
    }

    func export(
        sourceURL: URL,
        cameraURL: URL? = nil,
        backgroundMusicURL: URL? = nil,
        backgroundMusicVolume: Double = 0.2,
        recordedAudioMix: RecordedAudioMixStyle? = nil,
        project: TimelineProject,
        canvasStyle: CanvasRenderStyle,
        cameraStyle: CameraOverlayStyle = CameraOverlayStyle(
            position: .bottomRight,
            sizeFraction: 0.24,
            mirrored: true
        ),
        destinationURL: URL,
        format: ExportFormat = .mp4,
        frameRate: Int = 60,
        quality: ExportQuality = .studio,
        renderSizeOverride: CGSize? = nil,
        presetName: String = AVAssetExportPresetHighestQuality,
        maximumFileSizeBytes: Int64? = nil,
        progress: @escaping @MainActor @Sendable (Double) -> Void = { _ in }
    ) async throws {
        try Task.checkCancellation()
        let prepared = try await prepare(
            sourceURL: sourceURL,
            cameraURL: cameraURL,
            backgroundMusicURL: backgroundMusicURL,
            backgroundMusicVolume: backgroundMusicVolume,
            recordedAudioMix: recordedAudioMix,
            project: project,
            frameRate: frameRate,
            renderSizeOverride: renderSizeOverride,
            canvasStyle: canvasStyle,
            cameraStyle: cameraStyle
        )

        if format == .gif {
            try await exportGIF(
                prepared: prepared,
                duration: project.duration,
                destinationURL: destinationURL,
                frameRate: min(frameRate, 20),
                quality: quality,
                progress: progress
            )
            return
        }

        guard let session = AVAssetExportSession(
            asset: prepared.composition,
            presetName: presetName
        ) else {
            throw VideoExportError.cannotCreateExportSession
        }

        try? FileManager.default.removeItem(at: destinationURL)
        session.outputURL = destinationURL
        session.outputFileType = .mp4
        session.videoComposition = prepared.videoComposition
        session.audioMix = prepared.audioMix
        session.shouldOptimizeForNetworkUse = true
        if let maximumFileSizeBytes {
            session.fileLengthLimit = max(1_000_000, maximumFileSizeBytes)
        }

        let sessionBox = SendableExportSession(session)
        let progressTask = Task {
            while !Task.isCancelled {
                await progress(Double(sessionBox.value.progress))
                switch sessionBox.value.status {
                case .completed, .failed, .cancelled:
                    return
                case .unknown, .waiting, .exporting:
                    break
                @unknown default:
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        await withTaskCancellationHandler {
            await session.export()
        } onCancel: {
            sessionBox.value.cancelExport()
        }
        progressTask.cancel()
        _ = await progressTask.result
        do {
            try Task.checkCancellation()
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }
        if session.status == .cancelled {
            try? FileManager.default.removeItem(at: destinationURL)
            throw CancellationError()
        }
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: destinationURL)
            throw session.error ?? VideoExportError.exportFailed
        }
        await progress(1)
    }

    func renderFrame(
        sourceURL: URL,
        cameraURL: URL? = nil,
        project: TimelineProject,
        timelineTime: TimeInterval,
        canvasStyle: CanvasRenderStyle,
        cameraStyle: CameraOverlayStyle = CameraOverlayStyle(
            position: .bottomRight,
            sizeFraction: 0.24,
            mirrored: true
        ),
        frameRate: Int = 60
    ) async throws -> CGImage {
        var stillStyle = canvasStyle
        stillStyle.showCursor = false
        stillStyle.clickEffect = .none
        stillStyle.showShortcuts = false
        stillStyle.showCaptions = false
        let prepared = try await prepare(
            sourceURL: sourceURL,
            cameraURL: cameraURL,
            project: project,
            frameRate: frameRate,
            canvasStyle: stillStyle,
            cameraStyle: cameraStyle
        )
        let safeTime = timelineTime.clamped(
            to: 0...max(0, project.duration - 1 / Double(max(1, frameRate)))
        )
        let reader = try AVAssetReader(asset: prepared.composition)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: safeTime, preferredTimescale: 600),
            duration: CMTime(
                value: 1,
                timescale: CMTimeScale(frameRate.clamped(to: 15...120))
            )
        )
        let videoTracks = try await prepared.composition.loadTracks(
            withMediaType: .video
        )
        let output = AVAssetReaderVideoCompositionOutput(
            videoTracks: videoTracks,
            videoSettings: [
                kCVPixelBufferPixelFormatTypeKey as String:
                    Int(kCVPixelFormatType_32BGRA)
            ]
        )
        output.videoComposition = prepared.videoComposition
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw VideoExportError.cannotReadComposedFrame
        }
        reader.add(output)
        guard reader.startReading(),
              let sampleBuffer = output.copyNextSampleBuffer(),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw reader.error ?? VideoExportError.cannotReadComposedFrame
        }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let result = CIContext().createCGImage(
            image,
            from: CGRect(
                origin: .zero,
                size: prepared.videoComposition.renderSize
            )
        ) else {
            throw VideoExportError.cannotReadComposedFrame
        }
        return composeCurrentOverlays(
            over: result,
            project: project,
            at: safeTime,
            style: canvasStyle,
            cropGeometry: prepared.cropGeometry
        )
    }

    private func composeCurrentOverlays(
        over image: CGImage,
        project: TimelineProject,
        at timelineTime: TimeInterval,
        style: CanvasRenderStyle,
        cropGeometry: CanvasCropGeometry
    ) -> CGImage {
        let duration = style.clickEffect.duration
        let activeClick = project.clicks.reversed().compactMap({ click -> (
                  click: MouseClick,
                  start: TimeInterval
              )? in
                  guard let start = project.timelineTime(
                      forSourceTime: click.time
                  ),
                        timelineTime >= start,
                        timelineTime <= start + duration else {
                      return nil
                  }
                  return (click, start)
              }).first
        let cursor = style.showCursor
            && currentCursorIsVisible(
                project: project,
                at: timelineTime,
                style: style
            )
            ? project.cursorSample(
                atTimelineTime: timelineTime,
                freezeBeforeEnd: style.cursorTailFreeze,
                loopToStart: style.cursorLoopToStart,
                removeShakes: style.removeCursorShakes,
                shakeThreshold: style.cursorShakeThreshold,
                optimizeRapidChanges: style.optimizeRapidCursorChanges,
                smoothMovement: style.smoothCursorMovement
            )
            : nil
        let sourceTime = project.sourceTime(forTimelineTime: timelineTime)
        let caption = style.showCaptions ? project.captions.last {
            guard let sourceTime else { return false }
            return sourceTime >= $0.sourceStart
                && sourceTime <= $0.sourceStart + $0.duration
        } : nil
        let shortcut = style.showShortcuts
            ? activeShortcut(in: project, at: timelineTime)
            : nil
        let redactions = project.activeRedactions(
            atTimelineTime: timelineTime
        )
        let annotations = sourceTime.map {
            project.activeAnnotations(atSourceTime: $0)
        } ?? []
        let motionBlur = MotionBlurResolver.resolve(
            at: timelineTime,
            project: project,
            zoomMotion: style.zoomMotion,
            style: style.motionBlur,
            renderSize: CGSize(width: image.width, height: image.height),
            cursorTailFreeze: style.cursorTailFreeze,
            cursorLoopToStart: style.cursorLoopToStart,
            removeCursorShakes: style.removeCursorShakes,
            cursorShakeThreshold: style.cursorShakeThreshold,
            optimizeRapidCursorChanges: style.optimizeRapidCursorChanges,
            smoothCursorMovement: style.smoothCursorMovement
        )
        guard activeClick != nil
                || cursor != nil
                || caption != nil
                || shortcut != nil
                || !redactions.isEmpty
                || !annotations.isEmpty,
              let context = CGContext(
                  data: nil,
                  width: image.width,
                  height: image.height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return image
        }

        let bounds = CGRect(
            x: 0,
            y: 0,
            width: image.width,
            height: image.height
        )
        context.interpolationQuality = .high
        context.draw(image, in: bounds)

        let padding = min(
            style.padding,
            min(bounds.width, bounds.height) * 0.32
        )
        let videoFrame = bounds.insetBy(dx: padding, dy: padding)
        if let cursor,
           cropGeometry.containsSourcePoint(
               x: cursor.normalizedX,
               y: cursor.normalizedY
           ) {
            let cursorImage = blurredImage(
                CursorArtwork.cgImage(for: style.cursorReplacement),
                radius: motionBlur.cursorRadius
            )
            let layerPoint = cursorPoint(
                for: cursor,
                at: timelineTime,
                project: project,
                in: videoFrame,
                cropGeometry: cropGeometry,
                style: style
            )
            let drawPoint = CGPoint(
                x: layerPoint.x,
                y: bounds.height - layerPoint.y
            )
            let sourceSize = CursorArtwork.size(
                for: style.cursorReplacement
            )
            let hotspot = CursorArtwork.hotspot(
                for: style.cursorReplacement
            )
            let scale = style.cursorSize.clamped(to: 0.6...2.5)
            let size = CGSize(
                width: max(12, sourceSize.width * scale),
                height: max(18, sourceSize.height * scale)
            )
            let cursorRect = CGRect(
                x: drawPoint.x - size.width * hotspot.x,
                y: drawPoint.y - size.height * (1 - hotspot.y),
                width: size.width,
                height: size.height
            )
            context.saveGState()
            context.setShadow(
                offset: CGSize(width: 1, height: -1),
                blur: 2,
                color: NSColor.black.withAlphaComponent(0.55).cgColor
            )
            context.draw(cursorImage, in: cursorRect)
            context.restoreGState()
        }

        if let active = activeClick,
           cropGeometry.containsSourcePoint(
               x: active.click.normalizedX,
               y: active.click.normalizedY
           ) {
            let layerPoint = cursorPoint(
                for: CursorSample(
                    time: active.click.time,
                    normalizedX: active.click.normalizedX,
                    normalizedY: active.click.normalizedY
                ),
                at: timelineTime,
                project: project,
                in: videoFrame,
                cropGeometry: cropGeometry,
                style: style
            )
            let point = CGPoint(
                x: layerPoint.x,
                y: bounds.height - layerPoint.y
            )
            let progress = CGFloat(
                ((timelineTime - active.start) / duration).clamped(to: 0...1)
            )
            let baseRadius = 17 * style.cursorSize.clamped(to: 0.6...2.5)
            context.saveGState()
            context.translateBy(x: point.x, y: point.y)

            switch style.clickEffect {
            case .none:
                break
            case .circle:
                let radius = baseRadius * (1 - progress * 0.42)
                context.setFillColor(
                    NSColor.white.withAlphaComponent(
                        0.58 * (1 - progress)
                    ).cgColor
                )
                context.fillEllipse(
                    in: CGRect(
                        x: -radius,
                        y: -radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                )
            case .ripple:
                let radius = baseRadius * (0.35 + progress * 1.45)
                context.setStrokeColor(
                    NSColor.white.withAlphaComponent(
                        0.9 * (1 - progress)
                    ).cgColor
                )
                context.setLineWidth(3)
                context.strokeEllipse(
                    in: CGRect(
                        x: -radius,
                        y: -radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                )
            case .rotation:
                let radius = baseRadius * (0.72 + progress * 0.58)
                context.rotate(by: progress * .pi * 1.65)
                context.setStrokeColor(
                    NSColor.white.withAlphaComponent(
                        0.9 * (1 - progress)
                    ).cgColor
                )
                context.setLineWidth(3)
                context.setLineDash(phase: 0, lengths: [8, 5])
                context.strokeEllipse(
                    in: CGRect(
                        x: -radius,
                        y: -radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                )
            }
            context.restoreGState()
        }

        for redaction in redactions {
            if redaction.resolvedPresentation == .redaction,
               redaction.resolvedEffect == .blur {
                // Blur masks are already composited by the shared Core Image
                // video compositor used for current-frame and MP4 rendering.
                continue
            }
            let width = videoFrame.width * redaction.normalizedWidth
            let height = videoFrame.height * redaction.normalizedHeight
            let rect = CGRect(
                x: videoFrame.minX
                    + videoFrame.width * redaction.normalizedX
                    - width / 2,
                y: videoFrame.maxY
                    - videoFrame.height * redaction.normalizedY
                    - height / 2,
                width: width,
                height: height
            )
            let rounded = CGPath(
                roundedRect: rect,
                cornerWidth: 8,
                cornerHeight: 8,
                transform: nil
            )
            if redaction.resolvedPresentation == .spotlight {
                let dimPath = CGMutablePath()
                dimPath.addRect(videoFrame)
                dimPath.addPath(rounded)
                context.addPath(dimPath)
                context.setFillColor(
                    NSColor.black.withAlphaComponent(
                        redaction.opacity
                    ).cgColor
                )
                context.drawPath(using: .eoFill)
                context.addPath(rounded)
                context.setStrokeColor(
                    NSColor(
                        calibratedHue: redaction.resolvedHighlightHue,
                        saturation: 0.9,
                        brightness: 1,
                        alpha: 0.92
                    ).cgColor
                )
                context.setLineWidth(3)
                context.strokePath()
            } else {
                context.setFillColor(
                    NSColor.black.withAlphaComponent(redaction.opacity).cgColor
                )
                context.addPath(rounded)
                context.fillPath()
            }
        }

        for annotation in annotations {
            let path = annotationCGPath(
                for: annotation,
                progress: annotation.drawProgress(
                    atSourceTime: sourceTime ?? annotation.start
                )
            ) { x, y in
                let point = self.point(
                    x: x,
                    y: y,
                    in: videoFrame,
                    cropGeometry: cropGeometry
                )
                return CGPoint(x: point.x, y: bounds.height - point.y)
            }
            context.saveGState()
            context.setStrokeColor(annotation.color.nsColor.cgColor)
            context.setLineWidth(annotation.lineWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.setShadow(
                offset: .zero,
                blur: 2,
                color: NSColor.black.withAlphaComponent(0.7).cgColor
            )
            context.addPath(path)
            context.strokePath()
            context.restoreGState()
        }

        if let caption {
            drawCurrentCaption(
                caption.text,
                in: context,
                videoFrame: videoFrame,
                fontSize: style.captionFontSize
            )
        }
        if let shortcut {
            drawCurrentShortcut(
                shortcut.label,
                in: context,
                videoFrame: videoFrame
            )
        }
        return context.makeImage() ?? image
    }

    private func activeShortcut(
        in project: TimelineProject,
        at timelineTime: TimeInterval
    ) -> ShortcutEvent? {
        project.shortcuts.reversed().first { shortcut in
            guard let start = project.timelineTime(
                forSourceTime: shortcut.time
            ) else {
                return false
            }
            return timelineTime >= start
                && timelineTime <= start + ShortcutEvent.displayDuration
        }
    }

    private func drawCurrentShortcut(
        _ label: String,
        in context: CGContext,
        videoFrame: CGRect
    ) {
        let height: CGFloat = 54
        let width = CGFloat(34 + label.count * 22)
            .clamped(to: 92...videoFrame.width * 0.72)
        let rect = CGRect(
            x: videoFrame.midX - width / 2,
            y: videoFrame.maxY - height - max(22, videoFrame.height * 0.06),
            width: width,
            height: height
        )
        context.saveGState()
        context.setFillColor(
            NSColor.black.withAlphaComponent(0.76).cgColor
        )
        context.addPath(
            CGPath(
                roundedRect: rect,
                cornerWidth: 12,
                cornerHeight: 12,
                transform: nil
            )
        )
        context.fillPath()
        context.setStrokeColor(
            NSColor.white.withAlphaComponent(0.16).cgColor
        )
        context.setLineWidth(1)
        context.addPath(
            CGPath(
                roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                cornerWidth: 11.5,
                cornerHeight: 11.5,
                transform: nil
            )
        )
        context.strokePath()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributed = NSAttributedString(
            string: label,
            attributes: [
                .font: NSFont.systemFont(
                    ofSize: 24,
                    weight: .semibold
                ),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph
            ]
        )
        let framesetter = CTFramesetterCreateWithAttributedString(
            attributed as CFAttributedString
        )
        let path = CGPath(
            rect: rect.insetBy(dx: 12, dy: 10),
            transform: nil
        )
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(),
            path,
            nil
        )
        CTFrameDraw(frame, context)
        context.restoreGState()
    }

    private func currentCursorIsVisible(
        project: TimelineProject,
        at timelineTime: TimeInterval,
        style: CanvasRenderStyle
    ) -> Bool {
        guard style.showCursor else { return false }
        let returnStart = project.duration
            - TimelineProject.cursorReturnDuration(for: project.duration)
        if style.cursorLoopToStart, timelineTime >= returnStart {
            return true
        }
        guard style.hideCursorWhenIdle,
              let sourceTime = project.sourceTime(
                  forTimelineTime: timelineTime
              ) else {
            return true
        }
        let samples = project.cursorSamples
            .filter { $0.time <= sourceTime }
            .sorted { $0.time < $1.time }
        guard let first = samples.first else { return false }
        var previous = first
        var lastMovement = first.time
        for sample in samples.dropFirst() {
            if hypot(
                sample.normalizedX - previous.normalizedX,
                sample.normalizedY - previous.normalizedY
            ) > 0.0015 {
                lastMovement = sample.time
            }
            previous = sample
        }
        return sourceTime - lastMovement <= style.cursorIdleTimeout
    }

    private func drawCurrentCaption(
        _ caption: String,
        in context: CGContext,
        videoFrame: CGRect,
        fontSize: CGFloat
    ) {
        let size = fontSize.clamped(to: 18...72)
        let height = size * 2.6
        let width = videoFrame.width * 0.76
        let rect = CGRect(
            x: videoFrame.midX - width / 2,
            y: videoFrame.minY + max(26, videoFrame.height * 0.08),
            width: width,
            height: height
        )
        context.saveGState()
        context.setFillColor(
            NSColor.black.withAlphaComponent(0.72).cgColor
        )
        context.addPath(
            CGPath(
                roundedRect: rect,
                cornerWidth: min(16, size * 0.45),
                cornerHeight: min(16, size * 0.45),
                transform: nil
            )
        )
        context.fillPath()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributed = NSAttributedString(
            string: caption,
            attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: .semibold),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph
            ]
        )
        let framesetter = CTFramesetterCreateWithAttributedString(
            attributed as CFAttributedString
        )
        let textPath = CGPath(
            rect: rect.insetBy(dx: 18, dy: 9),
            transform: nil
        )
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(),
            textPath,
            nil
        )
        CTFrameDraw(frame, context)
        context.restoreGState()
    }

    private func exportGIF(
        prepared: PreparedComposition,
        duration: TimeInterval,
        destinationURL: URL,
        frameRate: Int,
        quality: ExportQuality,
        progress: @escaping @MainActor @Sendable (Double) -> Void
    ) async throws {
        try? FileManager.default.removeItem(at: destinationURL)
        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            UTType.gif.identifier as CFString,
            0,
            nil
        ) else {
            throw VideoExportError.cannotCreateExportSession
        }

        CGImageDestinationSetProperties(
            destination,
            [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFLoopCount: 0
                ]
            ] as CFDictionary
        )

        let generator = AVAssetImageGenerator(asset: prepared.composition)
        generator.videoComposition = prepared.videoComposition
        generator.appliesPreferredTrackTransform = false
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let safeFrameRate = max(5, min(20, frameRate))
        let frameCount = max(1, Int(ceil(duration * Double(safeFrameRate))))
        let frameProperties = [
            kCGImageDestinationLossyCompressionQuality:
                quality.imageCompressionQuality,
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: 1.0 / Double(safeFrameRate)
            ]
        ] as CFDictionary
        let imageContext = CIContext(options: [.cacheIntermediates: false])

        do {
            for index in 0..<frameCount {
                try Task.checkCancellation()
                let time = CMTime(
                    seconds: min(
                        duration,
                        Double(index) / Double(safeFrameRate)
                    ),
                    preferredTimescale: 600
                )
                let result = try await generator.image(at: time)
                let image = posterizedGIFImage(
                    result.image,
                    levels: quality.gifPosterizeLevels,
                    context: imageContext
                )
                CGImageDestinationAddImage(
                    destination,
                    image,
                    frameProperties
                )
                await progress(Double(index + 1) / Double(frameCount))
            }
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: destinationURL)
            throw VideoExportError.exportFailed
        }
    }

    private func posterizedGIFImage(
        _ image: CGImage,
        levels: Double?,
        context: CIContext
    ) -> CGImage {
        guard let levels,
              let filter = CIFilter(
                name: "CIColorPosterize",
                parameters: [
                    kCIInputImageKey: CIImage(cgImage: image),
                    "inputLevels": levels
                ]
              ),
              let output = filter.outputImage else {
            return image
        }
        return context.createCGImage(output, from: output.extent) ?? image
    }

    private func applyCanvasAndCursor(
        _ style: CanvasRenderStyle,
        project: TimelineProject,
        to videoComposition: AVMutableVideoComposition,
        renderSize: CGSize,
        cropGeometry: CanvasCropGeometry
    ) {
        let processedCursorSamples = project.processedCursorSamples(
            removeShakes: style.removeCursorShakes,
            shakeThreshold: style.cursorShakeThreshold,
            optimizeRapidChanges: style.optimizeRapidCursorChanges
        )
        let timelineCursorSamples = processedCursorSamples.compactMap { sample -> (
            time: TimeInterval,
            sample: CursorSample
        )? in
            guard let time = project.timelineTime(forSourceTime: sample.time) else {
                return nil
            }
            return (time, sample)
        }
        .sorted { $0.time < $1.time }

        let dipJunctions = project.transitionJunctions().filter {
            $0.transition?.style == .fade || $0.transition?.style == .flash
        }
        let needsCanvas = style.padding > 0 || style.cornerRadius > 0
        guard needsCanvas
            || !timelineCursorSamples.isEmpty
            || (style.clickEffect != .none && !project.clicks.isEmpty)
            || (style.showShortcuts && !project.shortcuts.isEmpty)
            || (style.showCaptions && !project.captions.isEmpty)
            || !project.redactions.isEmpty
            || !project.annotations.isEmpty
            || !dipJunctions.isEmpty
            || style.motionBlur.enabled else {
            return
        }

        let bounds = CGRect(origin: .zero, size: renderSize)
        let padding = min(
            style.padding,
            min(renderSize.width, renderSize.height) * 0.32
        )

        let parentLayer = CALayer()
        parentLayer.frame = bounds
        parentLayer.isGeometryFlipped = true

        let backgroundLayer: CALayer
        switch style.backgroundMode {
        case .wallpaper:
            let gradient = CAGradientLayer()
            gradient.colors = style.wallpaperPreset.colors.map {
                NSColor(
                    calibratedHue: $0.hue,
                    saturation: $0.saturation,
                    brightness: $0.brightness,
                    alpha: 1
                ).cgColor
            }
            gradient.locations = [0, 0.52, 1]
            gradient.startPoint = style.wallpaperPreset.startPoint
            gradient.endPoint = style.wallpaperPreset.endPoint
            backgroundLayer = gradient
        case .gradient:
            let gradient = CAGradientLayer()
            gradient.colors = [
                NSColor(
                    calibratedHue: style.backgroundHue,
                    saturation: 0.72,
                    brightness: 0.42,
                    alpha: 1
                ).cgColor,
                NSColor(
                    calibratedHue: (style.backgroundHue + 0.1)
                        .truncatingRemainder(dividingBy: 1),
                    saturation: 0.78,
                    brightness: 0.16,
                    alpha: 1
                ).cgColor
            ]
            gradient.startPoint = CGPoint(x: 0, y: 0)
            gradient.endPoint = CGPoint(x: 1, y: 1)
            backgroundLayer = gradient
        case .solid:
            let solid = CALayer()
            solid.backgroundColor = NSColor(
                calibratedHue: style.backgroundHue,
                saturation: 0.68,
                brightness: 0.42,
                alpha: 1
            ).cgColor
            backgroundLayer = solid
        case .image:
            let imageLayer = CALayer()
            if let url = style.backgroundImageURL,
               let image = NSImage(contentsOf: url),
               let cgImage = image.cgImage(
                forProposedRect: nil,
                context: nil,
                hints: nil
               ) {
                imageLayer.contents = blurredImage(
                    cgImage,
                    radius: style.backgroundBlur
                )
                imageLayer.contentsGravity = .resizeAspectFill
            } else {
                imageLayer.backgroundColor = NSColor(
                    calibratedHue: style.backgroundHue,
                    saturation: 0.68,
                    brightness: 0.36,
                    alpha: 1
                ).cgColor
            }
            backgroundLayer = imageLayer
        }
        backgroundLayer.frame = bounds

        let shadowLayer = CALayer()
        shadowLayer.frame = bounds.insetBy(dx: padding, dy: padding)
        shadowLayer.backgroundColor = NSColor.black.cgColor
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOpacity = Float(style.shadowOpacity.clamped(to: 0...1))
        shadowLayer.shadowRadius = max(12, padding * 0.45)
        shadowLayer.shadowOffset = CGSize(width: 0, height: max(6, padding * 0.22))
        shadowLayer.cornerRadius = style.cornerRadius

        let videoLayer = CALayer()
        videoLayer.frame = bounds.insetBy(dx: padding, dy: padding)
        videoLayer.cornerRadius = style.cornerRadius
        videoLayer.masksToBounds = true
        addScreenMotionBlur(
            style.motionBlur,
            project: project,
            zoomMotion: style.zoomMotion,
            renderSize: renderSize,
            to: videoLayer
        )

        if needsCanvas {
            parentLayer.addSublayer(backgroundLayer)
            parentLayer.addSublayer(shadowLayer)
        }
        parentLayer.addSublayer(videoLayer)

        if (style.showCursor && !timelineCursorSamples.isEmpty)
            || (style.clickEffect != .none && !project.clicks.isEmpty) {
            let cursorClipLayer = CALayer()
            cursorClipLayer.frame = videoLayer.frame
            cursorClipLayer.masksToBounds = true
            parentLayer.addSublayer(cursorClipLayer)
            addCursorTrack(
                timelineCursorSamples,
                project: project,
                style: style,
                to: cursorClipLayer,
                videoFrame: cursorClipLayer.bounds,
                cropGeometry: cropGeometry
            )
        }

        for junction in dipJunctions {
            addTransitionDip(
                junction: junction,
                project: project,
                to: parentLayer,
                videoFrame: videoLayer.frame,
                cornerRadius: style.cornerRadius
            )
        }

        addPrivacyRedactions(
            project.redactions,
            to: parentLayer,
            videoFrame: videoLayer.frame
        )
        addAnnotations(
            project.annotations,
            project: project,
            to: parentLayer,
            videoFrame: videoLayer.frame,
            cropGeometry: cropGeometry
        )

        if style.showCaptions, !project.captions.isEmpty {
            addCaptions(
                project: project,
                style: style,
                to: parentLayer,
                renderSize: renderSize,
                videoFrame: videoLayer.frame
            )
        }
        if style.showShortcuts, !project.shortcuts.isEmpty {
            addShortcutLabels(
                project: project,
                to: parentLayer,
                videoFrame: videoLayer.frame
            )
        }

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
    }

    private func addTransitionDip(
        junction: TransitionJunction,
        project: TimelineProject,
        to parentLayer: CALayer,
        videoFrame: CGRect,
        cornerRadius: CGFloat
    ) {
        guard let transition = junction.transition else { return }
        let totalDuration = project.duration
        let half = transition.duration / 2
        let start = max(0, junction.time - half)
        let end = min(totalDuration, junction.time + half)
        guard end - start > 0.001 else { return }

        let junctions = project.transitionJunctions()
        let steps = max(2, Int(ceil((end - start) * 60)))
        var values: [Double] = []
        var keyTimes: [NSNumber] = []
        for step in 0...steps {
            let progress = Double(step) / Double(steps)
            let time = start + (end - start) * progress
            values.append(
                ClipTransitionResolver.frame(
                    junctions: junctions,
                    at: time
                ).dipOpacity
            )
            keyTimes.append(NSNumber(value: progress))
        }

        let dipLayer = CALayer()
        dipLayer.frame = videoFrame
        dipLayer.cornerRadius = cornerRadius
        dipLayer.masksToBounds = true
        dipLayer.backgroundColor = (
            transition.style.dipsToWhite ? NSColor.white : NSColor.black
        ).cgColor
        dipLayer.opacity = 0

        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = values
        animation.keyTimes = keyTimes
        animation.duration = end - start
        animation.beginTime = AVCoreAnimationBeginTimeAtZero + start
        animation.isRemovedOnCompletion = false
        animation.fillMode = .forwards
        dipLayer.add(animation, forKey: "transitionDip")

        parentLayer.addSublayer(dipLayer)
    }

    private func addPrivacyRedactions(
        _ redactions: [PrivacyRedaction],
        to parentLayer: CALayer,
        videoFrame: CGRect
    ) {
        for redaction in redactions {
            if redaction.resolvedPresentation == .redaction,
               redaction.resolvedEffect == .blur {
                continue
            }
            let width = videoFrame.width * redaction.normalizedWidth
            let height = videoFrame.height * redaction.normalizedHeight
            let regionFrame = CGRect(
                x: videoFrame.minX
                    + videoFrame.width * redaction.normalizedX
                    - width / 2,
                y: videoFrame.minY
                    + videoFrame.height * redaction.normalizedY
                    - height / 2,
                width: width,
                height: height
            )
            let layer: CALayer
            if redaction.resolvedPresentation == .spotlight {
                let spotlight = CAShapeLayer()
                spotlight.frame = parentLayer.bounds
                let path = CGMutablePath()
                path.addRect(videoFrame)
                path.addPath(
                    CGPath(
                        roundedRect: regionFrame,
                        cornerWidth: 12,
                        cornerHeight: 12,
                        transform: nil
                    )
                )
                spotlight.path = path
                spotlight.fillRule = .evenOdd
                spotlight.fillColor = NSColor.black.cgColor
                let border = CAShapeLayer()
                border.path = CGPath(
                    roundedRect: regionFrame,
                    cornerWidth: 12,
                    cornerHeight: 12,
                    transform: nil
                )
                border.fillColor = nil
                border.strokeColor = NSColor(
                    calibratedHue: redaction.resolvedHighlightHue,
                    saturation: 0.9,
                    brightness: 1,
                    alpha: 0.92
                ).cgColor
                border.lineWidth = 3
                spotlight.addSublayer(border)
                layer = spotlight
            } else {
                let cover = CALayer()
                cover.frame = regionFrame
                cover.backgroundColor = NSColor.black.cgColor
                cover.cornerRadius = 8
                layer = cover
            }
            layer.opacity = 0

            let visibility = CAKeyframeAnimation(keyPath: "opacity")
            visibility.values = [
                0,
                redaction.opacity,
                redaction.opacity,
                0
            ]
            visibility.keyTimes = [0, 0.01, 0.99, 1]
            visibility.beginTime = AVCoreAnimationBeginTimeAtZero
                + redaction.start
            visibility.duration = redaction.duration
            visibility.isRemovedOnCompletion = false
            visibility.fillMode = .backwards
            layer.add(visibility, forKey: "privacyVisibility")
            parentLayer.addSublayer(layer)
        }
    }

    private func addAnnotations(
        _ annotations: [Annotation],
        project: TimelineProject,
        to parentLayer: CALayer,
        videoFrame: CGRect,
        cropGeometry: CanvasCropGeometry
    ) {
        for annotation in annotations {
            guard let timelineStart = project.timelineTime(
                forSourceTime: annotation.start
            ) else {
                continue
            }
            let path = annotationCGPath(for: annotation) { x, y in
                point(x: x, y: y, in: videoFrame, cropGeometry: cropGeometry)
            }
            let layer = CAShapeLayer()
            layer.frame = parentLayer.bounds
            layer.path = path
            layer.fillColor = nil
            layer.strokeColor = annotation.color.nsColor.cgColor
            layer.lineWidth = annotation.lineWidth
            layer.lineCap = .round
            layer.lineJoin = .round
            layer.shadowColor = NSColor.black.cgColor
            layer.shadowOpacity = 0.7
            layer.shadowRadius = 2
            layer.opacity = 0

            if annotation.drawDuration > 0 {
                let draw = CAKeyframeAnimation(keyPath: "path")
                draw.values = annotationDrawSamplePaths(
                    for: annotation,
                    videoFrame: videoFrame,
                    cropGeometry: cropGeometry
                )
                draw.calculationMode = .discrete
                draw.beginTime = AVCoreAnimationBeginTimeAtZero
                    + timelineStart
                draw.duration = annotation.drawDuration
                draw.isRemovedOnCompletion = false
                draw.fillMode = .both
                layer.add(draw, forKey: "annotationDrawProgress")
            }

            let visibility = CAKeyframeAnimation(keyPath: "opacity")
            visibility.values = [0, 1, 1, 0]
            visibility.keyTimes = [0, 0.01, 0.99, 1]
            visibility.beginTime = AVCoreAnimationBeginTimeAtZero
                + timelineStart
            visibility.duration = annotation.drawDuration
                + annotation.duration
            visibility.isRemovedOnCompletion = false
            visibility.fillMode = .backwards
            layer.add(visibility, forKey: "annotationVisibility")
            parentLayer.addSublayer(layer)
        }
    }

    /// Samples the shared progressive annotation geometry at display rate so
    /// the Core Animation export layer replays the drawing gesture the same
    /// way the preview and current-frame renderers do.
    private func annotationDrawSamplePaths(
        for annotation: Annotation,
        videoFrame: CGRect,
        cropGeometry: CanvasCropGeometry
    ) -> [Any] {
        let sampleCount = max(
            2,
            min(120, Int((annotation.drawDuration * 60).rounded()))
        )
        return (0...sampleCount).map { step in
            annotationCGPath(
                for: annotation,
                progress: Double(step) / Double(sampleCount)
            ) { x, y in
                point(x: x, y: y, in: videoFrame, cropGeometry: cropGeometry)
            }
        }
    }

    private func addShortcutLabels(
        project: TimelineProject,
        to parentLayer: CALayer,
        videoFrame: CGRect
    ) {
        for shortcut in project.shortcuts {
            guard let start = project.timelineTime(
                forSourceTime: shortcut.time
            ) else {
                continue
            }
            let height: CGFloat = 54
            let width = CGFloat(34 + shortcut.label.count * 22)
                .clamped(to: 92...videoFrame.width * 0.72)
            let pill = CALayer()
            pill.bounds = CGRect(
                x: 0,
                y: 0,
                width: width,
                height: height
            )
            pill.position = CGPoint(
                x: videoFrame.midX,
                y: videoFrame.minY
                    + height / 2
                    + max(22, videoFrame.height * 0.06)
            )
            pill.backgroundColor = NSColor.black
                .withAlphaComponent(0.76)
                .cgColor
            pill.borderColor = NSColor.white
                .withAlphaComponent(0.16)
                .cgColor
            pill.borderWidth = 1
            pill.cornerRadius = 12
            pill.opacity = 0

            let text = CATextLayer()
            text.frame = pill.bounds.insetBy(dx: 12, dy: 9)
            text.string = shortcut.label
            text.foregroundColor = NSColor.white.cgColor
            text.font = NSFont.systemFont(
                ofSize: 24,
                weight: .semibold
            )
            text.fontSize = 24
            text.alignmentMode = .center
            text.contentsScale = 2
            pill.addSublayer(text)

            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [0, 1, 1, 0]
            opacity.keyTimes = [0, 0.08, 0.86, 1]
            opacity.beginTime = AVCoreAnimationBeginTimeAtZero + start
            opacity.duration = ShortcutEvent.displayDuration
            opacity.isRemovedOnCompletion = false
            opacity.fillMode = .backwards
            pill.add(opacity, forKey: "shortcutVisibility")
            parentLayer.addSublayer(pill)
        }
    }

    private func blurredImage(
        _ image: CGImage,
        radius: CGFloat
    ) -> CGImage {
        guard radius > 0.5,
              let filter = CIFilter(name: "CIGaussianBlur") else {
            return image
        }
        let input = CIImage(cgImage: image)
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(
            radius.clamped(to: 0...48),
            forKey: kCIInputRadiusKey
        )
        guard let output = filter.outputImage?.cropped(to: input.extent),
              let result = CIContext().createCGImage(
                output,
                from: input.extent
              ) else {
            return image
        }
        return result
    }

    private func addCaptions(
        project: TimelineProject,
        style: CanvasRenderStyle,
        to parentLayer: CALayer,
        renderSize: CGSize,
        videoFrame: CGRect
    ) {
        let maximumWidth = videoFrame.width * 0.76
        let fontSize = style.captionFontSize.clamped(to: 18...72)
        let height = fontSize * 2.6

        for cue in project.captions {
            guard let start = project.timelineTime(
                forSourceTime: cue.sourceStart
            ) else {
                continue
            }
            let sourceEnd = cue.sourceStart + cue.duration
            let end = project.timelineTime(forSourceTime: sourceEnd)
                ?? min(project.duration, start + cue.duration)
            let duration = max(0.2, end - start)

            let background = CALayer()
            background.bounds = CGRect(
                x: 0,
                y: 0,
                width: maximumWidth,
                height: height
            )
            background.position = CGPoint(
                x: renderSize.width / 2,
                y: videoFrame.maxY - max(26, videoFrame.height * 0.08)
            )
            background.backgroundColor = NSColor.black
                .withAlphaComponent(0.72)
                .cgColor
            background.cornerRadius = min(16, fontSize * 0.45)
            background.opacity = 0

            let text = CATextLayer()
            text.frame = background.bounds.insetBy(dx: 18, dy: 9)
            text.string = cue.text
            text.foregroundColor = NSColor.white.cgColor
            text.font = NSFont.systemFont(
                ofSize: fontSize,
                weight: .semibold
            )
            text.fontSize = fontSize
            text.alignmentMode = .center
            text.isWrapped = true
            text.contentsScale = 2
            background.addSublayer(text)

            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [0, 1, 1, 0]
            opacity.keyTimes = [0, 0.04, 0.94, 1]
            opacity.beginTime = AVCoreAnimationBeginTimeAtZero + start
            opacity.duration = duration
            opacity.isRemovedOnCompletion = false
            opacity.fillMode = .backwards
            background.add(opacity, forKey: "captionVisibility")
            parentLayer.addSublayer(background)
        }
    }

    private func addCursorTrack(
        _ samples: [(time: TimeInterval, sample: CursorSample)],
        project: TimelineProject,
        style: CanvasRenderStyle,
        to parentLayer: CALayer,
        videoFrame: CGRect,
        cropGeometry: CanvasCropGeometry
    ) {
        guard project.duration > 0 else {
            return
        }
        let scale = style.cursorSize.clamped(to: 0.6...2.5)
        if style.showCursor,
           !samples.isEmpty {
            let cursorImage = CursorArtwork.cgImage(
                for: style.cursorReplacement
            )
            let imageSize = CursorArtwork.size(
                for: style.cursorReplacement
            )
            let hotspot = CursorArtwork.hotspot(
                for: style.cursorReplacement
            )
            let cursorLayer = CALayer()
            cursorLayer.contents = cursorImage
            cursorLayer.contentsGravity = .resizeAspect
            cursorLayer.bounds = CGRect(
                origin: .zero,
                size: CGSize(
                    width: max(12, imageSize.width * scale),
                    height: max(18, imageSize.height * scale)
                )
            )
            // The macOS arrow hotspot is close to its upper-left corner.
            cursorLayer.anchorPoint = hotspot
            cursorLayer.shadowColor = NSColor.black.cgColor
            cursorLayer.shadowOpacity = 0.5
            cursorLayer.shadowRadius = 1.5
            cursorLayer.shadowOffset = CGSize(width: 0, height: 1)

            var animationSamples = samples
            let freezeStart = max(
                0,
                project.duration - style.cursorTailFreeze.clamped(
                    to: 0...project.duration
                )
            )
            if style.cursorTailFreeze > 0,
                let frozenSample = project.cursorSample(
                   atTimelineTime: freezeStart,
                   freezeBeforeEnd: style.cursorTailFreeze,
                   removeShakes: style.removeCursorShakes,
                   shakeThreshold: style.cursorShakeThreshold,
                   optimizeRapidChanges: style.optimizeRapidCursorChanges,
                   smoothMovement: style.smoothCursorMovement
               ) {
                animationSamples.removeAll { $0.time >= freezeStart }
                animationSamples.append((freezeStart, frozenSample))
            }
            if style.cursorLoopToStart {
                let returnDuration = TimelineProject.cursorReturnDuration(
                    for: project.duration
                )
                let returnStart = max(
                    0,
                    project.duration - returnDuration
                )
                animationSamples.removeAll { $0.time >= returnStart }
                for step in 0...8 {
                    let time = returnStart
                        + returnDuration * Double(step) / 8
                    if let sample = project.cursorSample(
                        atTimelineTime: time,
                        freezeBeforeEnd: style.cursorTailFreeze,
                        loopToStart: true,
                        removeShakes: style.removeCursorShakes,
                        shakeThreshold: style.cursorShakeThreshold,
                        optimizeRapidChanges: style.optimizeRapidCursorChanges,
                        smoothMovement: style.smoothCursorMovement
                    ) {
                        animationSamples.append((time, sample))
                    }
                }
            }
            if let first = animationSamples.first, first.time > 0 {
                animationSamples.insert((0, first.sample), at: 0)
            }
            if let last = animationSamples.last, last.time < project.duration {
                animationSamples.append((project.duration, last.sample))
            }

            let cursorPoints = animationSamples.map {
                cursorPoint(
                    for: $0.sample,
                    at: $0.time,
                    project: project,
                    in: videoFrame,
                    cropGeometry: cropGeometry,
                    style: style
                )
            }
            cursorLayer.position = cursorPoints.last ?? .zero

            let positionAnimation = CAKeyframeAnimation(keyPath: "position")
            positionAnimation.values = cursorPoints
            positionAnimation.keyTimes = animationSamples.map {
                NSNumber(value: ($0.time / project.duration).clamped(to: 0...1))
            }
            positionAnimation.duration = project.duration
            positionAnimation.beginTime = AVCoreAnimationBeginTimeAtZero
            positionAnimation.calculationMode = style.smoothCursorMovement
                ? .linear
                : .discrete
            positionAnimation.isRemovedOnCompletion = false
            positionAnimation.fillMode = .both
            cursorLayer.add(positionAnimation, forKey: "cursorPosition")
            addCursorMotionBlur(
                style.motionBlur,
                points: cursorPoints,
                times: animationSamples.map(\.time),
                duration: project.duration,
                renderSize: videoFrame.size,
                to: cursorLayer
            )

            if style.hideCursorWhenIdle {
                var previous = animationSamples.first
                var lastMovementTime = animationSamples.first?.time ?? 0
                var opacityValues: [NSNumber] = []
                for sample in animationSamples {
                    if let previous {
                        let distance = hypot(
                            sample.sample.normalizedX - previous.sample.normalizedX,
                            sample.sample.normalizedY - previous.sample.normalizedY
                        )
                        if distance > 0.0015 {
                            lastMovementTime = sample.time
                        }
                    }
                    let visible = sample.time - lastMovementTime
                        <= style.cursorIdleTimeout
                    opacityValues.append(NSNumber(value: visible ? 1 : 0))
                    previous = sample
                }
                let opacityAnimation = CAKeyframeAnimation(keyPath: "opacity")
                opacityAnimation.values = opacityValues
                opacityAnimation.keyTimes = positionAnimation.keyTimes
                opacityAnimation.duration = project.duration
                opacityAnimation.beginTime = AVCoreAnimationBeginTimeAtZero
                opacityAnimation.calculationMode = .discrete
                opacityAnimation.isRemovedOnCompletion = false
                opacityAnimation.fillMode = .both
                cursorLayer.add(opacityAnimation, forKey: "cursorVisibility")
            }
            parentLayer.addSublayer(cursorLayer)
        }

        guard style.clickEffect != .none else { return }
        for click in project.clicks {
            guard let timelineTime = project.timelineTime(forSourceTime: click.time),
                  timelineTime <= project.duration else {
                continue
            }
            let ripple = CAShapeLayer()
            let diameter = 34 * scale
            ripple.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
            ripple.position = cursorPoint(
                for: CursorSample(
                    time: click.time,
                    normalizedX: click.normalizedX,
                    normalizedY: click.normalizedY
                ),
                at: timelineTime,
                project: project,
                in: videoFrame,
                cropGeometry: cropGeometry,
                style: style
            )
            ripple.path = CGPath(
                ellipseIn: ripple.bounds.insetBy(dx: 2, dy: 2),
                transform: nil
            )
            ripple.strokeColor = NSColor.white.withAlphaComponent(0.9).cgColor
            ripple.opacity = 0

            let opacityAnimation = CAKeyframeAnimation(keyPath: "opacity")
            let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
            var animations: [CAAnimation] = [scaleAnimation, opacityAnimation]
            let duration: TimeInterval
            switch style.clickEffect {
            case .none:
                continue
            case .circle:
                ripple.fillColor = NSColor.white.withAlphaComponent(0.52).cgColor
                ripple.lineWidth = 2
                scaleAnimation.fromValue = 1
                scaleAnimation.toValue = 0.58
                opacityAnimation.values = [0, 0.78, 0]
                opacityAnimation.keyTimes = [0, 0.08, 1]
                duration = 0.42
            case .ripple:
                ripple.fillColor = NSColor.clear.cgColor
                ripple.lineWidth = 3
                scaleAnimation.fromValue = 0.35
                scaleAnimation.toValue = 1.8
                opacityAnimation.values = [0, 0.9, 0]
                opacityAnimation.keyTimes = [0, 0.12, 1]
                duration = 0.55
            case .rotation:
                ripple.fillColor = NSColor.clear.cgColor
                ripple.lineWidth = 3
                ripple.lineDashPattern = [8, 5]
                scaleAnimation.fromValue = 0.72
                scaleAnimation.toValue = 1.3
                opacityAnimation.values = [0, 0.95, 0]
                opacityAnimation.keyTimes = [0, 0.08, 1]
                let rotation = CABasicAnimation(keyPath: "transform.rotation")
                rotation.fromValue = 0
                rotation.toValue = CGFloat.pi * 1.65
                animations.append(rotation)
                duration = 0.62
            }

            let group = CAAnimationGroup()
            group.animations = animations
            group.beginTime = AVCoreAnimationBeginTimeAtZero + timelineTime
            group.duration = duration
            group.isRemovedOnCompletion = false
            group.fillMode = .backwards
            ripple.add(group, forKey: "clickRipple")
            parentLayer.addSublayer(ripple)
        }
    }

    private func addScreenMotionBlur(
        _ style: MotionBlurStyle,
        project: TimelineProject,
        zoomMotion: ZoomMotionStyle,
        renderSize: CGSize,
        to layer: CALayer
    ) {
        guard style.enabled, style.strength > 0,
              project.duration > 0 else {
            return
        }
        let intervalCount = min(
            7_200,
            max(2, Int(ceil(project.duration * 15)))
        )
        let times = (0...intervalCount).map {
            project.duration * Double($0) / Double(intervalCount)
        }
        let values = times.map {
            MotionBlurResolver.screenRadius(
                at: $0,
                zooms: project.zooms,
                totalDuration: project.duration,
                zoomMotion: zoomMotion,
                style: style,
                renderSize: renderSize
            )
        }
        addMotionBlurFilter(
            to: layer,
            name: "screenMotionBlur",
            values: values,
            keyTimes: times.map {
                NSNumber(value: $0 / project.duration)
            },
            duration: project.duration
        )
    }

    private func addCursorMotionBlur(
        _ style: MotionBlurStyle,
        points: [CGPoint],
        times: [TimeInterval],
        duration: TimeInterval,
        renderSize: CGSize,
        to layer: CALayer
    ) {
        guard style.enabled, style.strength > 0,
              style.cursorAmount > 0,
              points.count == times.count,
              points.count > 1,
              duration > 0 else {
            return
        }
        let referenceSize = max(
            1,
            min(renderSize.width, renderSize.height)
        )
        var values: [CGFloat] = [0]
        for index in 1..<points.count {
            let elapsed = max(1 / 240, times[index] - times[index - 1])
            let normalizedVelocity = hypot(
                points[index].x - points[index - 1].x,
                points[index].y - points[index - 1].y
            ) / referenceSize / elapsed
            values.append(
                (
                    style.strength
                        * style.cursorAmount
                        * referenceSize
                        * 0.012
                        * min(1.5, normalizedVelocity / 2)
                ).clamped(to: 0...24)
            )
        }
        addMotionBlurFilter(
            to: layer,
            name: "cursorMotionBlur",
            values: values,
            keyTimes: times.map {
                NSNumber(value: ($0 / duration).clamped(to: 0...1))
            },
            duration: duration
        )
    }

    private func addMotionBlurFilter(
        to layer: CALayer,
        name: String,
        values: [CGFloat],
        keyTimes: [NSNumber],
        duration: TimeInterval
    ) {
        guard values.count == keyTimes.count,
              !values.isEmpty,
              let filter = CIFilter(name: "CIGaussianBlur") else {
            return
        }
        filter.name = name
        filter.setDefaults()
        filter.setValue(0, forKey: kCIInputRadiusKey)
        layer.filters = [filter]

        let animation = CAKeyframeAnimation(
            keyPath: "filters.\(name).inputRadius"
        )
        animation.values = values.map { NSNumber(value: Double($0)) }
        animation.keyTimes = keyTimes
        animation.duration = duration
        animation.beginTime = AVCoreAnimationBeginTimeAtZero
        animation.calculationMode = .linear
        animation.isRemovedOnCompletion = false
        animation.fillMode = .both
        layer.add(animation, forKey: "\(name)Animation")
    }

    private func point(
        x: CGFloat,
        y: CGFloat,
        in videoFrame: CGRect,
        cropGeometry: CanvasCropGeometry
    ) -> CGPoint {
        let normalized = cropGeometry.normalizedOutputPoint(x: x, y: y)
        return CGPoint(
            x: videoFrame.minX + videoFrame.width * normalized.x,
            y: videoFrame.minY + videoFrame.height * normalized.y
        )
    }

    private func cursorPoint(
        for sample: CursorSample,
        at time: TimeInterval,
        project: TimelineProject,
        in videoFrame: CGRect,
        cropGeometry: CanvasCropGeometry,
        style: CanvasRenderStyle
    ) -> CGPoint {
        let rawPoint = point(
            x: sample.normalizedX,
            y: sample.normalizedY,
            in: videoFrame,
            cropGeometry: cropGeometry
        )
        guard let zoomState = effectiveZoom(
            at: time,
            zooms: project.zooms,
            totalDuration: project.duration,
            motion: style.zoomMotion
        ) else {
            return rawPoint
        }

        let zoomFocus = resolvedZoomFocus(
            zoomState,
            at: time,
            project: project,
            style: style
        )
        let focus = point(
            x: zoomFocus.x,
            y: zoomFocus.y,
            in: videoFrame,
            cropGeometry: cropGeometry
        )
        return CGPoint(
            x: focus.x + (rawPoint.x - focus.x) * zoomState.scale,
            y: focus.y + (rawPoint.y - focus.y) * zoomState.scale
        )
    }

    private func effectiveZoom(
        at time: TimeInterval,
        zooms: [ZoomEvent],
        totalDuration: TimeInterval,
        motion: ZoomMotionStyle
    ) -> ResolvedZoomMotion? {
        ZoomMotionResolver.state(
            at: time,
            zooms: zooms,
            totalDuration: totalDuration,
            motion: motion
        )
    }

    private func resolvedZoomFocus(
        _ zoomState: ResolvedZoomMotion,
        at time: TimeInterval,
        project: TimelineProject,
        style: CanvasRenderStyle,
        processedCursorSamples: [CursorSample]? = nil
    ) -> CGPoint {
        ZoomFocusResolver.focus(
            at: time,
            zoomState: zoomState,
            project: project,
            cursorTailFreeze: style.cursorTailFreeze,
            cursorLoopToStart: style.cursorLoopToStart,
            removeCursorShakes: style.removeCursorShakes,
            cursorShakeThreshold: style.cursorShakeThreshold,
            optimizeRapidCursorChanges: style.optimizeRapidCursorChanges,
            smoothCursorMovement: true,
            processedCursorSamples: processedCursorSamples
        )
    }

    private func applyZooms(
        _ zooms: [ZoomEvent],
        to instruction: AVMutableVideoCompositionLayerInstruction,
        baseTransform: CGAffineTransform,
        cropGeometry: CanvasCropGeometry,
        totalDuration: TimeInterval,
        project: TimelineProject,
        style: CanvasRenderStyle
    ) {
        let motion = style.zoomMotion
        let processedCursorSamples = project.processedCursorSamples(
            removeShakes: style.removeCursorShakes,
            shakeThreshold: style.cursorShakeThreshold,
            optimizeRapidChanges: style.optimizeRapidCursorChanges
        )
        // 30 fps 光标轨迹需要至少同密度的关键帧，15/s 会让跟随相机的
        // 折线速度转折点在导出里混叠成顿挫。
        let samplesPerSecond = max(
            30,
            Double(motion.exportSampleCount)
                / max(0.08, motion.transitionDuration)
        )
        var boundaries = zooms.flatMap { [$0.start, $0.end] }

        var activeRanges = ZoomMotionResolver.activeRanges(
            zooms: zooms,
            totalDuration: totalDuration
        )
        let zoomTransitionJunctions = project.transitionJunctions().filter {
            $0.transition?.style == .zoom
        }
        if !zoomTransitionJunctions.isEmpty {
            // Zoom-punch transition windows are sampled into the same dense
            // transform ramps; ranges are merged so ramps never overlap.
            activeRanges += zoomTransitionJunctions.map { junction in
                let half = (junction.transition?.duration ?? 0.4) / 2
                let lower = max(0, junction.time - half)
                let upper = min(totalDuration, junction.time + half)
                return lower...upper
            }
            boundaries += zoomTransitionJunctions.map(\.time)
            activeRanges = mergedRanges(activeRanges)
        }

        for activeRange in activeRanges {
            let duration = activeRange.upperBound - activeRange.lowerBound
            guard duration > 0 else { continue }
            let steps = max(
                1,
                min(9_000, Int(ceil(duration * samplesPerSecond)))
            )
            var sampleTimes = (0...steps).map {
                activeRange.lowerBound
                    + duration * Double($0) / Double(steps)
            }
            sampleTimes.append(
                contentsOf: boundaries.filter {
                    $0 > activeRange.lowerBound
                        && $0 < activeRange.upperBound
                }
            )
            sampleTimes.sort()
            sampleTimes = sampleTimes.reduce(into: []) { result, time in
                if let last = result.last, abs(last - time) < 0.000_001 {
                    return
                }
                result.append(time)
            }

            for (segmentStart, segmentEnd) in zip(
                sampleTimes,
                sampleTimes.dropFirst()
            ) where segmentEnd > segmentStart {
                let startState = ZoomMotionResolver.state(
                    at: segmentStart,
                    zooms: zooms,
                    totalDuration: totalDuration,
                    motion: motion
                )
                let endState = ZoomMotionResolver.state(
                    at: segmentEnd,
                    zooms: zooms,
                    totalDuration: totalDuration,
                    motion: motion
                )
                instruction.setTransformRamp(
                    fromStart: transform(
                        for: startState,
                        time: segmentStart,
                        baseTransform: baseTransform,
                        cropGeometry: cropGeometry,
                        project: project,
                        style: style,
                        processedCursorSamples: processedCursorSamples
                    ),
                    toEnd: transform(
                        for: endState,
                        time: segmentEnd,
                        baseTransform: baseTransform,
                        cropGeometry: cropGeometry,
                        project: project,
                        style: style,
                        processedCursorSamples: processedCursorSamples
                    ),
                    timeRange: CMTimeRange(
                        start: CMTime(
                            seconds: segmentStart,
                            preferredTimescale: 600
                        ),
                        duration: CMTime(
                            seconds: segmentEnd - segmentStart,
                            preferredTimescale: 600
                        )
                    )
                )
            }
        }
    }

    private func mergedRanges(
        _ ranges: [ClosedRange<TimeInterval>]
    ) -> [ClosedRange<TimeInterval>] {
        var result: [ClosedRange<TimeInterval>] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = result.last,
               range.lowerBound <= last.upperBound + 0.000_001 {
                result[result.count - 1] =
                    last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                result.append(range)
            }
        }
        return result
    }

    private func transform(
        for resolved: ResolvedZoomMotion?,
        time: TimeInterval,
        baseTransform: CGAffineTransform,
        cropGeometry: CanvasCropGeometry,
        project: TimelineProject,
        style: CanvasRenderStyle,
        processedCursorSamples: [CursorSample]
    ) -> CGAffineTransform {
        var result = baseTransform
        if let resolved {
            let resolvedFocus = resolvedZoomFocus(
                resolved,
                at: time,
                project: project,
                style: style,
                processedCursorSamples: processedCursorSamples
            )
            let normalizedFocus = cropGeometry.clampedNormalizedOutputPoint(
                x: resolvedFocus.x,
                y: resolvedFocus.y
            )
            let focus = CGPoint(
                x: cropGeometry.renderSize.width * normalizedFocus.x,
                y: cropGeometry.renderSize.height * normalizedFocus.y
            )
            let scale = resolved.scale
            let focusZoom = CGAffineTransform(translationX: focus.x, y: focus.y)
                .scaledBy(x: scale, y: scale)
                .translatedBy(x: -focus.x, y: -focus.y)
            result = result.concatenating(focusZoom)
        }
        let transitionScale = ClipTransitionResolver.frame(
            junctions: project.transitionJunctions(),
            at: time
        ).contentScale
        if abs(transitionScale - 1) > 0.000_1 {
            let center = CGPoint(
                x: cropGeometry.renderSize.width / 2,
                y: cropGeometry.renderSize.height / 2
            )
            let punch = CGAffineTransform(
                translationX: center.x,
                y: center.y
            )
                .scaledBy(x: transitionScale, y: transitionScale)
                .translatedBy(x: -center.x, y: -center.y)
            result = result.concatenating(punch)
        }
        return result
    }
}

private final class SendableExportSession: @unchecked Sendable {
    let value: AVAssetExportSession

    init(_ value: AVAssetExportSession) {
        self.value = value
    }
}
