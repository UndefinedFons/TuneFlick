import AppKit
import QuartzCore

// Build with SwipeDirection.swift, FeedbackWindowAnimation.swift, and SwipeFeedbackController.swift.
// This never sends media commands.
@main
struct FeedbackVerification {
    private struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    private static func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(description: message) }
    }

    private static func runLoop(for seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    static func main() {
        do {
            let application = NSApplication.shared
            application.setActivationPolicy(.prohibited)
            let previouslyFocused = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main!
            let controller = SwipeFeedbackController()
            if CommandLine.arguments.contains("--preview") {
                let backdrop = NSPanel(
                    contentRect: NSRect(x: screen.visibleFrame.midX - 132, y: screen.visibleFrame.midY - 76,
                                        width: 264, height: 152),
                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
                )
                backdrop.level = .floating
                backdrop.ignoresMouseEvents = true
                backdrop.hasShadow = false
                backdrop.hidesOnDeactivate = false
                backdrop.backgroundColor = NSColor(white: 0.94, alpha: 1)
                for x in stride(from: 24, to: 264, by: 36) {
                    let stripe = NSView(frame: NSRect(x: x, y: 0, width: 8, height: 152))
                    stripe.wantsLayer = true
                    stripe.layer?.backgroundColor = NSColor.gray.withAlphaComponent(0.4).cgColor
                    backdrop.contentView?.addSubview(stripe)
                }
                backdrop.orderFrontRegardless()
                let top = NSScreen.screens.first!.frame.maxY - backdrop.frame.maxY
                print("CAPTURE_RECT=\(Int(backdrop.frame.minX)),\(Int(top)),264,152")
                fflush(stdout)
                runLoop(for: 2.5)
                controller.show(direction: .right, action: .right)
                runLoop(for: 1.4)
                backdrop.backgroundColor = NSColor(white: 0.14, alpha: 1)
                controller.show(direction: .left, action: .left)
                runLoop(for: 1.4)
                runLoop(for: 2)
                backdrop.orderOut(nil)
                return
            }
            controller.show(direction: .right, action: .right)
            guard let panel = application.windows.first(where: { $0 is NSPanel }) as? NSPanel,
                  let layer = panel.contentView?.layer else {
                throw Failure(description: "Feedback panel was not created")
            }
            try check(panel.ignoresMouseEvents && !panel.isKeyWindow, "Feedback captures clicks or focus")
            try check(!panel.isOpaque && panel.backgroundColor.alphaComponent == 0 && !layer.masksToBounds,
                      "Feedback has an opaque or clipping container")
            guard let glass = panel.contentView?.subviews.compactMap({ $0 as? NSVisualEffectView }).first else {
                throw Failure(description: "Feedback has no native glass background")
            }
            try check(glass.material == .hudWindow && glass.blendingMode == .behindWindow && glass.state == .active,
                      "Glass is not using the native active HUD backdrop")
            try check(glass.maskImage != nil && glass.layer?.cornerRadius == glass.frame.height / 2,
                      "Glass corners are not rounded")

            let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            if reducedMotion {
                try check(panel.alphaValue == 1 && abs(panel.frame.midY - screen.visibleFrame.midY) <= 0.5,
                          "Reduced motion still animates")
                runLoop(for: 0.45)
                try check(panel.isVisible, "Feedback does not hold long enough")
                controller.show(direction: .left, action: .left)
                runLoop(for: 0.25)
                try check(panel.isVisible, "Previous dismissal closed repeated feedback")
                runLoop(for: 0.45)
            } else {
                runLoop(for: 0.06)
                let enteringOpacity = panel.alphaValue
                try check(enteringOpacity > 0 && enteringOpacity < 1, "Entrance does not fade gradually")
                try check(panel.frame.midY < screen.visibleFrame.midY - 0.5,
                          "Entrance has no actual window movement")
                runLoop(for: 0.26)
                try check(abs(panel.alphaValue - 1) < 0.01, "Entrance did not settle")
                try check(abs(panel.frame.midX - screen.visibleFrame.midX) <= 0.5 &&
                          abs(panel.frame.midY - screen.visibleFrame.midY) <= 0.5,
                          "Feedback is not centered: panel=\(panel.frame), screen=\(screen.visibleFrame)")
                runLoop(for: 0.32)
                try check(panel.isVisible && panel.alphaValue > 0.9, "Feedback does not hold long enough")

                let beforeRepeat = panel.alphaValue
                controller.show(direction: .left, action: .left)
                try check(abs(panel.alphaValue - beforeRepeat) < 0.03, "Repeated feedback restarts from transparent")
                runLoop(for: 0.5)
                try check(panel.isVisible && panel.alphaValue > 0.9,
                          "Previous dismissal closed repeated feedback")
                runLoop(for: 0.45)
                let exitingOpacity = panel.alphaValue
                try check(exitingOpacity > 0 && exitingOpacity < 1, "Exit does not fade gradually")
                try check(abs(panel.frame.midX - screen.visibleFrame.midX) <= 0.5, "Feedback slides in from a side")

                let exitingOrigin = panel.frame.origin
                controller.show(direction: .right, action: .right)
                try check(abs(panel.alphaValue - exitingOpacity) < 0.04 && panel.frame.origin == exitingOrigin,
                          "Interrupted exit jumps instead of continuing")
                runLoop(for: 0.3)
                try check(panel.isVisible && panel.alphaValue > 0.9,
                          "Old exit completion hid the new feedback")
                runLoop(for: 0.85)
            }

            try check(!panel.isVisible, "Feedback did not dismiss")
            try check(NSWorkspace.shared.frontmostApplication?.processIdentifier == previouslyFocused,
                      "Feedback changed the focused app")
            print("PASS: centered, native rounded glass, click-through, window lift/fade, shorter hold, repeat continuity, exit interruption, dismissal, focus unchanged (reduced motion: \(reducedMotion))")
        } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }
}
