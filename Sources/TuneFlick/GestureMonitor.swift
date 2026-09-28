import AppKit
import OSLog

final class GestureMonitor {
    var captureContext: ((NSEvent.ModifierFlags, CGPoint) -> ScrollGestureRouter.Context?)?
    var onSwipe: ((SwipeDirection, ScrollGestureRouter.Context) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var router = ScrollGestureRouter()
    private let logger = Logger(subsystem: "com.tuneflick.app", category: "gesture")
    private var hasLoggedNonPreciseScroll = false

    var isRunning: Bool {
        eventTap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false
    }

    func start() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
            return
        }
        let mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<GestureMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = monitor.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passUnretained(event)
                }
                return monitor.handle(event) ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.error("Cannot create scroll filter; check Accessibility permission")
            return
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return
        }
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.info("Active scroll filter installed")
    }

    func stop() {
        if let eventTap { CFMachPortInvalidate(eventTap) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        router = ScrollGestureRouter()
    }

    private func handle(_ cgEvent: CGEvent) -> Bool {
        guard let event = NSEvent(cgEvent: cgEvent), event.type == .scrollWheel else { return false }
        let sample = ScrollGestureRouter.Sample(
            horizontal: event.scrollingDeltaX, vertical: event.scrollingDeltaY,
            precise: event.hasPreciseScrollingDeltas || cgEvent.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            began: event.phase.contains(.began), ended: event.phase.contains(.ended),
            cancelled: event.phase.contains(.cancelled),
            momentum: !event.momentumPhase.isEmpty,
            momentumEnded: event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled),
            phased: !event.phase.isEmpty,
            timestamp: ProcessInfo.processInfo.systemUptime
        )
        if !sample.precise && !hasLoggedNonPreciseScroll {
            hasLoggedNonPreciseScroll = true
            logger.notice("Received line-based scroll input; waiting for continuous trackpad input")
        }
        let result = router.process(sample) { self.captureContext?(event.modifierFlags, cgEvent.location) }
        if let owner = result.ownerDecision {
            let x = String(format: "%.1f", sample.horizontal)
            let y = String(format: "%.1f", sample.vertical)
            logger.notice("Scroll sequence routed to \(owner, privacy: .public), delta=(\(x, privacy: .public), \(y, privacy: .public)), modifiers=\(event.modifierFlags.rawValue, format: .hex, privacy: .public)")
        }
        if let direction = result.direction, let context = result.context {
            logger.notice("Swipe recognized: \(direction.actionLabel, privacy: .public), foreground=\(context.foreground)")
            // Do not send media events or animate inside the time-limited tap callback.
            DispatchQueue.main.async { [weak self] in self?.onSwipe?(direction, context) }
        }
        return result.consume
    }
}
