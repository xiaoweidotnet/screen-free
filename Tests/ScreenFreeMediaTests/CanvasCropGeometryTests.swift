import CoreGraphics
import XCTest
@testable import ScreenFree

final class CanvasCropGeometryTests: XCTestCase {
    func testSquareCropHidesOutOfFrameMetadataAndClampsZoomFocus() {
        let geometry = CanvasCropGeometry(
            sourceSize: CGSize(width: 1_600, height: 900),
            aspectRatio: .square,
            contentMode: .crop
        )

        XCTAssertFalse(geometry.containsSourcePoint(x: 0, y: 0.5))
        XCTAssertTrue(geometry.containsSourcePoint(x: 0.5, y: 0.5))
        XCTAssertEqual(
            geometry.clampedNormalizedOutputPoint(x: 0, y: 0.5).x,
            0,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            geometry.clampedNormalizedOutputPoint(x: 1, y: 0.5).x,
            1,
            accuracy: 0.000_1
        )
    }

    func testWideScreenFitsCompletelyInsideSixteenByNineCanvas() {
        let geometry = CanvasCropGeometry(
            sourceSize: CGSize(width: 3_440, height: 1_440),
            aspectRatio: .landscape16x9,
            contentMode: .fit
        )

        XCTAssertEqual(
            geometry.renderSize.width / geometry.renderSize.height,
            16.0 / 9.0,
            accuracy: 0.001
        )
        XCTAssertTrue(geometry.containsSourcePoint(x: 0, y: 0.5))
        XCTAssertTrue(geometry.containsSourcePoint(x: 1, y: 0.5))
        XCTAssertGreaterThan(geometry.offset.y, 0)
        XCTAssertEqual(geometry.offset.x, 0, accuracy: 0.001)
    }

    func testWideScreenCropStillAvailableExplicitly() {
        let geometry = CanvasCropGeometry(
            sourceSize: CGSize(width: 3_440, height: 1_440),
            aspectRatio: .landscape16x9,
            contentMode: .crop
        )

        XCTAssertFalse(geometry.containsSourcePoint(x: 0, y: 0.5))
        XCTAssertTrue(geometry.containsSourcePoint(x: 0.5, y: 0.5))
    }
}
