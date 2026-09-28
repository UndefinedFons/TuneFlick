import AppKit

enum GestureModifier: String, CaseIterable {
    case control
    case option
    case command
    case shift

    var title: String {
        switch self {
        case .control:
            return "Control"
        case .option:
            return "Option"
        case .command:
            return "Command"
        case .shift:
            return "Shift"
        }
    }

    var shortcutTitle: String {
        switch self {
        case .control:
            return "⌃ Control"
        case .option:
            return "⌥ Option"
        case .command:
            return "⌘ Command"
        case .shift:
            return "⇧ Shift"
        }
    }

    var modifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .control:
            return .control
        case .option:
            return .option
        case .command:
            return .command
        case .shift:
            return .shift
        }
    }
}

final class GesturePreferences {
    private enum Key {
        static let gesturesEnabled = "gesturesEnabled"
        static let backgroundModifier = "backgroundModifier"
        static let reverseSwipe = "reverseSwipe"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var gesturesEnabled: Bool {
        get {
            guard defaults.object(forKey: Key.gesturesEnabled) != nil else { return true }
            return defaults.bool(forKey: Key.gesturesEnabled)
        }
        set {
            defaults.set(newValue, forKey: Key.gesturesEnabled)
        }
    }

    var backgroundModifier: GestureModifier {
        get {
            guard let rawValue = defaults.string(forKey: Key.backgroundModifier),
                  let modifier = GestureModifier(rawValue: rawValue) else {
                return .control
            }
            return modifier
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.backgroundModifier)
        }
    }

    var reverseSwipe: Bool {
        get { defaults.bool(forKey: Key.reverseSwipe) }
        set { defaults.set(newValue, forKey: Key.reverseSwipe) }
    }
}
