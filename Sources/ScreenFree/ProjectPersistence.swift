import Foundation
import ScreenFreeCore

struct ScreenFreeProjectSnapshot: Codable {
    static let currentVersion = 1

    var version: Int
    var sourcePath: String
    var cameraPath: String?
    var project: TimelineProject
    var canvasAspectRatio: CanvasAspectRatio?
    var canvasContentMode: CanvasContentMode? = nil
    var canvasPadding: Double
    var cornerRadius: Double
    var backgroundHue: Double
    var backgroundMode: CanvasBackgroundMode
    var wallpaperPreset: WallpaperPreset? = nil
    var backgroundImagePath: String?
    var backgroundBlur: Double?
    var shadowStrength: Double
    var cursorSize: Double
    var cursorReplacement: CursorReplacementStyle? = nil
    var showCursor: Bool
    var hideCursorWhenIdle: Bool
    var cursorIdleTimeout: Double
    var cursorTailFreeze: Double? = nil
    var cursorLoopToStart: Bool? = nil
    var removeCursorShakes: Bool? = nil
    var cursorShakeThreshold: Double? = nil
    var optimizeRapidCursorChanges: Bool? = nil
    var smoothCursorMovement: Bool? = nil
    var backgroundMusicPath: String? = nil
    var backgroundMusicVolume: Double? = nil
    var recordedAudioLayout: RecordedAudioLayout? = nil
    var systemAudioVolume: Double? = nil
    var microphoneAudioVolume: Double? = nil
    var microphoneAudioMuted: Bool? = nil
    var showClickRipple: Bool
    var clickEffectPreset: ClickEffectPreset? = nil
    var showShortcutOverlay: Bool? = nil
    var showCaptions: Bool
    var captionFontSize: Double
    var captionLanguage: String
    var captionVocabulary: String? = nil
    var zoomScale: Double
    var zoomDuration: Double
    var zoomMotionPreset: ZoomMotionPreset?
    var zoomCustomTransitionDuration: Double? = nil
    var zoomCustomX1: Double? = nil
    var zoomCustomY1: Double? = nil
    var zoomCustomX2: Double? = nil
    var zoomCustomY2: Double? = nil
    var motionBlurEnabled: Bool? = nil
    var motionBlurStrength: Double? = nil
    var cursorMotionBlur: Double? = nil
    var zoomMotionBlur: Double? = nil
    var panMotionBlur: Double? = nil
    var cameraSize: Double
    var cameraCornerRadius: Double
    var cameraMirrored: Bool
    var cameraPosition: CameraPosition
    var updatedAt: Date
}

enum ProjectPersistenceError: LocalizedError {
    case unsupportedVersion
    case missingSource

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion:
            return "This ScreenFree project was created by an unsupported version."
        case .missingSource:
            return "The original recording for this project could not be found."
        }
    }
}

struct ProjectPersistence {
    let recoveryURL: URL

    init() {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        recoveryURL = base
            .appendingPathComponent("ScreenFree", isDirectory: true)
            .appendingPathComponent("Recovery.screenfree")
    }

    func save(_ snapshot: ScreenFreeProjectSnapshot, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }

    func load(from url: URL) throws -> ScreenFreeProjectSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(
            ScreenFreeProjectSnapshot.self,
            from: Data(contentsOf: url)
        )
        guard snapshot.version <= ScreenFreeProjectSnapshot.currentVersion else {
            throw ProjectPersistenceError.unsupportedVersion
        }
        guard FileManager.default.fileExists(atPath: snapshot.sourcePath) else {
            throw ProjectPersistenceError.missingSource
        }
        return snapshot
    }
}
