import AppKit
import AVFoundation
import Foundation

enum ExportFrameRateOptions {
    static let supported = [24, 25, 30, 50, 60]
    static let gifSupported = [10, 15, 20]

    static func supported(for format: ExportFormat) -> [Int] {
        format == .gif ? gifSupported : supported
    }

    static func normalized(_ value: Int, for format: ExportFormat) -> Int {
        let options = supported(for: format)
        return options.min {
            abs($0 - value) < abs($1 - value)
        } ?? options[0]
    }
}

enum ExportDestination: String, CaseIterable, Identifiable {
    case file = "File"
    case clipboard = "Clipboard"
    case shareableLink = "Shareable Link"

    var id: Self { self }

    var symbolName: String {
        switch self {
        case .file:
            return "square.and.arrow.up"
        case .clipboard:
            return "doc.on.clipboard"
        case .shareableLink:
            return "link"
        }
    }
}

enum AfterRecordingAction: String, CaseIterable, Identifiable {
    case edit = "Open editor"
    case clipboard = "Copy recording"
    case file = "Save recording"

    var id: Self { self }
}

struct OriginalRecordingDelivery {
    func copy(sourceURL: URL, destinationURL: URL) throws {
        let fileManager = FileManager.default
        if sourceURL.standardizedFileURL
            == destinationURL.standardizedFileURL {
            return
        }
        let temporaryURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                ".screenfree-copy-\(UUID().uuidString)"
            )
        defer { try? fileManager.removeItem(at: temporaryURL) }
        try fileManager.copyItem(
            at: sourceURL,
            to: temporaryURL
        )
        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(
                destinationURL,
                withItemAt: temporaryURL
            )
        } else {
            try fileManager.moveItem(
                at: temporaryURL,
                to: destinationURL
            )
        }
    }
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case mp4 = "MP4"
    case gif = "GIF"

    var id: Self { self }
}

enum VideoPasteboardError: LocalizedError {
    case cannotWrite

    var errorDescription: String? {
        "The exported video could not be copied to the clipboard."
    }
}

struct VideoPasteboardWriter {
    func write(fileURL: URL, to pasteboard: NSPasteboard = .general) throws {
        pasteboard.clearContents()
        guard pasteboard.writeObjects([fileURL as NSURL]) else {
            throw VideoPasteboardError.cannotWrite
        }
    }
}

enum ExportResolution: String, CaseIterable, Identifiable {
    case source = "Source"
    case p4K = "4K"
    case p1080 = "1080p"
    case p720 = "720p"
    case custom = "Custom"

    var id: Self { self }

    var presetName: String {
        switch self {
        case .source:
            return AVAssetExportPresetHighestQuality
        case .p4K:
            return AVAssetExportPreset3840x2160
        case .p1080:
            return AVAssetExportPreset1920x1080
        case .p720:
            return AVAssetExportPreset1280x720
        case .custom:
            return AVAssetExportPresetHighestQuality
        }
    }

    func dimensions(
        sourceSize: CGSize,
        canvasAspectRatio: CanvasAspectRatio,
        customDimensions: ExportDimensions
    ) -> ExportDimensions {
        if self == .custom {
            return customDimensions
        }

        let safeSource = CGSize(
            width: max(2, sourceSize.width),
            height: max(2, sourceSize.height)
        )
        if self == .source {
            let geometry = CanvasCropGeometry(
                sourceSize: safeSource,
                aspectRatio: canvasAspectRatio
            )
            return ExportDimensions(
                width: Int(geometry.renderSize.width.rounded(.down)),
                height: Int(geometry.renderSize.height.rounded(.down))
            )
        }

        let shortEdge: CGFloat
        switch self {
        case .p4K:
            shortEdge = 2_160
        case .p1080:
            shortEdge = 1_080
        case .p720:
            shortEdge = 720
        case .source, .custom:
            shortEdge = min(safeSource.width, safeSource.height)
        }
        let ratio = canvasAspectRatio.effectiveRatio(
            sourceAspectRatio: safeSource.width / safeSource.height
        )
        let rawSize: CGSize
        if ratio >= 1 {
            rawSize = CGSize(
                width: shortEdge * ratio,
                height: shortEdge
            )
        } else {
            rawSize = CGSize(
                width: shortEdge,
                height: shortEdge / ratio
            )
        }
        return ExportDimensions(
            width: Int(rawSize.width.rounded()),
            height: Int(rawSize.height.rounded())
        )
    }
}

struct ExportDimensions: Equatable, Sendable {
    static let supportedRange = 320...7680

    let width: Int
    let height: Int

    init(width: Int, height: Int) {
        self.width = Self.sanitized(width)
        self.height = Self.sanitized(height)
    }

    var size: CGSize {
        CGSize(width: width, height: height)
    }

    static func sanitized(_ value: Int) -> Int {
        let clamped = value.clamped(to: supportedRange)
        return clamped.isMultiple(of: 2) ? clamped : clamped - 1
    }
}

enum ExportQuality: String, CaseIterable, Identifiable {
    case studio = "Studio"
    case social = "Social Media"
    case web = "Web"
    case webLow = "Web (Low)"

    var id: Self { self }

    func presetName(for resolution: ExportResolution) -> String {
        guard resolution == .source else { return resolution.presetName }
        switch self {
        case .studio:
            return AVAssetExportPresetHighestQuality
        case .social:
            return AVAssetExportPresetMediumQuality
        case .web:
            return AVAssetExportPresetMediumQuality
        case .webLow:
            return AVAssetExportPresetLowQuality
        }
    }

    var explanation: String {
        switch self {
        case .studio:
            return "Highest fidelity for editing, archiving, and large displays."
        case .social:
            return "Balanced quality and file size for social platforms."
        case .web:
            return "Smaller files for websites, messages, and presentations."
        case .webLow:
            return "Maximum compression for quick sharing and previews."
        }
    }

    fileprivate var videoBitsPerPixelPerFrame: Double {
        switch self {
        case .studio:
            return 0.12
        case .social:
            return 0.07
        case .web:
            return 0.04
        case .webLow:
            return 0.022
        }
    }

    fileprivate var gifBytesPerPixelPerFrame: Double {
        switch self {
        case .studio:
            return 0.012
        case .social:
            return 0.009
        case .web:
            return 0.006
        case .webLow:
            return 0.004
        }
    }

    var gifPosterizeLevels: Double? {
        switch self {
        case .studio:
            return nil
        case .social:
            return 24
        case .web:
            return 12
        case .webLow:
            return 6
        }
    }

    var imageCompressionQuality: Double {
        switch self {
        case .studio:
            return 1
        case .social:
            return 0.82
        case .web:
            return 0.62
        case .webLow:
            return 0.42
        }
    }
}

struct ExportEstimate: Equatable, Sendable {
    let fileSizeBytes: Int64
    let processingDuration: TimeInterval
}

enum ExportEstimateCalculator {
    static func estimate(
        timelineDuration: TimeInterval,
        dimensions: ExportDimensions,
        frameRate: Int,
        format: ExportFormat,
        quality: ExportQuality
    ) -> ExportEstimate {
        let duration = max(0.1, timelineDuration)
        let pixels = Double(dimensions.width * dimensions.height)
        let safeFrameRate = Double(
            ExportFrameRateOptions.normalized(frameRate, for: format)
        )
        let rawBytes: Double
        switch format {
        case .mp4:
            let videoBitsPerSecond = max(
                350_000,
                pixels * safeFrameRate * quality.videoBitsPerPixelPerFrame
            )
            let audioBitsPerSecond = 192_000.0
            rawBytes = duration
                * (videoBitsPerSecond + audioBitsPerSecond)
                / 8
                * 1.03
        case .gif:
            rawBytes = duration
                * pixels
                * safeFrameRate
                * quality.gifBytesPerPixelPerFrame
                * 1.03
        }

        let pixelFactor = pixels / Double(1_920 * 1_080)
        let frameFactor = safeFrameRate / 30
        let formatFactor = format == .gif ? 1.65 : 0.72
        let processingDuration = max(
            1,
            duration * max(0.18, pixelFactor) * frameFactor * formatFactor
        )
        return ExportEstimate(
            fileSizeBytes: max(1, Int64(rawBytes.rounded())),
            processingDuration: processingDuration
        )
    }

    static func targetFileLength(
        timelineDuration: TimeInterval,
        dimensions: ExportDimensions,
        frameRate: Int,
        format: ExportFormat,
        quality: ExportQuality
    ) -> Int64? {
        guard format == .mp4, quality != .studio else { return nil }
        let estimate = estimate(
            timelineDuration: timelineDuration,
            dimensions: dimensions,
            frameRate: frameRate,
            format: format,
            quality: quality
        )
        return max(1_000_000, Int64(Double(estimate.fileSizeBytes) * 1.08))
    }
}
