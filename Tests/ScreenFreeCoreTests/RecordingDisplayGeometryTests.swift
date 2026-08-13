import CoreGraphics
import XCTest
@testable import ScreenFreeCore

final class RecordingDisplayGeometryTests: XCTestCase {
    func testRetinaDisplayPreservesAllBackingPixels() {
        let geometry = RecordingDisplayGeometry(
            logicalSize: CGSize(width: 1_512, height: 982),
            pixelSize: CGSize(width: 3_024, height: 1_964)
        )

        XCTAssertEqual(
            geometry.fullDisplayOutputSize,
            CGSize(width: 3_024, height: 1_964),
            "A 2× Retina display must not be encoded at its logical point size."
        )
    }

    func testOneXDisplayIsNotUpscaled() {
        let geometry = RecordingDisplayGeometry(
            logicalSize: CGSize(width: 2_560, height: 1_440),
            pixelSize: CGSize(width: 2_560, height: 1_440)
        )

        XCTAssertEqual(
            geometry.fullDisplayOutputSize,
            CGSize(width: 2_560, height: 1_440)
        )
        XCTAssertEqual(
            geometry.windowOutputSize(
                forLogicalSize: CGSize(width: 800, height: 600)
            ),
            CGSize(width: 800, height: 600),
            "A window on a 1× display must not be doubled."
        )
    }

    func testRetinaAreaUsesLogicalSourceRectAndPhysicalOutputSize() {
        let geometry = RecordingDisplayGeometry(
            logicalSize: CGSize(width: 1_512, height: 982),
            pixelSize: CGSize(width: 3_024, height: 1_964)
        )
        let sourceRect = geometry.logicalSourceRect(
            normalizedArea: CGRect(x: 0.25, y: 0, width: 0.5, height: 0.5)
        )

        XCTAssertEqual(
            sourceRect,
            CGRect(x: 378, y: 0, width: 756, height: 491),
            "ScreenCaptureKit sourceRect remains in logical display coordinates."
        )
        XCTAssertEqual(
            geometry.areaOutputSize(forLogicalSourceRect: sourceRect),
            CGSize(width: 1_512, height: 982),
            "The encoded area must retain the selected Retina backing pixels."
        )
    }

    func testDefaultEightyPercentRetinaAreaMatchesEncodedDimensions() {
        let geometry = RecordingDisplayGeometry(
            logicalSize: CGSize(width: 1_512, height: 982),
            pixelSize: CGSize(width: 3_024, height: 1_964)
        )
        let sourceRect = geometry.logicalSourceRect(
            normalizedArea: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        )

        XCTAssertEqual(sourceRect, CGRect(x: 151, y: 98, width: 1_210, height: 786))
        XCTAssertEqual(
            geometry.areaOutputSize(forLogicalSourceRect: sourceRect),
            CGSize(width: 2_420, height: 1_572)
        )
    }

    func testRetinaWindowUsesActualDisplayScale() {
        let geometry = RecordingDisplayGeometry(
            logicalSize: CGSize(width: 1_512, height: 982),
            pixelSize: CGSize(width: 3_024, height: 1_964)
        )

        XCTAssertEqual(
            geometry.windowOutputSize(
                forLogicalSize: CGSize(width: 801, height: 601)
            ),
            CGSize(width: 1_602, height: 1_202)
        )
    }

    func testEncodedDimensionsAreRoundedToEvenPixels() {
        let geometry = RecordingDisplayGeometry(
            logicalSize: CGSize(width: 1_000, height: 800),
            pixelSize: CGSize(width: 1_500, height: 1_200)
        )

        XCTAssertEqual(
            geometry.windowOutputSize(
                forLogicalSize: CGSize(width: 801, height: 601)
            ),
            CGSize(width: 1_202, height: 902),
            "H.264 output dimensions must remain even after non-integer display scaling."
        )
    }
}
