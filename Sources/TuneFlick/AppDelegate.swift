import AppKit
import ApplicationServices
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate, TuneFlickPanelDelegate, NSPopoverDelegate {
    private let gestureMonitor = GestureMonitor()
    private let mediaController = MediaController()
    private let preferences = GesturePreferences()
    private let nativeScrollTargetDetector = NativeHorizontalScrollTargetDetector()
    private let popover = NSPopover()
    private let statusIcon = StatusBarIconFactory.makeIcon()
    private let swipeFeedback = SwipeFeedbackController()
    private let logger = Logger(subsystem: "com.tuneflick.app", category: "playback")

    private var statusItem: NSStatusItem!
    private var panelController: ControlPanelViewController?
    private var popoverDismissMonitor: Any?
    private var popoverEscapeMonitor: Any?
    private var popoverOpenedAt: TimeInterval = 0
    private var permissionTimer: Timer?
    private var nativeScrollTargetTimer: Timer?
    private var playbackSourceTimer: Timer?
    private var capturePermitted = false
    private var previousApplication: NSRunningApplication?
    private var accessibilityGranted = false
    private var listenEventGranted = false
    private var postEventGranted = false
    private var lastPermissionLog = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        configurePopover()
        configureStatusItem()

        gestureMonitor.captureContext = { [weak self] flags, location in
            guard let self, self.preferences.gesturesEnabled,
                  self.capturePermitted, !self.popover.isShown else { return nil }
            let frontmostApplication = NSWorkspace.shared.frontmostApplication
            let foreground = frontmostApplication.map {
                PlayerDetector.isSupported(bundleIdentifier: $0.bundleIdentifier, localizedName: $0.localizedName)
            } ?? false
            guard GestureActivationPolicy.allowsCapture(
                foreground: foreground, flags: flags, backgroundModifier: self.preferences.backgroundModifier
            ), let source = self.mediaController.currentSource else { return nil }
            if foreground, let processIdentifier = frontmostApplication?.processIdentifier {
                guard source.matches(frontmostApplication?.bundleIdentifier) else { return nil }
                guard !self.nativeScrollTargetDetector.nativeHorizontalScrollHasPriority(
                    at: location,
                    processIdentifier: processIdentifier
                ) else { return nil }
            }
            return ScrollGestureRouter.Context(foreground: foreground, reverse: self.preferences.reverseSwipe,
                                               targetBundleIdentifier: source.bundleIdentifier)
        }
        gestureMonitor.onSwipe = { [weak self] direction, context in
            self?.handleSwipe(direction, context: context)
        }
        refreshMonitoring()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshMonitoring()
        }
        refreshNativeScrollTarget()
        nativeScrollTargetTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.refreshNativeScrollTarget()
        }
        refreshInterface()
        mediaController.refreshSource()
        playbackSourceTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, self.preferences.gesturesEnabled else { return }
            self.mediaController.refreshSource()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        gestureMonitor.stop()
        permissionTimer?.invalidate()
        nativeScrollTargetTimer?.invalidate()
        playbackSourceTimer?.invalidate()
        removePopoverDismissMonitors()
    }

    func panelState() -> TuneFlickPanelState {
        TuneFlickPanelState(
            gesturesEnabled: preferences.gesturesEnabled,
            modifier: preferences.backgroundModifier,
            reverseSwipe: preferences.reverseSwipe,
            accessibilityGranted: accessibilityGranted,
            listenGranted: listenEventGranted,
            postEventGranted: postEventGranted,
            monitoringReady: gestureMonitor.isRunning
        )
    }

    func setGesturesEnabled(_ enabled: Bool) {
        preferences.gesturesEnabled = enabled
        if enabled { mediaController.refreshSource() }
        refreshInterface()
    }

    func setBackgroundModifier(_ modifier: GestureModifier) {
        preferences.backgroundModifier = modifier
        refreshInterface()
    }

    func setReverseSwipe(_ reverseSwipe: Bool) {
        preferences.reverseSwipe = reverseSwipe
        refreshInterface()
    }

    func requestAccessibilityPermission() {
        refreshPermissionState()
        if !accessibilityGranted {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            openPrivacyPane("Privacy_Accessibility")
        } else if !listenEventGranted {
            if !CGRequestListenEventAccess() { openPrivacyPane("Privacy_ListenEvent") }
        } else if !postEventGranted {
            if !CGRequestPostEventAccess() { openPrivacyPane("Privacy_Accessibility") }
        }
        refreshMonitoring()
        refreshInterface()
    }

    func terminateApplication() {
        NSApp.terminate(nil)
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            closePopover(sender)
            return
        }

        refreshMonitoring()
        panelController?.refresh()
        previousApplication = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        popoverOpenedAt = ProcessInfo.processInfo.systemUptime
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        panelController?.view.window?.makeKey()
        installPopoverDismissMonitors()
    }

    private func configurePopover() {
        let controller = ControlPanelViewController(delegate: self)
        panelController = controller
        popover.contentViewController = controller
        popover.delegate = self
        popover.behavior = .applicationDefined
        popover.animates = true
    }

    func popoverDidClose(_ notification: Notification) {
        removePopoverDismissMonitors()
        popoverOpenedAt = 0
        let previous = previousApplication
        previousApplication = nil
        // Outside clicks choose their own destination; only restore on Esc/toggle.
        DispatchQueue.main.async {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                previous?.activate(options: [])
            }
        }
    }

    func popoverDidShow(_ notification: Notification) {
        panelController?.view.window?.makeKey()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }

        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])
        updateStatusItem()
    }

    private func handleSwipe(_ direction: SwipeDirection, context: ScrollGestureRouter.Context) {
        guard preferences.gesturesEnabled, let target = context.targetBundleIdentifier else { return }
        let effectiveDirection = context.reverse ? direction.opposite : direction
        mediaController.perform(effectiveDirection, targetBundleIdentifier: target) { [weak self] accepted in
            guard let self else { return }
            guard accepted else {
                self.logger.error("Media command rejected, unavailable, or playback source changed")
                return
            }
            self.logger.notice("System media command accepted: \(effectiveDirection.actionLabel, privacy: .public)")
            // Background commands stay silent, even if focus changes before completion.
            if context.foreground, self.preferences.gesturesEnabled,
               NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.lowercased() == target {
                self.swipeFeedback.show(direction: direction, action: effectiveDirection)
            }
        }
    }

    private func refreshMonitoring() {
        let previouslyReady = gestureMonitor.isRunning
        let previouslyPermitted = capturePermitted
        refreshPermissionState()
        capturePermitted = accessibilityGranted && listenEventGranted && postEventGranted
        if capturePermitted && !gestureMonitor.isRunning {
            gestureMonitor.start()
        } else if !capturePermitted && gestureMonitor.isRunning {
            gestureMonitor.stop()
        }
        if previouslyReady != gestureMonitor.isRunning || previouslyPermitted != capturePermitted {
            refreshInterface()
        }
    }

    private func refreshPermissionState() {
        accessibilityGranted = AXIsProcessTrusted()
        listenEventGranted = CGPreflightListenEventAccess()
        postEventGranted = CGPreflightPostEventAccess()
        let snapshot = "accessibility=\(accessibilityGranted), listen=\(listenEventGranted), post=\(postEventGranted), tap=\(gestureMonitor.isRunning)"
        if snapshot != lastPermissionLog {
            logger.notice("Permission state: \(snapshot, privacy: .public)")
            lastPermissionLog = snapshot
        }
    }

    private func refreshNativeScrollTarget() {
        guard let application = NSWorkspace.shared.frontmostApplication,
              PlayerDetector.isSupported(bundleIdentifier: application.bundleIdentifier, localizedName: application.localizedName),
              let location = CGEvent(source: nil)?.location else {
            nativeScrollTargetDetector.clear()
            return
        }
        nativeScrollTargetDetector.refresh(at: location, processIdentifier: application.processIdentifier)
    }

    private func openPrivacyPane(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func refreshInterface() {
        updateStatusItem()
        panelController?.refresh()
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }

        button.image = statusIcon ?? NSImage(systemSymbolName: "music.note.list", accessibilityDescription: "TuneFlick")
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = preferences.gesturesEnabled
            ? "TuneFlick · 前台直滑切歌 / \(preferences.backgroundModifier.shortcutTitle) + 横滑保留原生操作 · 后台 \(preferences.backgroundModifier.shortcutTitle) + 横滑"
            : "TuneFlick · 手势已暂停"
    }

    private func closePopover(_ sender: Any?) {
        guard popover.isShown else { return }
        popover.performClose(sender)
    }

    private func installPopoverDismissMonitors() {
        removePopoverDismissMonitors()

        let mouseDownEvents: NSEvent.EventTypeMask = [
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown
        ]
        popoverDismissMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseDownEvents) { [weak self] event in
            guard let self, self.popover.isShown, event.timestamp >= self.popoverOpenedAt else { return }
            let location = self.screenLocation(of: event)
            guard !self.containsPopoverInteraction(at: location) else { return }
            self.closePopover(nil)
        }

        popoverEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, self?.popover.isShown == true else {
                return event
            }

            self?.closePopover(nil)
            return nil
        }
    }

    private func screenLocation(of event: NSEvent) -> NSPoint {
        if let window = event.window {
            return window.convertPoint(toScreen: event.locationInWindow)
        }
        if let location = event.cgEvent?.location, let primaryScreen = NSScreen.screens.first {
            return NSPoint(x: location.x, y: primaryScreen.frame.maxY - location.y)
        }
        return NSEvent.mouseLocation
    }

    private func containsPopoverInteraction(at location: NSPoint) -> Bool {
        if let window = panelController?.view.window, contains(location, in: window) {
            return true
        }
        if let button = statusItem.button, let window = button.window {
            let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
            if buttonFrame.contains(location) { return true }
        }
        return false
    }

    private func contains(_ location: NSPoint, in window: NSWindow) -> Bool {
        if window.isVisible && window.frame.contains(location) { return true }
        return window.childWindows?.contains { contains(location, in: $0) } ?? false
    }

    private func removePopoverDismissMonitors() {
        if let popoverDismissMonitor {
            NSEvent.removeMonitor(popoverDismissMonitor)
            self.popoverDismissMonitor = nil
        }

        if let popoverEscapeMonitor {
            NSEvent.removeMonitor(popoverEscapeMonitor)
            self.popoverEscapeMonitor = nil
        }
    }
}
