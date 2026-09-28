import Foundation

/// Locks ownership on the first directional delta, including the inertial tail.
/// No events are replayed: a gesture belongs either to the page or to TuneFlick.
struct ScrollGestureRouter {
    struct Context {
        let foreground: Bool
        let reverse: Bool
        var targetBundleIdentifier: String? = nil
    }

    struct Sample {
        var horizontal: CGFloat = 0
        var vertical: CGFloat = 0
        var precise = true
        var began = false
        var ended = false
        var cancelled = false
        var momentum = false
        var momentumEnded = false
        var phased = true
        var timestamp: TimeInterval = 0
    }

    struct Result {
        var consume = false
        var direction: SwipeDirection?
        var context: Context?
        var ownerDecision: String?
    }

    private enum Ownership { case undecided, page, tuneFlick }
    private var ownership = Ownership.undecided
    private var context: Context?
    private var distance: CGFloat = 0
    private var delivered = false
    private var lastTimestamp: TimeInterval?
    private var fingersEnded = false

    mutating func process(_ sample: Sample, captureContext: () -> Context?) -> Result {
        guard sample.precise else { return Result() }
        // Momentum can arrive after a pause or after the modifier is released.
        // Never reset its owner merely because the finger phase has ended.
        if !sample.momentum && (sample.began || fingersEnded ||
            (!sample.phased && sample.timestamp - (lastTimestamp ?? -.infinity) > 0.25)) {
            self = ScrollGestureRouter()
        }
        lastTimestamp = sample.timestamp

        if sample.momentum {
            let result = Result(consume: ownership == .tuneFlick)
            if sample.momentumEnded { self = ScrollGestureRouter() }
            return result
        }

        var ownerDecision: String?
        if ownership == .undecided && (sample.horizontal != 0 || sample.vertical != 0) {
            if abs(sample.horizontal) > abs(sample.vertical), let candidate = captureContext() {
                ownership = .tuneFlick
                context = candidate
            } else {
                ownership = .page
            }
            ownerDecision = ownership == .tuneFlick ? "TuneFlick" : "front app"
        }

        var result = Result(consume: ownership == .tuneFlick, ownerDecision: ownerDecision)
        if ownership == .tuneFlick && !sample.cancelled {
            distance += sample.horizontal
            if !delivered && abs(distance) >= 24 {
                delivered = true
                result.direction = distance > 0 ? .right : .left
                result.context = context
            }
        }
        if sample.ended { fingersEnded = true }
        if sample.cancelled { self = ScrollGestureRouter() }
        return result
    }
}
