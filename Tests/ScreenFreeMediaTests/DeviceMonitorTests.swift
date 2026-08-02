import XCTest
@testable import ScreenFree

@MainActor
final class DeviceMonitorTests: XCTestCase {
    func testCameraRecordingFailsWhenPreviewIsNotReady() {
        let monitor = DeviceMonitor()

        XCTAssertThrowsError(try monitor.startCameraRecording()) { error in
            XCTAssertEqual(
                error.localizedDescription,
                DeviceMonitorError.cameraNotReady.localizedDescription
            )
        }
    }
}
