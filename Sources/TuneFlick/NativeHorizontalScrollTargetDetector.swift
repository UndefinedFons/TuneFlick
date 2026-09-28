import ApplicationServices
import CoreGraphics
import Foundation
import OSLog

final class NativeHorizontalScrollTargetDetector {
    private enum Observation: Equatable {
        case horizontalScrollAvailable
        case noHorizontalScrollAvailable
        case unknown

        var logLabel: String {
            switch self {
            case .horizontalScrollAvailable: "native-horizontal-scroll"
            case .noHorizontalScrollAvailable: "no-horizontal-scroll"
            case .unknown: "unknown-fail-open"
            }
        }
    }

    private struct Request {
        let location: CGPoint
        let processIdentifier: pid_t
        let generation: UInt64
    }

    private struct Snapshot {
        let location: CGPoint
        let processIdentifier: pid_t
        let observation: Observation
        let timestamp: TimeInterval
    }

    private let queue = DispatchQueue(label: "com.tuneflick.native-scroll-target", qos: .utility)
    private let lock = NSLock()
    private let logger = Logger(subsystem: "com.tuneflick.app", category: "gesture-priority")
    private var snapshot: Snapshot?
    private var pendingRequest: Request?
    private var queryInProgress = false
    private var generation: UInt64 = 0
    private var lastLoggedProcessIdentifier: pid_t?
    private var lastLoggedObservation: Observation?

    func refresh(at location: CGPoint, processIdentifier: pid_t) {
        lock.lock()
        pendingRequest = Request(location: location, processIdentifier: processIdentifier, generation: generation)
        let shouldStartQuery = !queryInProgress
        if shouldStartQuery { queryInProgress = true }
        lock.unlock()

        if shouldStartQuery {
            queue.async { [weak self] in self?.processRequests() }
        }
    }

    func clear() {
        lock.lock()
        generation &+= 1
        snapshot = nil
        pendingRequest = nil
        lastLoggedProcessIdentifier = nil
        lastLoggedObservation = nil
        lock.unlock()
    }

    /// Unknown or stale hit tests fail open so the player's native gesture wins.
    func nativeHorizontalScrollHasPriority(at location: CGPoint, processIdentifier: pid_t) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let snapshot,
              snapshot.processIdentifier == processIdentifier,
              ProcessInfo.processInfo.systemUptime - snapshot.timestamp <= 0.4,
              abs(snapshot.location.x - location.x) <= 24,
              abs(snapshot.location.y - location.y) <= 24 else {
            return true
        }

        return snapshot.observation != .noHorizontalScrollAvailable
    }

    private func processRequests() {
        while true {
            lock.lock()
            guard let request = pendingRequest else {
                queryInProgress = false
                lock.unlock()
                return
            }
            pendingRequest = nil
            lock.unlock()

            let observation = Self.inspect(request)

            lock.lock()
            var logObservation = false
            // A newer queued query must not starve a completed observation.
            if request.generation == generation {
                snapshot = Snapshot(
                    location: request.location,
                    processIdentifier: request.processIdentifier,
                    observation: observation,
                    timestamp: ProcessInfo.processInfo.systemUptime
                )
                logObservation = lastLoggedProcessIdentifier != request.processIdentifier ||
                    lastLoggedObservation != observation
                lastLoggedProcessIdentifier = request.processIdentifier
                lastLoggedObservation = observation
            }
            lock.unlock()
            if logObservation {
                logger.notice("Frontmost player hit-test: \(observation.logLabel, privacy: .public)")
            }
        }
    }

    private static func inspect(_ request: Request) -> Observation {
        let systemWideElement = AXUIElementCreateSystemWide()
        _ = AXUIElementSetMessagingTimeout(systemWideElement, 0.08)

        var hitElement: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            systemWideElement,
            Float(request.location.x),
            Float(request.location.y),
            &hitElement
        ) == .success,
        let hitElement else {
            return .unknown
        }

        var hitProcessIdentifier: pid_t = 0
        guard AXUIElementGetPid(hitElement, &hitProcessIdentifier) == .success,
              hitProcessIdentifier == request.processIdentifier else {
            return .unknown
        }

        var element = hitElement
        for _ in 0..<16 {
            guard let role = attribute(kAXRoleAttribute as CFString, from: element) as? String else {
                return .unknown
            }

            if role == (kAXScrollAreaRole as String) {
                switch horizontalScrollObservation(in: element) {
                case .some(.horizontalScrollAvailable):
                    return .horizontalScrollAvailable
                case .some(.unknown):
                    return .unknown
                case .some(.noHorizontalScrollAvailable), .none:
                    break
                }
            }

            if role == (kAXWindowRole as String) {
                return .noHorizontalScrollAvailable
            }

            guard let parent = accessibilityElementAttribute(kAXParentAttribute as CFString, from: element) else {
                return .unknown
            }
            element = parent
        }

        return .unknown
    }

    private static func attribute(_ name: CFString, from element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
        return value
    }

    private static func accessibilityElementAttribute(_ name: CFString, from element: AXUIElement) -> AXUIElement? {
        guard let value = attribute(name, from: element) else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func horizontalScrollObservation(in element: AXUIElement) -> Observation? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXHorizontalScrollBarAttribute as CFString,
            &value
        )
        guard result == .success else {
            if result == .noValue || result == .attributeUnsupported { return nil }
            return .unknown
        }
        guard let value else { return .unknown }

        let scrollBar = unsafeBitCast(value, to: AXUIElement.self)
        guard let minimum = attribute(kAXMinValueAttribute as CFString, from: scrollBar) as? NSNumber,
              let maximum = attribute(kAXMaxValueAttribute as CFString, from: scrollBar) as? NSNumber else {
            return .unknown
        }
        return maximum.doubleValue > minimum.doubleValue
            ? .horizontalScrollAvailable
            : .noHorizontalScrollAvailable
    }
}
