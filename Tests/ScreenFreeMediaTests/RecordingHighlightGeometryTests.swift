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

    func testSpeakerNotesVisibilityAndDisplayPlacement() {
        XCTAssertFalse(
            RecordingSpeakerNotesPresentation.shouldShow(
                enabled: false,
                text: "Present this"
            )
        )
        XCTAssertFalse(
            RecordingSpeakerNotesPresentation.shouldShow(
                enabled: true,
                text: " \n "
            )
        )
        XCTAssertTrue(
            RecordingSpeakerNotesPresentation.shouldShow(
                enabled: true,
                text: "Present this"
            )
        )

        let frame = RecordingSpeakerNotesPresentation.frame(
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
