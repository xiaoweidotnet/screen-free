import XCTest
@testable import ScreenFree

@MainActor
final class LocalizationTests: XCTestCase {
    func testDynamicStatusesAndErrorsFollowSelectedLanguage() {
        let defaults = UserDefaults.standard
        let previousLanguage = defaults.string(forKey: "appLanguage")
        defer {
            if let previousLanguage {
                defaults.set(previousLanguage, forKey: "appLanguage")
            } else {
                defaults.removeObject(forKey: "appLanguage")
            }
        }

        let store = EditorStore()
        store.appLanguage = .simplifiedChinese

        store.statusMessage = "Exported Demo.mp4"
        XCTAssertEqual(store.localizedStatusMessage, "已导出 Demo.mp4")

        store.statusMessage = "Generated 3 cursor-focused zooms."
        XCTAssertEqual(store.localizedStatusMessage, "已生成 3 个鼠标聚焦缩放。")

        store.statusMessage = "Added background music Theme.m4a"
        XCTAssertEqual(store.localizedStatusMessage, "已添加背景音乐 Theme.m4a")

        store.statusMessage = "Applied preset Vibrant"
        XCTAssertEqual(store.localizedStatusMessage, "已应用预设 鲜明")

        store.statusMessage = "Saved original recording Demo.mp4"
        XCTAssertEqual(
            store.localizedStatusMessage,
            "已保存原始录制 Demo.mp4"
        )

        store.errorMessage = "Video export failed."
        XCTAssertEqual(store.localizedErrorMessage, "视频导出失败。")

        store.errorMessage =
            "The selected background music does not contain a usable audio track."
        XCTAssertEqual(
            store.localizedErrorMessage,
            "所选背景音乐不包含可用的音频轨道。"
        )

        XCTAssertEqual(
            L10n.text(
                "Edited clip %d",
                language: .simplifiedChinese,
                2
            ),
            "已剪辑片段 2"
        )
        XCTAssertEqual(
            L10n.text(
                "Recording history",
                language: .simplifiedChinese
            ),
            "录制历史"
        )
        XCTAssertEqual(
            L10n.text(
                "Editable cursor data is unavailable for this recording. The original pointer positions cannot be reconstructed.",
                language: .simplifiedChinese
            ),
            "这段录像的可编辑鼠标轨迹已不可用，无法重建原始鼠标位置。"
        )

        XCTAssertEqual(store.localizedTimelineSummary, "0 个片段 · 0 个缩放")
    }
}
