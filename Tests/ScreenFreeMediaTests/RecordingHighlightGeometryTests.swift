import AppKit
import CoreGraphics
import XCTest
@testable import ScreenFree

final class RecordingHighlightGeometryTests: XCTestCase {
    func testQuartzFramesMapAcrossMultiDisplayDesktop() {
        let primary = RecordingHighlightGeometry.appKitFrame(
            forQuartzFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            mainDisplayHeight: 1080
        )
        XCTAssertEqual(primary, CGRect(x: 0, y: 0, width: 1920, height: 1080))

        let tallerRightDisplay = RecordingHighlightGeometry.appKitFrame(
            forQuartzFrame: CGRect(
                x: 1920,
                y: 0,
                width: 2560,
                height: 1440
            ),
            mainDisplayHeight: 1080
        )
        XCTAssertEqual(
            tallerRightDisplay,
            CGRect(x: 1920, y: -360, width: 2560, height: 1440)
        )

        let displayAbove = RecordingHighlightGeometry.appKitFrame(
            forQuartzFrame: CGRect(
                x: 0,
                y: -900,
                width: 1440,
                height: 900
            ),
            mainDisplayHeight: 1080
        )
        XCTAssertEqual(
            displayAbove,
            CGRect(x: 0, y: 1080, width: 1440, height: 900)
        )
    }

    func testDockPresentationRestoresThePreviousApplicationPolicy() {
        var presentation = RecordingApplicationPresentation()
        XCTAssertEqual(
            presentation.begin(
                currentPolicy: .regular,
                hideDockIcon: true
            ),
            .accessory
        )
        XCTAssertTrue(presentation.isPresenting)
        XCTAssertNil(
            presentation.begin(
                currentPolicy: .regular,
                hideDockIcon: true
            )
        )
        XCTAssertEqual(presentation.finish(), .regular)
        XCTAssertFalse(presentation.isPresenting)
        XCTAssertNil(presentation.finish())

        XCTAssertNil(
            presentation.begin(
                currentPolicy: .regular,
                hideDockIcon: false
            )
        )
        XCTAssertNil(presentation.finish())
        XCTAssertFalse(presentation.isPresenting)

        XCTAssertNil(
            presentation.begin(
                currentPolicy: .accessory,
                hideDockIcon: true
            )
        )
        XCTAssertNil(presentation.finish())
    }

    func testTeleprompterVisibilityAndDisplayPlacement() {
        XCTAssertFalse(
            RecordingTeleprompterPresentation.shouldShow(text: " \n ")
        )
        XCTAssertTrue(
            RecordingTeleprompterPresentation.shouldShow(text: "Present this")
        )

        let frame = RecordingTeleprompterPresentation.frame(
            in: CGRect(
                x: 1920,
                y: -360,
                width: 2560,
                height: 1400
            ),
            size: CGSize(width: 560, height: 170)
        )
        XCTAssertEqual(
            frame,
            CGRect(
                x: 2920,
                y: -336,
                width: 560,
                height: 170
            )
        )
    }

    func testTeleprompterPanelSizeClamping() {
        XCTAssertEqual(
            RecordingTeleprompterPresentation.clamped(
                size: CGSize(width: 200, height: 80)
            ),
            CGSize(width: 320, height: 120)
        )
        XCTAssertEqual(
            RecordingTeleprompterPresentation.clamped(
                size: CGSize(width: 2000, height: 900)
            ),
            CGSize(width: 1000, height: 600)
        )
        XCTAssertEqual(
            RecordingTeleprompterPresentation.clamped(
                size: CGSize(width: 700, height: 300)
            ),
            CGSize(width: 700, height: 300)
        )
    }

    func testTeleprompterSavedOriginIsUsedAndClampedToVisibleFrame() {
        let visible = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        let kept = RecordingTeleprompterPresentation.frame(
            in: visible,
            size: CGSize(width: 560, height: 190),
            savedOrigin: CGPoint(x: 100, y: 200)
        )
        XCTAssertEqual(kept.origin, CGPoint(x: 100, y: 200))
        XCTAssertEqual(kept.size, CGSize(width: 560, height: 190))

        let small = CGRect(x: 0, y: 0, width: 800, height: 600)
        let clampedFrame = RecordingTeleprompterPresentation.frame(
            in: small,
            size: CGSize(width: 560, height: 190),
            savedOrigin: CGPoint(x: 1500, y: 900)
        )
        XCTAssertEqual(
            clampedFrame.origin,
            CGPoint(x: 800 - 560, y: 600 - 190)
        )

        let negativeScreen = CGRect(x: 1920, y: -360, width: 2560, height: 1400)
        let clampedNegative = RecordingTeleprompterPresentation.frame(
            in: negativeScreen,
            size: CGSize(width: 560, height: 190),
            savedOrigin: CGPoint(x: -500, y: -900)
        )
        XCTAssertEqual(clampedNegative.origin, CGPoint(x: 1920, y: -360))

        var desktopPresentation = RecordingDesktopIconPresentation()
        let inheritedVisible = DesktopIconPreferenceSnapshot(
            hadExplicitValue: false,
            iconsVisible: true
        )
        XCTAssertTrue(
            desktopPresentation.begin(
                currentPreference: inheritedVisible,
                hideDesktopIcons: true
            )
        )
        XCTAssertFalse(
            desktopPresentation.begin(
                currentPreference: inheritedVisible,
                hideDesktopIcons: true
            )
        )
        XCTAssertEqual(
            desktopPresentation.finish(),
            inheritedVisible
        )
        XCTAssertNil(desktopPresentation.finish())

        let alreadyHidden = DesktopIconPreferenceSnapshot(
            hadExplicitValue: true,
            iconsVisible: false
        )
        XCTAssertFalse(
            desktopPresentation.begin(
                currentPreference: alreadyHidden,
                hideDesktopIcons: true
            )
        )
        XCTAssertNil(desktopPresentation.finish())
        XCTAssertFalse(
            desktopPresentation.begin(
                currentPreference: inheritedVisible,
                hideDesktopIcons: false
            )
        )
        XCTAssertNil(desktopPresentation.finish())

        XCTAssertFalse(
            RecordingCameraPreviewPresentation.shouldShow(
                cameraSelected: false,
                hidden: false
            )
        )
        XCTAssertFalse(
            RecordingCameraPreviewPresentation.shouldShow(
                cameraSelected: true,
                hidden: true
            )
        )
        XCTAssertTrue(
            RecordingCameraPreviewPresentation.shouldShow(
                cameraSelected: true,
                hidden: false
            )
        )
    }

    func testCountdownIsLargeAndCenteredOnTheRecordingDisplay() {
        XCTAssertFalse(
            RecordingCountdownPresentation.shouldShow(remaining: 0)
        )
        XCTAssertTrue(
            RecordingCountdownPresentation.shouldShow(remaining: 3)
        )
        XCTAssertGreaterThanOrEqual(
            RecordingCountdownPresentation.panelSize.height,
            260
        )
        XCTAssertEqual(
            RecordingCountdownPresentation.frame(
                in: CGRect(x: 1920, y: -360, width: 2560, height: 1440)
            ),
            CGRect(x: 3040, y: 220, width: 320, height: 280)
        )
    }
}
