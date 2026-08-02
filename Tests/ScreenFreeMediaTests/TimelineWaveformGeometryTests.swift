import CoreGraphics
import ScreenFreeCore
import XCTest
@testable import ScreenFree

final class TimelineWaveformGeometryTests: XCTestCase {
    func testMissingWaveformProducesNoBaseline() {
        let bars = TimelineWaveformGeometry.bars(
            samples: [],
            sourceDuration: 4,
            clip: TimelineClip(sourceStart: 0, duration: 4),
            canvasSize: CGSize(width: 100, height: 40)
        )

        XCTAssertTrue(bars.isEmpty)
    }

    func testSilentClipProducesNoWaveformBars() {
        let bars = TimelineWaveformGeometry.bars(
            samples: [0, 0, 0, 0],
            sourceDuration: 4,
            clip: TimelineClip(sourceStart: 0, duration: 4),
            canvasSize: CGSize(width: 100, height: 40)
        )

        XCTAssertTrue(bars.isEmpty)
    }

    func testTrimmedClipUsesItsSourceRangeAndPreservesLevelDifferences() {
        let bars = TimelineWaveformGeometry.bars(
            samples: [0, 0, 0, 0, 0.25, 1, 0, 0],
            sourceDuration: 8,
            clip: TimelineClip(sourceStart: 4, duration: 2),
            canvasSize: CGSize(width: 10, height: 20)
        )

        XCTAssertEqual(bars.count, 2)
        guard bars.count == 2 else { return }
        XCTAssertEqual(bars[0].x, 2.5, accuracy: 0.001)
        XCTAssertEqual(bars[1].x, 7.5, accuracy: 0.001)
        XCTAssertGreaterThan(bars[1].halfHeight, bars[0].halfHeight)
    }
}
