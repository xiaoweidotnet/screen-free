import AVFoundation
import XCTest
@testable import ScreenFree

final class ExportOptionsTests: XCTestCase {
    func testResolutionFrameRateAndOriginalDeliveryOptions() async throws {
        XCTAssertEqual(
            ExportResolution.source.presetName,
            AVAssetExportPresetHighestQuality
        )
        XCTAssertEqual(
            ExportResolution.p720.presetName,
            AVAssetExportPreset1280x720
        )
        XCTAssertEqual(
            ExportResolution.p1080.presetName,
            AVAssetExportPreset1920x1080
        )
        XCTAssertEqual(
            ExportResolution.p4K.presetName,
            AVAssetExportPreset3840x2160
        )
        XCTAssertEqual(
            ExportResolution.custom.presetName,
            AVAssetExportPresetHighestQuality
        )
        XCTAssertEqual(
            ExportDimensions(width: 641, height: 359),
            ExportDimensions(width: 640, height: 358)
        )
        XCTAssertEqual(
            ExportDimensions(width: 100, height: 9_000),
            ExportDimensions(width: 320, height: 7_680)
        )
        let customCrop = CanvasCropGeometry(
            sourceSize: CGSize(width: 1_920, height: 1_080),
            targetSize: CGSize(width: 640, height: 640)
        )
        XCTAssertEqual(customCrop.renderSize.width, 640)
        XCTAssertEqual(customCrop.renderSize.height, 640)
        XCTAssertFalse(
            customCrop.containsSourcePoint(x: 0.05, y: 0.5)
        )
        XCTAssertTrue(
            customCrop.containsSourcePoint(x: 0.5, y: 0.5)
        )
        XCTAssertEqual(
            ExportFrameRateOptions.supported,
            [24, 25, 30, 50, 60]
        )
        XCTAssertEqual(
            ExportFrameRateOptions.supported(for: .gif),
            [10, 15, 20]
        )
        XCTAssertEqual(
            ExportFrameRateOptions.normalized(60, for: .gif),
            20
        )
        XCTAssertEqual(
            ExportDestination.allCases,
            [.file, .clipboard, .shareableLink]
        )
        XCTAssertEqual(
            AfterRecordingAction.allCases,
            [.edit, .clipboard, .file]
        )

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.mp4")
        let destination = directory.appendingPathComponent("delivery.mp4")
        try Data("screenfree-recording".utf8).write(to: source)
        try Data("old".utf8).write(to: destination)

        let delivery = OriginalRecordingDelivery()
        try delivery.copy(
            sourceURL: source,
            destinationURL: destination
        )
        XCTAssertEqual(
            try Data(contentsOf: destination),
            Data("screenfree-recording".utf8)
        )
        try delivery.copy(sourceURL: source, destinationURL: source)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))

        let multiTrackURL = directory.appendingPathComponent("tracks.mov")
        let extractedURL = directory.appendingPathComponent("microphone.m4a")
        try await makeTwoTrackAudioAsset(
            at: multiTrackURL,
            directory: directory
        )
        try Data("replace-me".utf8).write(to: extractedURL)
        try await OriginalMediaExporter().extractAudio(
            sourceURL: multiTrackURL,
            trackIndex: 1,
            destinationURL: extractedURL
        )
        let extractedAsset = AVURLAsset(url: extractedURL)
        let extractedTracks = try await extractedAsset.loadTracks(
            withMediaType: .audio
        )
        let extractedDuration = try await extractedAsset.load(.duration).seconds
        XCTAssertEqual(extractedTracks.count, 1)
        XCTAssertEqual(extractedDuration, 0.5, accuracy: 0.04)

        do {
            try await OriginalMediaExporter().extractAudio(
                sourceURL: multiTrackURL,
                trackIndex: 2,
                destinationURL: extractedURL
            )
            XCTFail("An unavailable role must not fall back to another track.")
        } catch {
            XCTAssertTrue(error is OriginalMediaExportError)
        }
    }

    func testResolutionDimensionsFollowCanvasAspectRatio() {
        let sourceSize = CGSize(width: 5_120, height: 1_440)
        let custom = ExportDimensions(width: 1_000, height: 800)

        XCTAssertEqual(
            ExportResolution.source.dimensions(
                sourceSize: sourceSize,
                canvasAspectRatio: .landscape16x9,
                customDimensions: custom
            ),
            ExportDimensions(width: 2_560, height: 1_440)
        )
        XCTAssertEqual(
            ExportResolution.p4K.dimensions(
                sourceSize: sourceSize,
                canvasAspectRatio: .landscape16x9,
                customDimensions: custom
            ),
            ExportDimensions(width: 3_840, height: 2_160)
        )
        XCTAssertEqual(
            ExportResolution.p1080.dimensions(
                sourceSize: sourceSize,
                canvasAspectRatio: .portrait9x16,
                customDimensions: custom
            ),
            ExportDimensions(width: 1_080, height: 1_920)
        )
        XCTAssertEqual(
            ExportResolution.p720.dimensions(
                sourceSize: sourceSize,
                canvasAspectRatio: .square,
                customDimensions: custom
            ),
            ExportDimensions(width: 720, height: 720)
        )
        XCTAssertEqual(
            ExportResolution.custom.dimensions(
                sourceSize: sourceSize,
                canvasAspectRatio: .square,
                customDimensions: custom
            ),
            custom
        )
    }

    func testExportEstimatesReflectCompressionResolutionAndFrameRate() throws {
        let dimensions = ExportDimensions(width: 1_920, height: 1_080)
        let qualities = ExportQuality.allCases.map {
            ExportEstimateCalculator.estimate(
                timelineDuration: 60,
                dimensions: dimensions,
                frameRate: 60,
                format: .mp4,
                quality: $0
            ).fileSizeBytes
        }
        XCTAssertEqual(qualities, qualities.sorted(by: >))

        let p720 = ExportEstimateCalculator.estimate(
            timelineDuration: 60,
            dimensions: ExportDimensions(width: 1_280, height: 720),
            frameRate: 30,
            format: .mp4,
            quality: .social
        )
        let p1080 = ExportEstimateCalculator.estimate(
            timelineDuration: 60,
            dimensions: dimensions,
            frameRate: 60,
            format: .mp4,
            quality: .social
        )
        XCTAssertGreaterThan(p1080.fileSizeBytes, p720.fileSizeBytes)
        XCTAssertGreaterThan(
            p1080.processingDuration,
            p720.processingDuration
        )

        XCTAssertNil(
            ExportEstimateCalculator.targetFileLength(
                timelineDuration: 60,
                dimensions: dimensions,
                frameRate: 60,
                format: .mp4,
                quality: .studio
            )
        )
        let socialLimit = ExportEstimateCalculator.targetFileLength(
            timelineDuration: 60,
            dimensions: dimensions,
            frameRate: 60,
            format: .mp4,
            quality: .social
        )
        let lowLimit = ExportEstimateCalculator.targetFileLength(
            timelineDuration: 60,
            dimensions: dimensions,
            frameRate: 60,
            format: .mp4,
            quality: .webLow
        )
        XCTAssertGreaterThan(try XCTUnwrap(socialLimit), try XCTUnwrap(lowLimit))
    }

    private func makeTwoTrackAudioAsset(
        at outputURL: URL,
        directory: URL
    ) async throws {
        let shortURL = directory.appendingPathComponent("short.caf")
        let longURL = directory.appendingPathComponent("long.caf")
        try makeSilentAudio(at: shortURL, duration: 0.25)
        try makeSilentAudio(at: longURL, duration: 0.5)

        let composition = AVMutableComposition()
        for url in [shortURL, longURL] {
            let asset = AVURLAsset(url: url)
            let sourceTracks = try await asset.loadTracks(
                withMediaType: .audio
            )
            let sourceTrack = try XCTUnwrap(
                sourceTracks.first
            )
            let sourceRange = try await sourceTrack.load(.timeRange)
            let destinationTrack = try XCTUnwrap(
                composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                )
            )
            try destinationTrack.insertTimeRange(
                sourceRange,
                of: sourceTrack,
                at: .zero
            )
        }

        let session = try XCTUnwrap(
            AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetPassthrough
            )
        )
        session.outputURL = outputURL
        session.outputFileType = .mov
        await session.export()
        XCTAssertEqual(session.status, .completed)
        let tracks = try await AVURLAsset(url: outputURL).loadTracks(
            withMediaType: .audio
        )
        XCTAssertEqual(tracks.count, 2)
    }

    private func makeSilentAudio(
        at url: URL,
        duration: TimeInterval
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
}
