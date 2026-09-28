import AppKit

/// Drives the complete translucent window without animating AppKit-owned backing layers.
final class FeedbackWindowAnimation: NSAnimation {
    private let update: (CGFloat) -> Void

    init(duration: TimeInterval, curve: NSAnimation.Curve, update: @escaping (CGFloat) -> Void) {
        self.update = update
        super.init(duration: duration, animationCurve: curve)
        animationBlockingMode = .nonblocking
        frameRate = 60
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override var currentProgress: NSAnimation.Progress {
        get { super.currentProgress }
        set {
            super.currentProgress = newValue
            update(CGFloat(currentValue))
        }
    }
}
