import AppKit

enum GestureActivationPolicy {
    static func allowsCapture(foreground: Bool, flags: NSEvent.ModifierFlags, backgroundModifier: GestureModifier) -> Bool {
        let modifiers = flags.intersection([.control, .option, .command, .shift])
        if foreground {
            // Leave multi-key shortcuts with the player rather than repurposing them for playback.
            return modifiers != backgroundModifier.modifierFlag && modifiers.rawValue.nonzeroBitCount <= 1
        }
        return modifiers == backgroundModifier.modifierFlag
    }
}
