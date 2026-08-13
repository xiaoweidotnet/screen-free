import CoreGraphics
import Foundation

/// Converts logical ScreenCaptureKit coordinates into encoded video dimensions.
///
/// Source rectangles remain in logical display coordinates. Output dimensions are
/// resolved separately so HiDPI captures can retain the display's backing pixels.
public struct RecordingDisplayGeometry: Equatable, Sendable {
    public let logicalSize: CGSize
    public let pixelSize: CGSize

    public init(logicalSize: CGSize, pixelSize: CGSize) {
        let validLogicalSize = Self.validSize(logicalSize) ?? CGSize(width: 1, height: 1)
        self.logicalSize = validLogicalSize
        self.pixelSize = Self.validSize(pixelSize) ?? validLogicalSize
    }

    public var fullDisplayOutputSize: CGSize {
        Self.encodedSize(pixelSize)
    }

    public func logicalSourceRect(normalizedArea: CGRect) -> CGRect {
        let unitRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        let normalized = normalizedArea.standardized.intersection(unitRect)
        guard !normalized.isNull, normalized.width > 0, normalized.height > 0 else {
            return CGRect(origin: .zero, size: logicalSize)
        }

        let logicalBounds = CGRect(origin: .zero, size: logicalSize)
        let sourceRect = CGRect(
            x: logicalSize.width * normalized.minX,
            y: logicalSize.height * normalized.minY,
            width: logicalSize.width * normalized.width,
            height: logicalSize.height * normalized.height
        ).integral
        return sourceRect.intersection(logicalBounds)
    }

    public func areaOutputSize(forLogicalSourceRect sourceRect: CGRect) -> CGSize {
        Self.encodedSize(
            CGSize(
                width: sourceRect.width * horizontalScale,
                height: sourceRect.height * verticalScale
            )
        )
    }

    public func windowOutputSize(forLogicalSize windowSize: CGSize) -> CGSize {
        Self.encodedSize(
            CGSize(
                width: windowSize.width * horizontalScale,
                height: windowSize.height * verticalScale
            )
        )
    }

    private var horizontalScale: CGFloat {
        pixelSize.width / logicalSize.width
    }

    private var verticalScale: CGFloat {
        pixelSize.height / logicalSize.height
    }

    private static func validSize(_ size: CGSize) -> CGSize? {
        guard size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0 else {
            return nil
        }
        return size
    }

    private static func encodedSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: CGFloat(evenPixelDimension(size.width)),
            height: CGFloat(evenPixelDimension(size.height))
        )
    }

    private static func evenPixelDimension(_ value: CGFloat) -> Int {
        let rounded = max(2, Int(value.rounded()))
        return rounded.isMultiple(of: 2) ? rounded : rounded + 1
    }
}
