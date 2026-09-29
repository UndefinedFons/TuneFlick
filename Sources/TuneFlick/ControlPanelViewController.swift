import AppKit

struct TuneFlickPanelState {
    let gesturesEnabled: Bool
    let modifier: GestureModifier
    let reverseSwipe: Bool
    let accessibilityGranted: Bool
    let listenGranted: Bool
    let postEventGranted: Bool
    let monitoringReady: Bool
}

protocol TuneFlickPanelDelegate: AnyObject {
    func panelState() -> TuneFlickPanelState
    func setGesturesEnabled(_ enabled: Bool)
    func setBackgroundModifier(_ modifier: GestureModifier)
    func setReverseSwipe(_ reverseSwipe: Bool)
    func requestAccessibilityPermission()
    func terminateApplication()
}

final class ControlPanelViewController: NSViewController {
    private weak var delegate: (any TuneFlickPanelDelegate)?
    private let enabledSwitch = NSSwitch()
    private let modifierPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let reverseSwitch = NSSwitch()
    private let statusLabel = NSTextField(labelWithString: "")
    private let gestureHint = NSTextField(labelWithString: "")
    private let previousAction = NSTextField(labelWithString: "上一首")
    private let nextAction = NSTextField(labelWithString: "下一首")
    private let previousDirection = NSImageView()
    private let nextDirection = NSImageView()
    private let permissionLabel = NSTextField(labelWithString: "")
    private let permissionButton = NSButton(title: "授权…", target: nil, action: nil)
    private let permissionSection = NSStackView()

    init(delegate: any TuneFlickPanelDelegate) {
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 344, height: 224)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:)") }

    override func loadView() {
        let glass = NSVisualEffectView(frame: NSRect(origin: .zero, size: preferredContentSize))
        glass.material = .popover
        glass.blendingMode = .behindWindow
        glass.state = .active
        view = glass
        view.setAccessibilityLabel("TuneFlick 控制面板")
        configureControls()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
        ])
        stack.addArrangedSubview(makeHeader())
        stack.addArrangedSubview(spacer(12))
        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(spacer(5))
        stack.addArrangedSubview(makeGestureGuide())
        stack.addArrangedSubview(spacer(5))
        stack.addArrangedSubview(separator())
        stack.addArrangedSubview(spacer(3))
        stack.addArrangedSubview(settingRow("修饰键", detail: "按住此键：前台原生滑动，后台切歌", control: modifierPopup))
        stack.addArrangedSubview(settingRow("反向滑动", detail: "交换上一首与下一首的方向", control: reverseSwitch))
        stack.addArrangedSubview(spacer(3))
        stack.addArrangedSubview(separator())

        permissionSection.orientation = .vertical
        permissionSection.alignment = .width
        permissionSection.spacing = 6
        permissionSection.addArrangedSubview(spacer(3))
        permissionSection.addArrangedSubview(horizontal([permissionLabel, flexibleSpace(), permissionButton]))
        stack.addArrangedSubview(permissionSection)
        stack.addArrangedSubview(spacer(7))
        gestureHint.font = .systemFont(ofSize: 10)
        gestureHint.textColor = .secondaryLabelColor
        let quit = NSButton(title: "退出", target: self, action: #selector(quitApp))
        quit.bezelStyle = .inline
        quit.controlSize = .small
        stack.addArrangedSubview(horizontal([gestureHint, flexibleSpace(), quit]))
        refresh()
    }

    func refresh() {
        guard isViewLoaded, let state = delegate?.panelState() else { return }
        enabledSwitch.state = state.gesturesEnabled ? .on : .off
        reverseSwitch.state = state.reverseSwipe ? .on : .off
        modifierPopup.selectItem(withTitle: state.modifier.shortcutTitle)
        gestureHint.stringValue = "前台直滑切歌 · \(state.modifier.title) 原生横滑 · 后台按修饰键"
        statusLabel.stringValue = statusText(for: state)
        previousDirection.image = NSImage(systemSymbolName: state.reverseSwipe ? "arrow.right" : "arrow.left", accessibilityDescription: nil)
        nextDirection.image = NSImage(systemSymbolName: state.reverseSwipe ? "arrow.left" : "arrow.right", accessibilityDescription: nil)
        let ready = state.accessibilityGranted && state.listenGranted && state.postEventGranted && state.monitoringReady
        permissionSection.isHidden = ready
        permissionLabel.stringValue = permissionText(for: state)
        permissionButton.title = state.accessibilityGranted && state.listenGranted && state.postEventGranted ? "重试" : "打开设置…"
        preferredContentSize = NSSize(width: 344, height: ready ? 224 : 255)
    }

    private func configureControls() {
        enabledSwitch.target = self
        enabledSwitch.action = #selector(toggleEnabled(_:))
        enabledSwitch.controlSize = .small
        enabledSwitch.setAccessibilityLabel("启用触控板切歌")
        enabledSwitch.toolTip = "关闭后恢复播放器原有的横滑操作"
        reverseSwitch.target = self
        reverseSwitch.action = #selector(toggleReverse(_:))
        reverseSwitch.controlSize = .small
        reverseSwitch.setAccessibilityLabel("反向滑动")
        modifierPopup.addItems(withTitles: GestureModifier.allCases.map(\.shortcutTitle))
        modifierPopup.target = self
        modifierPopup.action = #selector(changeModifier(_:))
        modifierPopup.controlSize = .small
        modifierPopup.font = .systemFont(ofSize: 11)
        modifierPopup.widthAnchor.constraint(equalToConstant: 104).isActive = true
        modifierPopup.setAccessibilityLabel("手势修饰键")
        permissionLabel.font = .systemFont(ofSize: 11)
        permissionLabel.textColor = .secondaryLabelColor
        permissionButton.target = self
        permissionButton.action = #selector(requestPermission)
        permissionButton.bezelStyle = .rounded
        permissionButton.controlSize = .small
    }

    private func makeHeader() -> NSView {
        let title = text("TuneFlick", size: 15, weight: .semibold)
        statusLabel.font = .systemFont(ofSize: 10)
        statusLabel.textColor = .secondaryLabelColor
        let titles = NSStackView(views: [title, statusLabel])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 3
        return horizontal([titles, flexibleSpace(), enabledSwitch], spacing: 12)
    }

    private func makeGestureGuide() -> NSView {
        let previous = directionHint(previousDirection, label: previousAction, iconFirst: true)
        let next = directionHint(nextDirection, label: nextAction, iconFirst: false)
        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.separatorColor.cgColor
        divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
        divider.heightAnchor.constraint(equalToConstant: 18).isActive = true
        let group = horizontal([previous, divider, next], spacing: 18)
        group.setContentHuggingPriority(.required, for: .horizontal)
        let container = NSView()
        container.addSubview(group)
        group.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 38),
            group.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            group.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }

    private func directionHint(_ icon: NSImageView, label: NSTextField, iconFirst: Bool) -> NSView {
        icon.contentTintColor = .secondaryLabelColor
        icon.widthAnchor.constraint(equalToConstant: 12).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 12).isActive = true
        label.font = .systemFont(ofSize: 11, weight: .medium)
        let content: [NSView] = iconFirst
            ? [flexibleSpace(), icon, label, flexibleSpace()]
            : [flexibleSpace(), label, icon, flexibleSpace()]
        let row = horizontal(content, spacing: 6)
        return row
    }

    private func settingRow(_ title: String, detail: String, control: NSView) -> NSView {
        let labels = NSStackView(views: [text(title, size: 11, weight: .medium), text(detail, size: 9, secondary: true)])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 4
        control.setContentHuggingPriority(.required, for: .horizontal)
        let row = horizontal([labels, flexibleSpace(), control])
        row.heightAnchor.constraint(equalToConstant: 40).isActive = true
        return row
    }

    private func statusText(for state: TuneFlickPanelState) -> String {
        if !state.gesturesEnabled { return "手势已暂停" }
        if !state.accessibilityGranted { return "需要辅助功能权限" }
        if !state.listenGranted { return "需要输入监控权限" }
        if !state.postEventGranted { return "需要系统事件权限" }
        return state.monitoringReady ? "已就绪 · 前台横滑 / 后台按修饰键" : "滚动监听器未启动"
    }

    private func permissionText(for state: TuneFlickPanelState) -> String {
        if !state.accessibilityGranted { return "需要辅助功能权限" }
        if !state.listenGranted { return "需要输入监控权限来监听触控板" }
        if !state.postEventGranted { return "需要系统事件权限来发送媒体键" }
        return "滚动监听器未启动，可尝试重启"
    }

    private func horizontal(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = spacing
        return stack
    }

    private func text(_ value: String, size: CGFloat, weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
        let label = NSTextField(labelWithString: value)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = secondary ? .secondaryLabelColor : .labelColor
        return label
    }

    private func flexibleSpace() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }

    private func spacer(_ height: CGFloat) -> NSView {
        let view = NSView()
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }

    private func separator() -> NSView {
        let line = NSBox()
        line.boxType = .separator
        return line
    }

    @objc private func toggleEnabled(_ sender: NSSwitch) { delegate?.setGesturesEnabled(sender.state == .on) }
    @objc private func toggleReverse(_ sender: NSSwitch) { delegate?.setReverseSwipe(sender.state == .on) }
    @objc private func changeModifier(_ sender: NSPopUpButton) {
        guard GestureModifier.allCases.indices.contains(sender.indexOfSelectedItem) else { return }
        delegate?.setBackgroundModifier(GestureModifier.allCases[sender.indexOfSelectedItem])
    }
    @objc private func requestPermission() { delegate?.requestAccessibilityPermission() }
    @objc private func quitApp() { delegate?.terminateApplication() }
}
