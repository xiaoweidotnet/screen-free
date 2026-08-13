import CoreGraphics
import ScreenFreeCore

enum DisplayPixelGeometryResolver {
    static func geometry(
        displayID: CGDirectDisplayID,
        logicalSize: CGSize,
        fallbackScale: CGFloat = 1
    ) -> RecordingDisplayGeometry {
        let pixelSize: CGSize
        if let mode = CGDisplayCopyDisplayMode(displayID),
           mode.pixelWidth > 0,
           mode.pixelHeight > 0 {
            pixelSize = CGSize(width: mode.pixelWidth, height: mode.pixelHeight)
        } else {
            let safeScale = max(1, fallbackScale.isFinite ? fallbackScale : 1)
            pixelSize = CGSize(
                width: logicalSize.width * safeScale,
                height: logicalSize.height * safeScale
            )
        }

        return RecordingDisplayGeometry(
            logicalSize: logicalSize,
            pixelSize: pixelSize
        )
    }
}
