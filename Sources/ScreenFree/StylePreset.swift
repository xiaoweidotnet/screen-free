import Foundation

struct ScreenFreeStylePreset: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int = currentVersion
    var name: String
    var canvasAspectRatio: CanvasAspectRatio
    var canvasContentMode: CanvasContentMode? = nil
    var canvasPadding: Double
    var cornerRadius: Double
    var backgroundHue: Double
    var backgroundMode: CanvasBackgroundMode
    var wallpaperPreset: WallpaperPreset? = nil
    var backgroundImagePath: String?
    var backgroundBlur: Double
    var shadowStrength: Double
    var cursorSize: Double
    var cursorReplacement: CursorReplacementStyle? = nil
    var showCursor: Bool
    var hideCursorWhenIdle: Bool
    var cursorIdleTimeout: Double
    var cursorTailFreeze: Double
    var cursorLoopToStart: Bool? = nil
    var removeCursorShakes: Bool? = nil
    var cursorShakeThreshold: Double? = nil
    var optimizeRapidCursorChanges: Bool? = nil
    var smoothCursorMovement: Bool? = nil
    var clickEffectPreset: ClickEffectPreset
    var showShortcutOverlay: Bool
    var showCaptions: Bool
    var captionFontSize: Double
    var zoomScale: Double
    var zoomDuration: Double
    var zoomMotionPreset: ZoomMotionPreset
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
}

enum BuiltInStylePreset: String, CaseIterable, Identifiable {
    case clean = "Clean"
    case vibrant = "Vibrant"
    case minimal = "Minimal"

    var id: Self { self }

    var preset: ScreenFreeStylePreset {
        switch self {
        case .clean:
            return ScreenFreeStylePreset(
                name: rawValue,
                canvasAspectRatio: .source,
                canvasContentMode: .fit,
                canvasPadding: 28,
                cornerRadius: 16,
                backgroundHue: 0.62,
                backgroundMode: .wallpaper,
                wallpaperPreset: .aurora,
                backgroundImagePath: nil,
                backgroundBlur: 0,
                shadowStrength: 0.45,
                cursorSize: 1.25,
                cursorReplacement: .arrow,
                showCursor: true,
                hideCursorWhenIdle: false,
                cursorIdleTimeout: 2,
                cursorTailFreeze: 0.8,
                cursorLoopToStart: true,
                removeCursorShakes: true,
                cursorShakeThreshold: 0.012,
                optimizeRapidCursorChanges: true,
                smoothCursorMovement: true,
                clickEffectPreset: .circle,
                showShortcutOverlay: true,
                showCaptions: true,
                captionFontSize: 34,
                zoomScale: 1.75,
                zoomDuration: 3.2,
                zoomMotionPreset: .mellow,
                zoomCustomTransitionDuration: 0.82,
                zoomCustomX1: 0.25,
                zoomCustomY1: 0.1,
                zoomCustomX2: 0.25,
                zoomCustomY2: 1,
                motionBlurEnabled: true,
                motionBlurStrength: 0.42,
                cursorMotionBlur: 0.58,
                zoomMotionBlur: 0.45,
                panMotionBlur: 0.34,
                cameraSize: 0.22,
                cameraCornerRadius: 18,
                cameraMirrored: true,
                cameraPosition: .bottomRight
            )
        case .vibrant:
            return ScreenFreeStylePreset(
                name: rawValue,
                canvasAspectRatio: .landscape16x9,
                canvasContentMode: .fit,
                canvasPadding: 46,
                cornerRadius: 24,
                backgroundHue: 0.79,
                backgroundMode: .wallpaper,
                wallpaperPreset: .candy,
                backgroundImagePath: nil,
                backgroundBlur: 0,
                shadowStrength: 0.68,
                cursorSize: 1.5,
                cursorReplacement: .pointer,
                showCursor: true,
                hideCursorWhenIdle: false,
                cursorIdleTimeout: 2,
                cursorTailFreeze: 1,
                cursorLoopToStart: true,
                removeCursorShakes: true,
                cursorShakeThreshold: 0.014,
                optimizeRapidCursorChanges: true,
                smoothCursorMovement: true,
                clickEffectPreset: .ripple,
                showShortcutOverlay: true,
                showCaptions: true,
                captionFontSize: 38,
                zoomScale: 1.9,
                zoomDuration: 2,
                zoomMotionPreset: .quick,
                zoomCustomTransitionDuration: 0.28,
                zoomCustomX1: 0.16,
                zoomCustomY1: 0.72,
                zoomCustomX2: 0.28,
                zoomCustomY2: 1,
                motionBlurEnabled: true,
                motionBlurStrength: 0.58,
                cursorMotionBlur: 0.72,
                zoomMotionBlur: 0.62,
                panMotionBlur: 0.48,
                cameraSize: 0.26,
                cameraCornerRadius: 24,
                cameraMirrored: true,
                cameraPosition: .bottomRight
            )
        case .minimal:
            return ScreenFreeStylePreset(
                name: rawValue,
                canvasAspectRatio: .source,
                canvasContentMode: .fit,
                canvasPadding: 12,
                cornerRadius: 8,
                backgroundHue: 0.66,
                backgroundMode: .solid,
                wallpaperPreset: .graphite,
                backgroundImagePath: nil,
                backgroundBlur: 0,
                shadowStrength: 0.22,
                cursorSize: 1.05,
                cursorReplacement: .arrow,
                showCursor: true,
                hideCursorWhenIdle: true,
                cursorIdleTimeout: 1.5,
                cursorTailFreeze: 0.5,
                cursorLoopToStart: false,
                removeCursorShakes: true,
                cursorShakeThreshold: 0.01,
                optimizeRapidCursorChanges: false,
                smoothCursorMovement: false,
                clickEffectPreset: .none,
                showShortcutOverlay: false,
                showCaptions: true,
                captionFontSize: 30,
                zoomScale: 1.55,
                zoomDuration: 2.5,
                zoomMotionPreset: .slow,
                zoomCustomTransitionDuration: 0.46,
                zoomCustomX1: 0.42,
                zoomCustomY1: 0,
                zoomCustomX2: 0.58,
                zoomCustomY2: 1,
                motionBlurEnabled: false,
                motionBlurStrength: 0.32,
                cursorMotionBlur: 0.36,
                zoomMotionBlur: 0.3,
                panMotionBlur: 0.24,
                cameraSize: 0.2,
                cameraCornerRadius: 12,
                cameraMirrored: true,
                cameraPosition: .bottomRight
            )
        }
    }
}

enum StylePresetError: LocalizedError {
    case unsupportedVersion

    var errorDescription: String? {
        "This style preset was created by an unsupported ScreenFree version."
    }
}

struct StylePresetPersistence {
    func save(_ preset: ScreenFreeStylePreset, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(preset).write(to: url, options: .atomic)
    }

    func load(from url: URL) throws -> ScreenFreeStylePreset {
        let preset = try JSONDecoder().decode(
            ScreenFreeStylePreset.self,
            from: Data(contentsOf: url)
        )
        guard preset.version <= ScreenFreeStylePreset.currentVersion else {
            throw StylePresetError.unsupportedVersion
        }
        return preset
    }
}
