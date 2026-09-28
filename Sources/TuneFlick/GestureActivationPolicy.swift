import AppKit

enum GestureActivationPolicy {
    static func allowsCapture(foreground: Bool, flags: NSEvent.ModifierFlags, backgroundModifier: GestureModifier) -> Bool {
        let modifiers = flags.intersection([.control, .option, .command, .shift])
        // Modified foreground gestures belong to the player; background needs exactly one selected key.
        return foreground ? modifiers.isEmpty : modifiers == backgroundModifier.modifierFlag
    }
}
