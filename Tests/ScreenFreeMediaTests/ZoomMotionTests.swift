import XCTest
@testable import ScreenFree
import ScreenFreeCore

final class ZoomMotionTests: XCTestCase {
    func testAdjacentZoomsStayMagnifiedAcrossTheirSharedBoundary() throws {
        let first = ZoomEvent(
            start: 1,
            duration: 2,
            scale: 1.8,
            focusX: 0.3,
            focusY: 0.4
        )
        let second = ZoomEvent(
            start: 3,
            duration: 2,
            scale: 2,
            focusX: 0.7,
            focusY: 0.6
        )
        let motion = ZoomMotionStyle(preset: .mellow)

        for time in stride(from: 2.7, through: 3.3, by: 0.05) {
            let state = try XCTUnwrap(
                ZoomMotionResolver.state(
                    at: time,
                    zooms: [first, second],
                    totalDuration: 6,
                    motion: motion
                )
            )
            XCTAssertGreaterThanOrEqual(
                state.scale,
                1.79,
                "Adjacent zooms must not return to 1× at \(time)."
            )
        }

        let boundary = try XCTUnwrap(
            ZoomMotionResolver.state(
                at: 3,
                zooms: [first, second],
                totalDuration: 6,
                motion: motion
            )
        )
        XCTAssertEqual(boundary.scale, first.scale, accuracy: 0.001)
        XCTAssertEqual(boundary.zoom.focusX, first.focusX, accuracy: 0.001)
        XCTAssertEqual(boundary.zoom.focusY, first.focusY, accuracy: 0.001)

        let minimumLengthConnector = ZoomEvent(
            start: 3,
            duration: 0.1,
            scale: 1.8,
            focusX: 0.5,
            focusY: 0.5
        )
        let afterConnector = ZoomEvent(
            start: 3.1,
            duration: 1,
            scale: 1.8,
            focusX: 0.6,
            focusY: 0.5
        )
        XCTAssertGreaterThanOrEqual(
            try XCTUnwrap(
                ZoomMotionResolver.state(
                    at: 3.05,
                    zooms: [first, minimumLengthConnector, afterConnector],
                    totalDuration: 5,
                    motion: motion
                )
            ).scale,
            1.79,
            "A minimum-length zoom block must preserve a continuous chain."
        )
    }

    func testMotionPresetUsesEasedEntryHoldAndExit() throws {
        let zoom = ZoomEvent(
            start: 1,
            duration: 3,
            scale: 2,
            focusX: 0.5,
            focusY: 0.5
        )

        XCTAssertNil(resolve(zoom, at: 0.9, preset: .mellow))
        XCTAssertEqual(
            try XCTUnwrap(resolve(zoom, at: 1, preset: .mellow)).scale,
            1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(resolve(zoom, at: 1.41, preset: .mellow)).scale,
            1.5,
            accuracy: 0.02
        )
        XCTAssertEqual(
            try XCTUnwrap(resolve(zoom, at: 2, preset: .mellow)).scale,
            2,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(resolve(zoom, at: 3.59, preset: .mellow)).scale,
            1.5,
            accuracy: 0.02
        )
        XCTAssertEqual(
            try XCTUnwrap(resolve(zoom, at: 4, preset: .mellow)).scale,
            1,
            accuracy: 0.001
        )

        let rapid = try XCTUnwrap(resolve(zoom, at: 1.06, preset: .rapid))
        let mellow = try XCTUnwrap(resolve(zoom, at: 1.06, preset: .mellow))
        XCTAssertGreaterThan(rapid.scale, mellow.scale)
        XCTAssertLessThan(
            try XCTUnwrap(resolve(zoom, at: 1.2, preset: .mellow)).scale,
            1.15,
            "The default zoom should enter gently instead of snapping in."
        )
        XCTAssertLessThan(
            try XCTUnwrap(resolve(zoom, at: 3.8, preset: .mellow)).scale,
            1.15,
            "The default zoom should recover gently instead of snapping out."
        )

        let linear = CubicBezierEasing(
            x1: 0,
            y1: 0,
            x2: 1,
            y2: 1
        )
        XCTAssertEqual(linear.value(at: 0.5), 0.5, accuracy: 0.001)
        let deliberate = CubicBezierEasing(
            x1: 0.8,
            y1: 0,
            x2: 1,
            y2: 0.2
        )
        XCTAssertLessThan(deliberate.value(at: 0.5), 0.15)

        let linearCustom = try XCTUnwrap(
            ZoomMotionResolver.state(
                at: 1.3,
                zooms: [zoom],
                totalDuration: 5,
                motion: ZoomMotionStyle(
                    preset: .custom,
                    customTransitionDuration: 0.6,
                    customEasing: linear
                )
            )
        )
        XCTAssertEqual(linearCustom.scale, 1.5, accuracy: 0.01)
        let deliberateCustom = try XCTUnwrap(
            ZoomMotionResolver.state(
                at: 1.3,
                zooms: [zoom],
                totalDuration: 5,
                motion: ZoomMotionStyle(
                    preset: .custom,
                    customTransitionDuration: 0.6,
                    customEasing: deliberate
                )
            )
        )
        XCTAssertLessThan(deliberateCustom.scale, 1.15)

        let motionProject = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 1)],
            zooms: [
                ZoomEvent(
                    start: 0,
                    duration: 1,
                    scale: 2,
                    focusX: 0.8,
                    focusY: 0.35
                )
            ],
            cursorSamples: [
                CursorSample(time: 0, normalizedX: 0.1, normalizedY: 0.2),
                CursorSample(time: 0.033, normalizedX: 0.28, normalizedY: 0.34),
                CursorSample(time: 0.066, normalizedX: 0.52, normalizedY: 0.5),
                CursorSample(time: 0.1, normalizedX: 0.8, normalizedY: 0.7)
            ]
        )
        let blurStyle = MotionBlurStyle(
            enabled: true,
            strength: 1,
            cursorAmount: 1,
            zoomAmount: 1,
            panAmount: 1
        )
        let movingBlur = MotionBlurResolver.resolve(
            at: 0.1,
            project: motionProject,
            zoomMotion: .rapid,
            style: blurStyle,
            renderSize: CGSize(width: 1_920, height: 1_080),
            cursorTailFreeze: 0,
            cursorLoopToStart: false,
            removeCursorShakes: false,
            cursorShakeThreshold: 0.012,
            optimizeRapidCursorChanges: false,
            smoothCursorMovement: true
        )
        XCTAssertGreaterThan(movingBlur.screenRadius, 1)
        XCTAssertGreaterThan(movingBlur.cursorRadius, 1)
        let disabledBlur = MotionBlurResolver.resolve(
            at: 0.1,
            project: motionProject,
            zoomMotion: .rapid,
            style: .disabled,
            renderSize: CGSize(width: 1_920, height: 1_080),
            cursorTailFreeze: 0,
            cursorLoopToStart: false,
            removeCursorShakes: false,
            cursorShakeThreshold: 0.012,
            optimizeRapidCursorChanges: false,
            smoothCursorMovement: true
        )
        XCTAssertEqual(disabledBlur, .zero)
        XCTAssertTrue(
            AutomaticZoomPolicy.shouldGenerate(
                enabled: true,
                clicks: [
                    MouseClick(
                        time: 1,
                        normalizedX: 0.5,
                        normalizedY: 0.5,
                        button: .left
                    )
                ]
            )
        )
        XCTAssertFalse(
            AutomaticZoomPolicy.shouldGenerate(
                enabled: false,
                clicks: [
                    MouseClick(
                        time: 1,
                        normalizedX: 0.5,
                        normalizedY: 0.5,
                        button: .left
                    )
                ]
            )
        )
        XCTAssertFalse(
            AutomaticZoomPolicy.shouldGenerate(
                enabled: true,
                clicks: []
            )
        )
        XCTAssertFalse(
            AutomaticZoomPolicy.shouldGenerate(
                enabled: true,
                clicks: [
                    MouseClick(
                        time: 1,
                        normalizedX: 0.5,
                        normalizedY: 0.5,
                        button: .right,
                        holdDuration: 0.49
                    )
                ]
            )
        )
        XCTAssertTrue(
            AutomaticZoomPolicy.shouldGenerate(
                enabled: true,
                clicks: [
                    MouseClick(
                        time: 1,
                        normalizedX: 0.5,
                        normalizedY: 0.5,
                        button: .right,
                        holdDuration: 0.5
                    )
                ]
            )
        )
    }

    private func resolve(
        _ zoom: ZoomEvent,
        at time: TimeInterval,
        preset: ZoomMotionPreset
    ) -> ResolvedZoomMotion? {
        ZoomMotionResolver.state(
            at: time,
            zooms: [zoom],
            totalDuration: 5,
            preset: preset
        )
    }
}
