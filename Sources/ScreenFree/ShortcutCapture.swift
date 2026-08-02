import AppKit
import Foundation

enum ShortcutLabelFormatter {
    static func label(
        keyCode: UInt16,
        characters: String?,
        modifiers: NSEvent.ModifierFlags
    ) -> String? {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        let privacySafeModifiers: NSEvent.ModifierFlags = [
            .command,
            .control,
            .option
        ]
        guard !flags.intersection(privacySafeModifiers).isEmpty,
              let key = keyLabel(
                  keyCode: keyCode,
                  characters: characters
              ) else {
            return nil
        }

        var label = ""
        if flags.contains(.control) { label += "⌃" }
        if flags.contains(.option) { label += "⌥" }
        if flags.contains(.shift) { label += "⇧" }
        if flags.contains(.command) { label += "⌘" }
        return label + key
    }

    private static func keyLabel(
        keyCode: UInt16,
        characters: String?
    ) -> String? {
        let specialKeys: [UInt16: String] = [
            36: "↩",
            48: "⇥",
            49: "Space",
            51: "⌫",
            53: "Esc",
            115: "Home",
            116: "Page Up",
            117: "⌦",
            119: "End",
            121: "Page Down",
            123: "←",
            124: "→",
            125: "↓",
            126: "↑",
            122: "F1",
            120: "F2",
            99: "F3",
            118: "F4",
            96: "F5",
            97: "F6",
            98: "F7",
            100: "F8",
            101: "F9",
            109: "F10",
            103: "F11",
            111: "F12"
        ]
        if let special = specialKeys[keyCode] {
            return special
        }
        guard let characters = characters?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(),
              !characters.isEmpty,
              characters.count <= 2 else {
            return nil
        }
        return characters
    }
}
