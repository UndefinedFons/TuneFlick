import Foundation

enum SwipeDirection {
    case left
    case right

    var opposite: SwipeDirection {
        switch self {
        case .left:
            return .right
        case .right:
            return .left
        }
    }

    var actionLabel: String {
        switch self {
        case .left:
            return "上一首"
        case .right:
            return "下一首"
        }
    }
}
