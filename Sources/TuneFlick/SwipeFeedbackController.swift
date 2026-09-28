import AppKit
import QuartzCore

/// A mouse-transparent HUD, never a key window or an activating panel.
final class SwipeFeedbackController {
    private enum Timing {
        static let entrance: TimeInterval = 0.24
        static let hold: TimeInterval = 0.65
        static let exit: TimeInterval = 0.18
    }

    private let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: 224, height: 104),
        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
    )
    private let symbol = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var dismissal: DispatchWorkItem?
    private var transition: FeedbackWindowAnimation?
    private var restingOrigin = NSPoint.zero
    private var generation = 0

    init() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let hostView = NSView(frame: panel.contentView!.bounds)
        hostView.wantsLayer = true
        panel.contentView = hostView

        let glassSize = NSSize(width: 144, height: 48)
        let glass = NSVisualEffectView(frame: NSRect(origin: .zero, size: glassSize))
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.appearance = NSAppearance(named: .vibrantDark)
        glass.wantsLayer = true
        glass.layer?.cornerRadius = glassSize.height / 2
        glass.layer?.masksToBounds = true
        // Mask the native backdrop as well as its contents, leaving the outer animation canvas clear.
        glass.maskImage = NSImage(size: glassSize, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 24, yRadius: 24).fill()
            return true
        }
        glass.translatesAutoresizingMaskIntoConstraints = false
        hostView.addSubview(glass)

        symbol.contentTintColor = .labelColor
        symbol.widthAnchor.constraint(equalToConstant: 16).isActive = true
        symbol.heightAnchor.constraint(equalToConstant: 16).isActive = true
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .labelColor
        let indicator = NSStackView(views: [symbol, label])
        indicator.spacing = 8
        indicator.alignment = .centerY
        indicator.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(indicator)
        NSLayoutConstraint.activate([
            glass.widthAnchor.constraint(equalToConstant: glassSize.width),
            glass.heightAnchor.constraint(equalToConstant: glassSize.height),
            glass.centerXAnchor.constraint(equalTo: hostView.centerXAnchor),
            glass.centerYAnchor.constraint(equalTo: hostView.centerYAnchor),
            indicator.centerXAnchor.constraint(equalTo: glass.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: glass.centerYAnchor)
        ])
    }

    deinit {
        transition?.stop()
        dismissal?.cancel()
    }

    func show(direction: SwipeDirection, action: SwipeDirection) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        dismissal?.cancel()
        transition?.stop()
        generation += 1
        let currentGeneration = generation
        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        label.stringValue = action.actionLabel
        symbol.image = NSImage(systemSymbolName: action == .left ? "backward.end.fill" : "forward.end.fill",
                               accessibilityDescription: action.actionLabel)
        restingOrigin = NSPoint(
            x: screen.visibleFrame.midX - panel.frame.width / 2,
            y: screen.visibleFrame.midY - panel.frame.height / 2
        )
        if !panel.isVisible || !screen.frame.contains(NSPoint(x: panel.frame.midX, y: panel.frame.midY)) {
            panel.alphaValue = 0
            panel.setFrameOrigin(NSPoint(x: restingOrigin.x, y: restingOrigin.y - (reducedMotion ? 0 : 18)))
        }
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.orderFrontRegardless()
        let entranceDuration = reducedMotion ? 0 : Timing.entrance
        animateWindow(
            opacity: 1,
            offset: 0,
            duration: entranceDuration,
            curve: .easeOut
        )
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == currentGeneration else { return }
            let exitDuration = reducedMotion ? 0 : Timing.exit
            self.animateWindow(
                opacity: 0,
                offset: reducedMotion ? 0 : 8,
                duration: exitDuration,
                curve: .easeInOut
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + exitDuration) { [weak self] in
                guard let self, self.generation == currentGeneration else { return }
                self.panel.orderOut(nil)
            }
        }
        dismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + entranceDuration + Timing.hold, execute: work)
    }

    private func animateWindow(opacity: CGFloat, offset: CGFloat, duration: TimeInterval, curve: NSAnimation.Curve) {
        let initialOpacity = panel.alphaValue
        let initialOrigin = panel.frame.origin
        let targetOrigin = NSPoint(x: restingOrigin.x, y: restingOrigin.y + offset)
        transition?.stop()
        // Retarget from the actual window state, including a partially completed exit.
        let update: (CGFloat) -> Void = { [weak self] progress in
            guard let self else { return }
            self.panel.alphaValue = initialOpacity + (opacity - initialOpacity) * progress
            self.panel.setFrameOrigin(NSPoint(
                x: initialOrigin.x + (targetOrigin.x - initialOrigin.x) * progress,
                y: initialOrigin.y + (targetOrigin.y - initialOrigin.y) * progress
            ))
        }
        guard duration > 0 else { update(1); return }
        let animation = FeedbackWindowAnimation(duration: duration, curve: curve, update: update)
        transition = animation
        animation.start()
    }
}
