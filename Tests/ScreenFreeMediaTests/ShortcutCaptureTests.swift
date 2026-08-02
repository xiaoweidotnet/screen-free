import AppKit
import XCTest
@testable import ScreenFree

final class ShortcutCaptureTests: XCTestCase {
    func testFormatterRejectsTypingAndKeepsOnlyModifiedShortcuts() {
        XCTAssertNil(
            ShortcutLabelFormatter.label(
                keyCode: 0,
                characters: "a",
                modifiers: []
            )
        )
        XCTAssertNil(
            ShortcutLabelFormatter.label(
                keyCode: 0,
                characters: "a",
                modifiers: [.shift]
            )
        )
        XCTAssertEqual(
            ShortcutLabelFormatter.label(
                keyCode: 40,
                characters: "k",
                modifiers: [.command]
            ),
            "⌘K"
        )
        XCTAssertEqual(
            ShortcutLabelFormatter.label(
                keyCode: 123,
                characters: nil,
                modifiers: [.control, .option, .shift]
            ),
            "⌃⌥⇧←"
        )
    }
}
