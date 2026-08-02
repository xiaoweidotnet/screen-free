import SwiftUI

enum CameraPosition: String, CaseIterable, Codable, Identifiable, Sendable {
    case topLeft = "Top left"
    case topRight = "Top right"
    case bottomLeft = "Bottom left"
    case bottomRight = "Bottom right"

    var id: Self { self }

    var alignment: Alignment {
        switch self {
        case .topLeft: return .topLeading
        case .topRight: return .topTrailing
        case .bottomLeft: return .bottomLeading
        case .bottomRight: return .bottomTrailing
        }
    }
}

struct CameraOverlayStyle: Sendable {
    var position: CameraPosition
    var sizeFraction: CGFloat
    var mirrored: Bool
    var cornerRadius: CGFloat = 18
}
