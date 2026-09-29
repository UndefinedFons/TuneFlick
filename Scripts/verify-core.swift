import AppKit
import Foundation

@main
enum CoreVerification {
    private static var checks = 0

    static func main() {
        verifyModifiers()
        verifySelectedModifierRouting()
        verifyPanelModifierHints()
        verifyRouting()
        verifySources()
        verifyCommands()
        verifyProcess()
        print("PASS: \(checks) core checks; no real playback commands sent")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        guard condition() else { fatalError(message) }
    }

    private static func wait(until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        expect(condition(), "Async operation did not complete")
    }

    private static func verifyModifiers() {
        let all: [NSEvent.ModifierFlags] = [.control, .option, .command, .shift]
        for selected in GestureModifier.allCases {
            for mask in 0..<16 {
                var flags: NSEvent.ModifierFlags = []
                for index in 0..<4 where mask & (1 << index) != 0 { flags.insert(all[index]) }
                let foregroundCapture = mask == 0 || ([1, 2, 4, 8].contains(mask) && flags != selected.modifierFlag)
                expect(GestureActivationPolicy.allowsCapture(foreground: true, flags: flags, backgroundModifier: selected) == foregroundCapture,
                       "Foreground capture mismatch: selected \(selected.title), modifier mask \(mask)")
                expect(GestureActivationPolicy.allowsCapture(foreground: false, flags: flags, backgroundModifier: selected) == (flags == selected.modifierFlag),
                       "Background must require exactly the selected modifier")
            }
        }
        expect(GestureActivationPolicy.allowsCapture(foreground: true, flags: .capsLock, backgroundModifier: .control),
               "Caps Lock is not a shortcut modifier")
        let suite = "com.tuneflick.verification.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = GesturePreferences(defaults: defaults)
        expect(preferences.gesturesEnabled && preferences.backgroundModifier == .control && !preferences.reverseSwipe,
               "Default preferences changed")
        preferences.backgroundModifier = .option
        preferences.reverseSwipe = true
        preferences.gesturesEnabled = false
        let restored = GesturePreferences(defaults: defaults)
        expect(!restored.gesturesEnabled && restored.backgroundModifier == .option && restored.reverseSwipe,
               "Preferences were not persisted")
        for selected in GestureModifier.allCases {
            preferences.backgroundModifier = selected
            expect(restored.backgroundModifier == selected, "Selected modifier did not update or persist")
        }
    }

    private static func verifySelectedModifierRouting() {
        for selected in GestureModifier.allCases {
            for pressed in GestureModifier.allCases {
                for foreground in [true, false] {
                    let expectedCapture = foreground ? pressed != selected : pressed == selected
                    for direction in [SwipeDirection.left, .right] {
                        var router = ScrollGestureRouter()
                        let capture = { () -> ScrollGestureRouter.Context? in
                            guard GestureActivationPolicy.allowsCapture(foreground: foreground,
                                flags: pressed.modifierFlag, backgroundModifier: selected) else { return nil }
                            return .init(foreground: foreground, reverse: false, targetBundleIdentifier: "com.spotify.client")
                        }
                        let sign: CGFloat = direction == .left ? -1 : 1
                        let scenario = "selected \(selected.title), pressed \(pressed.title), foreground \(foreground), direction \(direction)"
                        let began = router.process(.init(horizontal: sign * 12, began: true, timestamp: 1), captureContext: capture)
                        expect(began.consume == expectedCapture && began.direction == nil,
                               "Modifier gesture ownership mismatch: \(scenario)")
                        let ended = router.process(.init(horizontal: sign * 13, ended: true, timestamp: 1.1), captureContext: capture)
                        expect(ended.consume == expectedCapture && ended.direction == (expectedCapture ? direction : nil),
                               "Modifier gesture action mismatch: \(scenario)")
                        let momentum = router.process(.init(horizontal: sign * 30, momentum: true, momentumEnded: true, timestamp: 1.2), captureContext: { nil })
                        expect(momentum.consume == expectedCapture && momentum.direction == nil,
                               "Modifier gesture momentum ownership mismatch: \(scenario)")
                    }
                }
            }
        }
    }

    private final class PanelDelegate: TuneFlickPanelDelegate {
        var modifier = GestureModifier.control

        func panelState() -> TuneFlickPanelState {
            .init(gesturesEnabled: true, modifier: modifier, reverseSwipe: false,
                  accessibilityGranted: true, listenGranted: true, postEventGranted: true, monitoringReady: true)
        }

        func setBackgroundModifier(_ modifier: GestureModifier) { self.modifier = modifier }
        func setGesturesEnabled(_ enabled: Bool) {}
        func setReverseSwipe(_ reverseSwipe: Bool) {}
        func requestAccessibilityPermission() { fatalError("Panel verification must not request system permissions") }
        func terminateApplication() { fatalError("Panel verification must not terminate an application") }
    }

    private static func verifyPanelModifierHints() {
        func descendants(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap(descendants)
        }
        let delegate = PanelDelegate()
        let panel = ControlPanelViewController(delegate: delegate)
        let views = descendants(panel.view)
        let labels = views.compactMap { $0 as? NSTextField }
        let popup = views.compactMap { $0 as? NSPopUpButton }.first!
        let quit = views.compactMap { $0 as? NSButton }.first { $0.title == "退出" }!
        expect(labels.contains { $0.stringValue == "修饰键" }, "Modifier setting must describe both foreground and background")
        expect(popup.accessibilityLabel() == "手势修饰键", "Accessible modifier label must not imply background-only behavior")
        for selected in GestureModifier.allCases {
            delegate.setBackgroundModifier(selected)
            panel.refresh()
            let expected = "前台直滑切歌 · \(selected.title) 原生横滑 · 后台按修饰键"
            let hint = labels.first { $0.stringValue == expected }
            expect(hint != nil, "Panel hint did not follow the selected modifier")
            expect(popup.titleOfSelectedItem == selected.shortcutTitle, "Panel selection did not follow the selected modifier")
            expect(hint!.intrinsicContentSize.width + quit.intrinsicContentSize.width + 16 <= panel.view.bounds.width - 32,
                   "Selected modifier hint would overflow the panel footer")
            if selected != .control {
                expect(!labels.contains { $0.stringValue.contains("Control 原生横滑") }, "Panel retained a fixed Control hint after changing the modifier")
            }
        }
    }

    private static func verifyRouting() {
        let context = ScrollGestureRouter.Context(foreground: false, reverse: true, targetBundleIdentifier: "com.spotify.client")
        var router = ScrollGestureRouter()
        var captures = 0
        let capture = { () -> ScrollGestureRouter.Context? in captures += 1; return context }
        var result = router.process(.init(horizontal: 10, began: true, timestamp: 1), captureContext: capture)
        expect(result.consume && result.direction == nil, "Owned gesture should swallow initial deltas")
        result = router.process(.init(horizontal: 15, timestamp: 1.1), captureContext: capture)
        expect(result.consume && result.direction == .right && result.context?.reverse == true && result.context?.targetBundleIdentifier == "com.spotify.client",
               "Gesture context or threshold lost")
        result = router.process(.init(horizontal: 40, ended: true, timestamp: 1.2), captureContext: capture)
        expect(result.consume && result.direction == nil && captures == 1, "One physical gesture must produce one command")
        result = router.process(.init(horizontal: 50, momentum: true, timestamp: 2), captureContext: { nil })
        expect(result.consume && result.direction == nil, "Momentum must remain swallowed after releasing the modifier")
        result = router.process(.init(momentum: true, momentumEnded: true, timestamp: 2.1), captureContext: { nil })
        expect(result.consume, "Last momentum event must remain owned")
        result = router.process(.init(horizontal: 50, began: true, timestamp: 3), captureContext: { nil })
        expect(!result.consume && result.direction == nil, "Ordinary background gesture must pass through")

        router = ScrollGestureRouter()
        result = router.process(.init(horizontal: 2, vertical: 20, began: true, timestamp: 1), captureContext: capture)
        expect(!result.consume, "Vertical scrolling should pass through")
        result = router.process(.init(horizontal: 100, timestamp: 1.1), captureContext: capture)
        expect(!result.consume && result.direction == nil, "Page ownership must not flip mid-gesture")

        router = ScrollGestureRouter()
        result = router.process(.init(horizontal: 100, precise: false, began: true), captureContext: capture)
        expect(!result.consume, "Mouse wheel must not be captured")
        result = router.process(.init(horizontal: -25, began: true), captureContext: capture)
        expect(result.direction == .left && SwipeDirection.left.opposite == .right, "Left or reverse direction changed")
        result = router.process(.init(cancelled: true), captureContext: capture)
        expect(result.direction == nil, "Cancellation must not generate a command")
        result = router.process(.init(horizontal: 25, began: true), captureContext: { nil })
        expect(!result.consume, "Native-priority areas must pass through")
    }

    private static func metadata(_ identifier: String) -> Data {
        try! JSONSerialization.data(withJSONObject: ["bundleIdentifier": identifier, "playing": true])
    }

    private static func verifySources() {
        for identifier in ["com.apple.Music", "com.spotify.client", "com.netease.163music", "com.tencent.QQMusicMac", "com.kugou.mac.Music", "co.brushedtype.doppler-macos"] {
            expect(NowPlayingSource.decode(metadata(identifier))?.matches(identifier) == true, "Supported source not recognized: \(identifier)")
        }
        expect(NowPlayingSource.decode(metadata("com.google.Chrome")) == nil, "Browser media must not enable background music capture")
        expect(NowPlayingSource.decode(Data("null".utf8)) == nil, "Missing media must disable capture")
        expect(NowPlayingSource.decode(Data("broken".utf8)) == nil, "Malformed metadata must fail open")
        let parent = Data("{\"bundleIdentifier\":\"player.helper\",\"parentApplicationBundleIdentifier\":\"com.spotify.client\"}".utf8)
        expect(NowPlayingSource.decode(parent)?.matches("COM.SPOTIFY.CLIENT") == true, "Parent application identity should be supported")
    }

    private static func verifyCommands() {
        for direction in [SwipeDirection.left, .right] {
            var calls: [[String]] = []
            let controller = MediaController { arguments in
                calls.append(arguments)
                return arguments.first == "get" ? metadata("com.spotify.client") : Data()
            }
            var completed = false
            controller.perform(direction, targetBundleIdentifier: "com.spotify.client") { accepted in
                expect(accepted && Thread.isMainThread, "Command completion must report acceptance on main")
                completed = true
            }
            wait { completed }
            expect(calls == [["get", "--no-artwork", "--allow-missing-title"], [direction == .left ? "previous-track" : "next-track"]],
                   "Command must revalidate source, omit artwork, and use correct system command")
        }

        var calls: [[String]] = []
        let changed = MediaController { arguments in calls.append(arguments); return metadata("com.netease.163music") }
        var completed = false
        changed.perform(.right, targetBundleIdentifier: "com.spotify.client") { accepted in
            expect(!accepted, "Changed playback source must not receive an old gesture")
            completed = true
        }
        wait { completed }
        expect(calls.count == 1, "Source mismatch must not send or retry a command")

        calls = []
        let failed = MediaController { arguments in
            calls.append(arguments)
            return arguments.first == "get" ? metadata("com.spotify.client") : nil
        }
        completed = false
        failed.perform(.left, targetBundleIdentifier: "com.spotify.client") { accepted in
            expect(!accepted, "Failed command must not be reported as success")
            completed = true
        }
        wait { completed }
        expect(calls.count == 2, "Ambiguous failure must never be retried")

        var refreshes = 0
        let cached = MediaController { _ in refreshes += 1; return metadata("com.spotify.client") }
        expect(cached.currentSource == nil, "Uninitialized playback cache must fail open")
        cached.refreshSource()
        cached.refreshSource()
        wait { cached.currentSource != nil }
        expect(refreshes == 1, "Repeated source refresh must coalesce")
    }

    private static func verifyProcess() {
        let perl = URL(fileURLWithPath: "/usr/bin/perl")
        expect(MediaControlProcess.run(executable: perl, arguments: ["-e", "print q(ok)"], timeout: 1) == Data("ok".utf8), "Helper stdout lost")
        expect(MediaControlProcess.run(executable: perl, arguments: ["-e", "exit 3"], timeout: 1) == nil, "Nonzero helper exit must fail")
        expect(MediaControlProcess.run(executable: perl, arguments: ["-e", "print q(x) x 100000"], timeout: 1) == nil, "Oversized output must be drained and rejected")
        let start = Date()
        expect(MediaControlProcess.run(executable: perl, arguments: ["-e", "select undef, undef, undef, 10"], timeout: 0.1) == nil,
               "Stalled helper must time out")
        expect(Date().timeIntervalSince(start) < 1, "Helper timeout must remain bounded")
    }
}
