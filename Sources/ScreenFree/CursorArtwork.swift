import AppKit
import CoreGraphics

enum CursorReplacementStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case arrow
    case pointer

    var id: Self { self }

    var title: String {
        switch self {
        case .arrow:
            return "Arrow"
        case .pointer:
            return "Pointer"
        }
    }
}

enum CursorArtwork {
    static func size(for style: CursorReplacementStyle) -> CGSize {
        switch style {
        case .arrow:
            return CGSize(width: 24, height: 30)
        case .pointer:
            return CGSize(width: 28, height: 32)
        }
    }

    /// Normalized from the artwork's top-left corner.
    static func hotspot(for style: CursorReplacementStyle) -> CGPoint {
        switch style {
        case .arrow:
            return CGPoint(x: 0.12, y: 0.12)
        case .pointer:
            return CGPoint(x: 0.43, y: 0.08)
        }
    }

    static func cgImage(for style: CursorReplacementStyle) -> CGImage {
        switch style {
        case .arrow:
            return arrowCGImage
        case .pointer:
            return pointerCGImage
        }
    }

    static func image(for style: CursorReplacementStyle) -> NSImage {
        NSImage(cgImage: cgImage(for: style), size: size(for: style))
    }

    private static let arrowCGImage: CGImage = {
        let width = 48
        let height = 60
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.setLineJoin(.round)
        context.setLineCap(.round)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: 4, y: 56))
        path.addLine(to: CGPoint(x: 6, y: 12))
        path.addLine(to: CGPoint(x: 17, y: 23))
        path.addLine(to: CGPoint(x: 28, y: 4))
        path.addLine(to: CGPoint(x: 37, y: 10))
        path.addLine(to: CGPoint(x: 26, y: 29))
        path.addLine(to: CGPoint(x: 44, y: 30))
        path.closeSubpath()

        context.addPath(path)
        context.setFillColor(NSColor.white.cgColor)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.88).cgColor)
        context.setLineWidth(3)
        context.drawPath(using: .fillStroke)
        return context.makeImage()!
    }()

    private static let pointerCGImage: CGImage = {
        let width = 56
        let height = 64
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.setLineJoin(.round)
        context.setLineCap(.round)

        // A compact link-pointer hand with the fingertip at the top.
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 21, y: 5))
        path.addCurve(
            to: CGPoint(x: 15, y: 12),
            control1: CGPoint(x: 18, y: 7),
            control2: CGPoint(x: 16, y: 9)
        )
        path.addLine(to: CGPoint(x: 6, y: 27))
        path.addCurve(
            to: CGPoint(x: 13, y: 34),
            control1: CGPoint(x: 3, y: 31),
            control2: CGPoint(x: 8, y: 37)
        )
        path.addLine(to: CGPoint(x: 19, y: 29))
        path.addLine(to: CGPoint(x: 19, y: 56))
        path.addCurve(
            to: CGPoint(x: 27, y: 56),
            control1: CGPoint(x: 19, y: 62),
            control2: CGPoint(x: 27, y: 62)
        )
        path.addLine(to: CGPoint(x: 27, y: 35))
        path.addLine(to: CGPoint(x: 30, y: 40))
        path.addCurve(
            to: CGPoint(x: 37, y: 37),
            control1: CGPoint(x: 33, y: 44),
            control2: CGPoint(x: 38, y: 42)
        )
        path.addCurve(
            to: CGPoint(x: 45, y: 33),
            control1: CGPoint(x: 40, y: 40),
            control2: CGPoint(x: 46, y: 38)
        )
        path.addCurve(
            to: CGPoint(x: 51, y: 26),
            control1: CGPoint(x: 49, y: 34),
            control2: CGPoint(x: 53, y: 31)
        )
        path.addLine(to: CGPoint(x: 48, y: 15))
        path.addCurve(
            to: CGPoint(x: 41, y: 5),
            control1: CGPoint(x: 47, y: 9),
            control2: CGPoint(x: 44, y: 6)
        )
        path.closeSubpath()

        context.addPath(path)
        context.setFillColor(NSColor.white.cgColor)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.88).cgColor)
        context.setLineWidth(3)
        context.drawPath(using: .fillStroke)
        return context.makeImage()!
    }()
}
