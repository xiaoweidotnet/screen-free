import XCTest
@testable import ScreenFree

@MainActor
final class StylePresetTests: XCTestCase {
    func testFixedAspectRatioSelectionUsesEdgeToEdgeCrop() {
        let store = EditorStore()
        store.canvasPadding = 32
        store.cornerRadius = 18
        store.shadowStrength = 0.7
        store.canvasContentMode = .fit

        store.selectCanvasAspectRatio(.landscape16x9)

        XCTAssertEqual(store.canvasAspectRatio, .landscape16x9)
        XCTAssertEqual(store.canvasContentMode, .crop)
        XCTAssertEqual(store.canvasPadding, 0)
        XCTAssertEqual(store.cornerRadius, 0)
        XCTAssertEqual(store.shadowStrength, 0)
    }

    func testPresetRoundTripVersionValidationAndApplication() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = EditorStore()
        store.applyStylePreset(BuiltInStylePreset.vibrant.preset)
        let captured = store.currentStylePreset(name: "Launch")
        var expected = BuiltInStylePreset.vibrant.preset
        expected.name = "Launch"
        XCTAssertEqual(captured, expected)
        XCTAssertEqual(captured.cursorLoopToStart, true)
        XCTAssertEqual(captured.removeCursorShakes, true)
        XCTAssertEqual(captured.optimizeRapidCursorChanges, true)
        XCTAssertEqual(captured.smoothCursorMovement, true)
        XCTAssertEqual(captured.cursorReplacement, .pointer)
        XCTAssertEqual(captured.zoomCustomTransitionDuration, 0.28)
        XCTAssertEqual(captured.zoomCustomX1, 0.16)
        XCTAssertEqual(captured.zoomCustomY2, 1)
        XCTAssertEqual(captured.wallpaperPreset, .candy)
        XCTAssertEqual(captured.backgroundMode, .wallpaper)
        XCTAssertEqual(captured.motionBlurEnabled, true)
        XCTAssertEqual(captured.motionBlurStrength, 0.58)
        XCTAssertEqual(captured.cursorMotionBlur, 0.72)
        XCTAssertEqual(captured.zoomMotionBlur, 0.62)
        XCTAssertEqual(captured.panMotionBlur, 0.48)
        store.wallpaperPreset = .aurora
        store.randomizeWallpaper()
        XCTAssertNotEqual(store.wallpaperPreset, .aurora)
        XCTAssertEqual(store.backgroundMode, .wallpaper)
        store.applyStylePreset(captured)

        let url = directory.appendingPathComponent(
            "Launch.screenfreepreset"
        )
        let persistence = StylePresetPersistence()
        try persistence.save(captured, to: url)
        XCTAssertEqual(try persistence.load(from: url), captured)

        let encoded = try JSONEncoder().encode(captured)
        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "cursorLoopToStart")
        legacyObject.removeValue(forKey: "removeCursorShakes")
        legacyObject.removeValue(forKey: "cursorShakeThreshold")
        legacyObject.removeValue(forKey: "optimizeRapidCursorChanges")
        legacyObject.removeValue(forKey: "smoothCursorMovement")
        legacyObject.removeValue(forKey: "cursorReplacement")
        legacyObject.removeValue(forKey: "zoomCustomTransitionDuration")
        legacyObject.removeValue(forKey: "zoomCustomX1")
        legacyObject.removeValue(forKey: "zoomCustomY1")
        legacyObject.removeValue(forKey: "zoomCustomX2")
        legacyObject.removeValue(forKey: "zoomCustomY2")
        legacyObject.removeValue(forKey: "wallpaperPreset")
        legacyObject.removeValue(forKey: "motionBlurEnabled")
        legacyObject.removeValue(forKey: "motionBlurStrength")
        legacyObject.removeValue(forKey: "cursorMotionBlur")
        legacyObject.removeValue(forKey: "zoomMotionBlur")
        legacyObject.removeValue(forKey: "panMotionBlur")
        try JSONSerialization.data(
            withJSONObject: legacyObject
        ).write(to: url)
        let legacy = try persistence.load(from: url)
        XCTAssertNil(legacy.cursorLoopToStart)
        XCTAssertNil(legacy.removeCursorShakes)
        XCTAssertNil(legacy.cursorShakeThreshold)
        XCTAssertNil(legacy.optimizeRapidCursorChanges)
        XCTAssertNil(legacy.smoothCursorMovement)
        XCTAssertNil(legacy.cursorReplacement)
        XCTAssertNil(legacy.zoomCustomTransitionDuration)
        XCTAssertNil(legacy.zoomCustomX1)
        XCTAssertNil(legacy.zoomCustomY1)
        XCTAssertNil(legacy.zoomCustomX2)
        XCTAssertNil(legacy.zoomCustomY2)
        XCTAssertNil(legacy.wallpaperPreset)
        XCTAssertNil(legacy.motionBlurEnabled)
        XCTAssertNil(legacy.motionBlurStrength)
        XCTAssertNil(legacy.cursorMotionBlur)
        XCTAssertNil(legacy.zoomMotionBlur)
        XCTAssertNil(legacy.panMotionBlur)
        store.cursorLoopToStart = true
        store.removeCursorShakes = true
        store.optimizeRapidCursorChanges = true
        store.smoothCursorMovement = true
        store.cursorReplacement = .pointer
        store.motionBlurEnabled = true
        store.applyStylePreset(legacy)
        XCTAssertFalse(store.cursorLoopToStart)
        XCTAssertFalse(store.removeCursorShakes)
        XCTAssertFalse(store.optimizeRapidCursorChanges)
        XCTAssertFalse(store.smoothCursorMovement)
        XCTAssertEqual(store.cursorReplacement, .arrow)
        XCTAssertFalse(store.motionBlurEnabled)

        var unsupported = captured
        unsupported.version = ScreenFreeStylePreset.currentVersion + 1
        try persistence.save(unsupported, to: url)
        XCTAssertThrowsError(try persistence.load(from: url)) { error in
            XCTAssertTrue(error is StylePresetError)
        }

        var missingImage = captured
        missingImage.backgroundMode = .image
        missingImage.backgroundImagePath = directory
            .appendingPathComponent("missing.png")
            .path
        store.applyStylePreset(missingImage)
        XCTAssertEqual(store.backgroundMode, .gradient)
        XCTAssertNil(store.backgroundImageURL)
    }
}
