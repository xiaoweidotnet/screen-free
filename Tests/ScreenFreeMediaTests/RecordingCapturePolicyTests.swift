import XCTest
@testable import ScreenFree

final class RecordingCapturePolicyTests: XCTestCase {
    func testSelectedWindowRemainsDiscoverableAfterCountdown() {
        XCTAssertFalse(
            CaptureContentVisibilityPolicy.onScreenWindowsOnly(for: .window),
            "A selected window may become occluded while the recording controller replaces the editor."
        )
        XCTAssertTrue(
            CaptureContentVisibilityPolicy.onScreenWindowsOnly(for: .display)
        )
        XCTAssertTrue(
            CaptureContentVisibilityPolicy.onScreenWindowsOnly(for: .area)
        )
    }
}
