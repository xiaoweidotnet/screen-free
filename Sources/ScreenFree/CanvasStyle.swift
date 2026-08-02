import CoreGraphics
import Foundation
import ScreenFreeCore

enum CanvasBackgroundMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case wallpaper = "Wallpaper"
    case gradient = "Gradient"
    case solid = "Color"
    case image = "Image"

    var id: Self { self }
}

struct WallpaperColor: Equatable, Sendable {
    let hue: Double
    let saturation: Double
    let brightness: Double
}

enum WallpaperPreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case aurora = "Aurora"
    case sunset = "Sunset"
    case ocean = "Ocean"
    case forest = "Forest"
    case candy = "Candy"
    case graphite = "Graphite"

    var id: Self { self }

    var colors: [WallpaperColor] {
        switch self {
        case .aurora:
            return [
                WallpaperColor(hue: 0.48, saturation: 0.82, brightness: 0.72),
                WallpaperColor(hue: 0.68, saturation: 0.78, brightness: 0.56),
                WallpaperColor(hue: 0.82, saturation: 0.62, brightness: 0.42)
            ]
        case .sunset:
            return [
                WallpaperColor(hue: 0.98, saturation: 0.72, brightness: 0.76),
                WallpaperColor(hue: 0.08, saturation: 0.88, brightness: 0.86),
                WallpaperColor(hue: 0.78, saturation: 0.74, brightness: 0.42)
            ]
        case .ocean:
            return [
                WallpaperColor(hue: 0.54, saturation: 0.82, brightness: 0.76),
                WallpaperColor(hue: 0.62, saturation: 0.86, brightness: 0.52),
                WallpaperColor(hue: 0.5, saturation: 0.7, brightness: 0.3)
            ]
        case .forest:
            return [
                WallpaperColor(hue: 0.42, saturation: 0.72, brightness: 0.48),
                WallpaperColor(hue: 0.36, saturation: 0.8, brightness: 0.34),
                WallpaperColor(hue: 0.14, saturation: 0.5, brightness: 0.46)
            ]
        case .candy:
            return [
                WallpaperColor(hue: 0.92, saturation: 0.54, brightness: 0.94),
                WallpaperColor(hue: 0.78, saturation: 0.58, brightness: 0.82),
                WallpaperColor(hue: 0.55, saturation: 0.46, brightness: 0.92)
            ]
        case .graphite:
            return [
                WallpaperColor(hue: 0.64, saturation: 0.18, brightness: 0.38),
                WallpaperColor(hue: 0.7, saturation: 0.24, brightness: 0.22),
                WallpaperColor(hue: 0.58, saturation: 0.12, brightness: 0.12)
            ]
        }
    }

    var startPoint: CGPoint {
        switch self {
        case .sunset, .forest:
            return CGPoint(x: 0.5, y: 0)
        case .ocean:
            return CGPoint(x: 1, y: 0)
        default:
            return CGPoint(x: 0, y: 0)
        }
    }

    var endPoint: CGPoint {
        switch self {
        case .sunset, .forest:
            return CGPoint(x: 0.5, y: 1)
        case .ocean:
            return CGPoint(x: 0, y: 1)
        default:
            return CGPoint(x: 1, y: 1)
        }
    }
}

enum ClickEffectPreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case none = "None"
    case circle = "Circle"
    case ripple = "Ripple"
    case rotation = "Rotation"

    var id: Self { self }

    var duration: TimeInterval {
        switch self {
        case .none:
            return 0
        case .circle:
            return 0.42
        case .ripple:
            return 0.55
        case .rotation:
            return 0.62
        }
    }
}

enum CanvasAspectRatio: String, CaseIterable, Codable, Identifiable, Sendable {
    case source = "Source"
    case landscape16x9 = "16:9"
    case portrait9x16 = "9:16"
    case square = "1:1"
    case classic4x3 = "4:3"
    case portrait3x4 = "3:4"

    var id: Self { self }

    var displayTitle: String {
        switch self {
        case .source:
            return "Auto"
        case .landscape16x9:
            return "Wide 16:9"
        case .portrait9x16:
            return "Vertical 9:16"
        case .square:
            return "Square 1:1"
        case .classic4x3:
            return "Classic 4:3"
        case .portrait3x4:
            return "Tall 3:4"
        }
    }

    var ratio: CGFloat? {
        switch self {
        case .source:
            return nil
        case .landscape16x9:
            return 16 / 9
        case .portrait9x16:
            return 9 / 16
        case .square:
            return 1
        case .classic4x3:
            return 4 / 3
        case .portrait3x4:
            return 3 / 4
        }
    }

    func effectiveRatio(sourceAspectRatio: CGFloat) -> CGFloat {
        ratio ?? max(0.01, sourceAspectRatio)
    }

    func previewSize(
        in container: CGSize,
        sourceAspectRatio: CGFloat
    ) -> CGSize {
        let targetRatio = effectiveRatio(
            sourceAspectRatio: sourceAspectRatio
        )
        guard container.width > 0, container.height > 0 else {
            return .zero
        }
        if container.width / container.height > targetRatio {
            return CGSize(
                width: container.height * targetRatio,
                height: container.height
            )
        }
        return CGSize(
            width: container.width,
            height: container.width / targetRatio
        )
    }
}

enum CanvasContentMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case fit = "Fit"
    case crop = "Crop"

    var id: Self { self }
}

struct CanvasCropGeometry: Sendable {
    let sourceSize: CGSize
    let renderSize: CGSize
    let scale: CGFloat
    let offset: CGPoint

    init(
        sourceSize: CGSize,
        aspectRatio: CanvasAspectRatio,
        contentMode: CanvasContentMode = .crop
    ) {
        let safeSource = CGSize(
            width: max(2, sourceSize.width),
            height: max(2, sourceSize.height)
        )
        let targetRatio = aspectRatio.effectiveRatio(
            sourceAspectRatio: safeSource.width / safeSource.height
        )
        let rawRenderSize: CGSize
        if targetRatio >= safeSource.width / safeSource.height {
            rawRenderSize = CGSize(
                width: safeSource.width,
                height: safeSource.width / targetRatio
            )
        } else {
            rawRenderSize = CGSize(
                width: safeSource.height * targetRatio,
                height: safeSource.height
            )
        }
        let evenRenderSize = CGSize(
            width: max(2, floor(rawRenderSize.width / 2) * 2),
            height: max(2, floor(rawRenderSize.height / 2) * 2)
        )
        self.init(
            sourceSize: safeSource,
            targetSize: evenRenderSize,
            contentMode: contentMode
        )
    }

    init(
        sourceSize: CGSize,
        targetSize: CGSize,
        contentMode: CanvasContentMode = .crop
    ) {
        let safeSource = CGSize(
            width: max(2, sourceSize.width),
            height: max(2, sourceSize.height)
        )
        let evenRenderSize = CGSize(
            width: max(2, floor(targetSize.width / 2) * 2),
            height: max(2, floor(targetSize.height / 2) * 2)
        )
        let horizontalScale = evenRenderSize.width / safeSource.width
        let verticalScale = evenRenderSize.height / safeSource.height
        let resolvedScale = switch contentMode {
        case .fit:
            min(horizontalScale, verticalScale)
        case .crop:
            max(horizontalScale, verticalScale)
        }
        let scaledSize = CGSize(
            width: safeSource.width * resolvedScale,
            height: safeSource.height * resolvedScale
        )

        self.sourceSize = safeSource
        self.renderSize = evenRenderSize
        self.scale = resolvedScale
        self.offset = CGPoint(
            x: (evenRenderSize.width - scaledSize.width) / 2,
            y: (evenRenderSize.height - scaledSize.height) / 2
        )
    }

    var transform: CGAffineTransform {
        CGAffineTransform(
            a: scale,
            b: 0,
            c: 0,
            d: scale,
            tx: offset.x,
            ty: offset.y
        )
    }

    func normalizedOutputPoint(
        x: CGFloat,
        y: CGFloat
    ) -> CGPoint {
        let output = CGPoint(
            x: offset.x + sourceSize.width * x.clamped(to: 0...1) * scale,
            y: offset.y
                + sourceSize.height * (1 - y.clamped(to: 0...1)) * scale
        )
        return CGPoint(
            x: output.x / renderSize.width,
            y: output.y / renderSize.height
        )
    }

    func clampedNormalizedOutputPoint(
        x: CGFloat,
        y: CGFloat
    ) -> CGPoint {
        let point = normalizedOutputPoint(x: x, y: y)
        return CGPoint(
            x: point.x.clamped(to: 0...1),
            y: point.y.clamped(to: 0...1)
        )
    }

    func containsSourcePoint(
        x: CGFloat,
        y: CGFloat
    ) -> Bool {
        let point = normalizedOutputPoint(x: x, y: y)
        return (0...1).contains(point.x) && (0...1).contains(point.y)
    }

    func sourceNormalizedPoint(
        outputX: CGFloat,
        outputY: CGFloat
    ) -> CGPoint {
        let sourceX = (
            renderSize.width * outputX.clamped(to: 0...1) - offset.x
        ) / (sourceSize.width * scale)
        let sourceTopDownY = (
            renderSize.height * outputY.clamped(to: 0...1) - offset.y
        ) / (sourceSize.height * scale)
        return CGPoint(
            x: sourceX.clamped(to: 0...1),
            y: (1 - sourceTopDownY).clamped(to: 0...1)
        )
    }
}
