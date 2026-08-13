import SwiftUI

/// ScreenFree's semantic workstation palette.
///
/// Keep product chrome calm and neutral. Video canvas colors remain project
/// content and intentionally do not use these tokens.
enum StudioTheme {
    static let canvas = Color(red: 0.039, green: 0.051, blue: 0.067)
    static let surface = Color(red: 0.059, green: 0.078, blue: 0.102)
    static let raisedSurface = Color(red: 0.082, green: 0.106, blue: 0.133)
    static let elevatedSurface = Color(red: 0.106, green: 0.137, blue: 0.169)

    static let border = Color(red: 0.176, green: 0.220, blue: 0.259)
    static let strongBorder = Color(red: 0.267, green: 0.337, blue: 0.392)

    static let accent = Color(red: 0.306, green: 0.494, blue: 0.616)
    static let accentBright = Color(red: 0.431, green: 0.624, blue: 0.741)
    static let accentMuted = Color(red: 0.133, green: 0.224, blue: 0.282)

    static let timelineClip = Color(red: 0.647, green: 0.427, blue: 0.200)
    static let timelineClipBright = Color(red: 0.769, green: 0.557, blue: 0.278)
    static let zoom = Color(red: 0.278, green: 0.471, blue: 0.584)
    static let playhead = Color(red: 0.455, green: 0.651, blue: 0.757)

    static let success = Color(red: 0.365, green: 0.616, blue: 0.471)
    static let warning = Color(red: 0.745, green: 0.533, blue: 0.278)
    static let danger = Color(red: 0.741, green: 0.302, blue: 0.302)

    static let accentGradient = LinearGradient(
        colors: [accentBright, accent],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let recordGradient = LinearGradient(
        colors: [danger, Color(red: 0.655, green: 0.224, blue: 0.224)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let emptyStateBackground = LinearGradient(
        colors: [raisedSurface, canvas],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    enum Radius {
        static let compact: CGFloat = 6
        static let control: CGFloat = 10
        static let panel: CGFloat = 14
    }
}
