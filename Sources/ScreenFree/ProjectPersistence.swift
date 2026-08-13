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
    var transitionStyle: ClipTransitionStyle? = nil
    var transitionDuration: Double? = nil
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

    init(recoveryURL: URL? = nil) {
        if let recoveryURL {
            self.recoveryURL = recoveryURL
            return
        }
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        self.recoveryURL = base
            .appendingPathComponent("ScreenFree", isDirectory: true)
            .appendingPathComponent("Recovery.screenfree")
    }

    var previousRecoveryURL: URL {
        recoveryURL.deletingPathExtension()
            .appendingPathExtension("previous.screenfree")
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

    /// Prevents a transient empty load state from erasing a cursor path that
    /// was already captured for the same source recording. A previous copy is
    /// retained as an additional recovery point before the atomic write.
    func savePreservingRecordedInteractions(
        _ snapshot: ScreenFreeProjectSnapshot,
        to url: URL,
        backupURL: URL? = nil
    ) throws {
        var protectedSnapshot = snapshot
        if FileManager.default.fileExists(atPath: url.path),
           let existing = try? load(from: url),
           existing.sourcePath == snapshot.sourcePath,
           snapshot.project.cursorSamples.isEmpty,
           !existing.project.cursorSamples.isEmpty {
            protectedSnapshot.project.cursorSamples =
                existing.project.cursorSamples
            protectedSnapshot.project.clicks = existing.project.clicks
            protectedSnapshot.project.shortcuts = existing.project.shortcuts
        }
        if let backupURL,
           FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: backupURL)
            try FileManager.default.copyItem(at: url, to: backupURL)
        }
        try save(protectedSnapshot, to: url)
    }

    func saveRecovery(_ snapshot: ScreenFreeProjectSnapshot) throws {
        try savePreservingRecordedInteractions(
            snapshot,
            to: recoveryURL,
            backupURL: previousRecoveryURL
        )
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
