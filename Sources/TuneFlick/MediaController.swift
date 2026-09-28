import Foundation

/// Only source identity is retained; track metadata is neither stored nor logged.
struct NowPlayingSource: Equatable {
    let bundleIdentifier: String

    static func decode(_ data: Data) -> NowPlayingSource? {
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        for key in ["parentApplicationBundleIdentifier", "bundleIdentifier"] {
            if let identifier = payload[key] as? String,
               PlayerDetector.isSupported(bundleIdentifier: identifier, localizedName: nil) {
                return NowPlayingSource(bundleIdentifier: identifier.lowercased())
            }
        }
        return nil
    }

    func matches(_ identifier: String?) -> Bool {
        identifier?.lowercased() == bundleIdentifier
    }
}

final class MediaController {
    typealias Execute = ([String]) -> Data?
    private static let metadataArguments = ["get", "--no-artwork", "--allow-missing-title"]
    private let queue = DispatchQueue(label: "com.tuneflick.media-control", qos: .userInitiated)
    private let execute: Execute
    private var refreshInProgress = false
    private var source: NowPlayingSource?
    private var sourceReadAt: TimeInterval = 0

    init(execute: @escaping Execute = MediaControlProcess.run) {
        self.execute = execute
    }

    // Accessed on the main run loop, including the event-tap callback.
    var currentSource: NowPlayingSource? {
        guard ProcessInfo.processInfo.systemUptime - sourceReadAt < 4 else { return nil }
        return source
    }

    func refreshSource() {
        guard !refreshInProgress else { return }
        refreshInProgress = true
        queue.async { [self] in
            let candidate = execute(Self.metadataArguments).flatMap(NowPlayingSource.decode)
            DispatchQueue.main.async { [self] in
                source = candidate
                sourceReadAt = ProcessInfo.processInfo.systemUptime
                refreshInProgress = false
            }
        }
    }

    func perform(_ direction: SwipeDirection, targetBundleIdentifier: String, completion: @escaping (Bool) -> Void) {
        queue.async { [self] in
            // Recheck immediately before sending: a cached source must not route to another player.
            let candidate = execute(Self.metadataArguments).flatMap(NowPlayingSource.decode)
            let accepted: Bool
            if candidate?.matches(targetBundleIdentifier) == true {
                let command = direction == .left ? "previous-track" : "next-track"
                accepted = execute([command]) != nil
            } else {
                accepted = false
            }
            // Do not retry ambiguous failures: the player may have already handled the command.
            DispatchQueue.main.async { [self] in
                source = candidate
                sourceReadAt = ProcessInfo.processInfo.systemUptime
                completion(accepted)
            }
        }
    }
}
