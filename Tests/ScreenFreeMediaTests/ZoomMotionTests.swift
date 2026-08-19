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

    func testSubframeGapBetweenAdjacentZoomsNeverReturnsToIdentity() throws {
        let first = ZoomEvent(
            start: 1,
            duration: 2,
            scale: 1.8,
            focusX: 0.3,
            focusY: 0.4
        )
        let second = ZoomEvent(
            start: 3 + 1.0 / 240.0,
            duration: 2,
            scale: 1.8,
            focusX: 0.7,
            focusY: 0.6
        )

        let state = try XCTUnwrap(
            ZoomMotionResolver.state(
                at: 3 + 1.0 / 480.0,
                zooms: [first, second],
                totalDuration: 6,
                motion: .mellow
            ),
            "A visually adjacent subframe gap must be bridged as one continuous zoom."
        )

        XCTAssertGreaterThanOrEqual(state.scale, 1.79)
    }

    func testFollowCursorZoomDampsRapidPointerMovement() throws {
        let zoom = ZoomEvent(
            start: 0,
            duration: 3,
            scale: 1.8,
            focusX: 0.1,
            focusY: 0.5,
            followsCursor: true
        )
        let project = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 3)],
            zooms: [zoom],
            cursorSamples: [
                CursorSample(time: 0, normalizedX: 0.1, normalizedY: 0.5),
                CursorSample(time: 1, normalizedX: 0.1, normalizedY: 0.5),
                CursorSample(time: 1.033, normalizedX: 0.9, normalizedY: 0.5),
                CursorSample(time: 1.066, normalizedX: 0.9, normalizedY: 0.5),
                CursorSample(time: 1.6, normalizedX: 0.9, normalizedY: 0.5),
                CursorSample(time: 2.2, normalizedX: 0.9, normalizedY: 0.5)
            ]
        )

        let before = try focus(at: 1, project: project)
        let immediatelyAfter = try focus(
            at: 1.033,
            project: project
        )
        let settled = try focus(at: 1.8, project: project)

        XCTAssertLessThan(
            abs(immediatelyAfter.x - before.x),
            0.2,
            "A one-frame pointer jump must not throw the zoomed canvas across the screen."
        )
        XCTAssertGreaterThan(
            settled.x,
            0.7,
            "The camera should still follow a sustained intentional move."
        )
    }

    func testFollowCursorZoomSmoothsContinuousJitteryMovement() throws {
        let zoom = ZoomEvent(
            start: 0,
            duration: 4,
            scale: 1.8,
            focusX: 0.4,
            focusY: 0.5,
            followsCursor: true
        )
        // 0.2s 周期、±0.1 的三角波抖动：速度低于急变优化阈值、不构成
        // 可剔除的尖峰，会原样穿过光标预处理——正是"鼠标持续滑动时
        // 画面晃来晃去"的激励形态。
        var samples: [CursorSample] = []
        for index in 0..<120 {
            let time = Double(index) / 30.0
            let phase = (time.truncatingRemainder(dividingBy: 0.2)) / 0.2
            let triangle = 4 * abs(phase - 0.5) - 1
            samples.append(
                CursorSample(
                    time: time,
                    normalizedX: 0.4 + 0.1 * triangle,
                    normalizedY: 0.5
                )
            )
        }
        let project = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 4)],
            zooms: [zoom],
            cursorSamples: samples
        )

        var previous = try focus(at: 1.0, project: project)
        var maxFocusDelta: CGFloat = 0
        for step in 1...30 {
            let time = 1.0 + Double(step) / 30.0
            let current = try focus(at: time, project: project)
            maxFocusDelta = max(maxFocusDelta, abs(current.x - previous.x))
            previous = current
        }

        XCTAssertLessThan(
            maxFocusDelta,
            0.025,
            "The camera must low-pass continuous pointer jitter instead of passing it through as canvas wobble."
        )
        for step in 0...30 {
            let time = 1.0 + Double(step) / 30.0
            let current = try focus(at: time, project: project)
            XCTAssertTrue(
                (0.25...0.55).contains(current.x),
                "The smoothed focus must stay near the jitter corridor, not drift away."
            )
        }
    }

    func testAdjacentFollowCursorZoomsShareOneStableCameraPath() throws {
        let first = ZoomEvent(
            start: 0,
            duration: 1.5,
            scale: 1.8,
            focusX: 0.2,
            focusY: 0.5,
            followsCursor: true
        )
        let second = ZoomEvent(
            start: 1.5,
            duration: 1.5,
            scale: 1.8,
            focusX: 0.8,
            focusY: 0.5,
            followsCursor: true
        )
        let project = TimelineProject(
            clips: [TimelineClip(sourceStart: 0, duration: 3)],
            zooms: [first, second],
            cursorSamples: [
                CursorSample(time: 0, normalizedX: 0.2, normalizedY: 0.5),
                CursorSample(time: 1.45, normalizedX: 0.2, normalizedY: 0.5),
                CursorSample(time: 1.5, normalizedX: 0.8, normalizedY: 0.5),
                CursorSample(time: 1.55, normalizedX: 0.8, normalizedY: 0.5),
                CursorSample(time: 2, normalizedX: 0.8, normalizedY: 0.5)
            ]
        )

        let beforeBoundary = try focus(at: 1.499, project: project)
        let afterBoundary = try focus(at: 1.501, project: project)

        XCTAssertLessThan(
            abs(afterBoundary.x - beforeBoundary.x),
            0.05,
            "An adjacent zoom block must not reset the camera-following filter."
        )
        XCTAssertGreaterThanOrEqual(
            try XCTUnwrap(
                ZoomMotionResolver.state(
                    at: 1.501,
                    zooms: project.zooms,
                    totalDuration: project.duration,
                    motion: .mellow
                )
            ).scale,
            1.79
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
        // Halfway through the 0.95 s ramp the eased progress is exactly 0.5;
        // geometric interpolation puts the scale at 2^0.5.
        XCTAssertEqual(
            try XCTUnwrap(resolve(zoom, at: 1.475, preset: .mellow)).scale,
            sqrt(2),
            accuracy: 0.02
        )
        XCTAssertEqual(
            try XCTUnwrap(resolve(zoom, at: 2, preset: .mellow)).scale,
            2,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(resolve(zoom, at: 3.525, preset: .mellow)).scale,
            sqrt(2),
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
        XCTAssertEqual(linearCustom.scale, sqrt(2), accuracy: 0.01)
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
            ),
            "A recorded click must create an automatic zoom."
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

    private func focus(
        at time: TimeInterval,
        project: TimelineProject
    ) throws -> CGPoint {
        let state = try XCTUnwrap(
            ZoomMotionResolver.state(
                at: time,
                zooms: project.zooms,
                totalDuration: project.duration,
                motion: .mellow
            )
        )
        return ZoomFocusResolver.focus(
            at: time,
            zoomState: state,
            project: project,
            cursorTailFreeze: 0,
            cursorLoopToStart: false,
            removeCursorShakes: true,
            cursorShakeThreshold: 0.012,
            optimizeRapidCursorChanges: true,
            smoothCursorMovement: true
        )
    }
}
