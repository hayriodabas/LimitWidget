import AppKit
import Observation
import SwiftUI

/// LimitWidget: menü çubuğunda yaşayan kota izleyici. Ana pencere ve Ayarlar AppKit üzerinden yönetilir;
/// böylece Dock simgesi olmadan menü çubuğundan açılıp kapanabilir.
@main
struct LimitWidgetApp: App {
    @State private var store: SubscriptionStore
    @State private var preferences: AppPreferences
    @State private var statusBarController: StatusBarController

    init() {
        let store = SubscriptionStore()
        let preferences = AppPreferences()
        store.startAutoSync(interval: TimeInterval(preferences.refreshInterval))
        _store = State(initialValue: store)
        _preferences = State(initialValue: preferences)
        _statusBarController = State(initialValue: StatusBarController(store: store, preferences: preferences))
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

/// Menü çubuğu simgesini, açılır paneli, ana pencereyi ve Ayarlar penceresini yönetir.
@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate, NSApplicationDelegate, NSWindowDelegate {
    private let store: SubscriptionStore
    private let preferences: AppPreferences
    private let notifier = UsageAlertNotifier()
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var studioWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var isPinnedByClick = false
    private var isPointerInButton = false
    private var isPointerInPopover = false
    private var hoverOpenTask: Task<Void, Never>?
    private var hoverCloseTask: Task<Void, Never>?
    private var appliedRefreshInterval: Int
    private var launchedAsLoginItem = false

    init(store: SubscriptionStore, preferences: AppPreferences) {
        self.store = store
        self.preferences = preferences
        self.appliedRefreshInterval = preferences.refreshInterval
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()

        NSApplication.shared.delegate = self
        NSApplication.shared.setActivationPolicy(.accessory)
        configurePopover()
        configureStatusButton()
        applyThemeAppearance()
        observeStoreChanges()
        observePreferenceChanges()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            // Oturum açılışında sessizce menü çubuğunda başla; elle açılışta pencereyi göster.
            if self?.launchedAsLoginItem == false {
                self?.bringMainWindowToFront()
            }
            #if DEBUG
            self?.openDebugSurfacesIfRequested()
            #endif
        }
    }

    #if DEBUG
    /// Geliştirme sırasında ekran görüntüsü almak için: `-LWDebugOpen popover|settings|add`.
    private func openDebugSurfacesIfRequested() {
        switch UserDefaults.standard.string(forKey: "LWDebugOpen") {
        case "popover":
            isPinnedByClick = true
            showPopover()
        case "settings":
            showSettingsWindow()
        default:
            break
        }
    }
    #endif

    func applicationWillFinishLaunching(_ notification: Notification) {
        let event = NSAppleEventManager.shared().currentAppleEvent
        launchedAsLoginItem = event?.eventID == AEEventID(kAEOpenApplication)
            && event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        bringMainWindowToFront()
        return true
    }

    // MARK: Appearance

    private func applyThemeAppearance() {
        let appearance: NSAppearance?
        switch store.themeMode {
        case .system: appearance = nil
        case .dark: appearance = NSAppearance(named: .darkAqua)
        case .light: appearance = NSAppearance(named: .aqua)
        }
        NSApp.appearance = appearance
        popover.appearance = appearance
        studioWindow?.appearance = appearance
        settingsWindow?.appearance = appearance
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        let rootView = MenuBarPopoverView(
            store: store,
            onPopoverHoverChange: { [weak self] hovering in
                self?.handlePopoverHover(hovering)
            },
            onOpenMainWindow: { [weak self] in
                self?.closePopover()
                self?.bringMainWindowToFront()
            },
            onOpenSettings: { [weak self] in
                self?.closePopover()
                self?.showSettingsWindow()
            }
        )
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleStatusButtonClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageLeading
        button.setAccessibilityTitle("LimitWidget")

        let trackingView = StatusBarHoverTrackingView(frame: button.bounds) { [weak self] hovering in
            self?.handleButtonHover(hovering)
        }
        trackingView.autoresizingMask = [.width, .height]
        button.addSubview(trackingView)

        updateStatusButtonAppearance()
    }

    // MARK: Observation

    private func observeStoreChanges() {
        withObservationTracking {
            _ = store.subscriptions
            _ = store.isSyncing
            _ = store.themeMode
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateStatusButtonAppearance()
                self.applyThemeAppearance()
                self.notifier.evaluate(
                    self.store.subscriptions,
                    threshold: self.preferences.alertThreshold,
                    isEnabled: self.preferences.notifiesNearLimit
                )
                self.observeStoreChanges()
            }
        }
    }

    private func observePreferenceChanges() {
        withObservationTracking {
            _ = preferences.menuBarDisplay
            _ = preferences.refreshInterval
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateStatusButtonAppearance()
                if self.appliedRefreshInterval != self.preferences.refreshInterval {
                    self.appliedRefreshInterval = self.preferences.refreshInterval
                    self.store.startAutoSync(interval: TimeInterval(self.preferences.refreshInterval))
                }
                self.observePreferenceChanges()
            }
        }
    }

    // MARK: Status item

    private func updateStatusButtonAppearance() {
        guard let button = statusItem.button else { return }
        let peak = store.highestUsagePercentage
        let hasActive = !store.activeSubscriptions.isEmpty
        let severity = UsageTone.severity(forRatio: Double(peak) / 100)

        button.image = MenuBarGaugeImage.make(ratio: hasActive ? Double(peak) / 100 : 0)

        if preferences.menuBarDisplay == .peakPercent && hasActive {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
                .baselineOffset: 0.5
            ]
            if severity == .critical {
                attributes[.foregroundColor] = NSColor.systemRed
            }
            button.attributedTitle = NSAttributedString(string: " %\(peak)", attributes: attributes)
        } else {
            button.attributedTitle = NSAttributedString(string: "")
        }

        let summaryLines = store.activeSubscriptions.map { item in
            "\(item.providerName): \(item.percentText)"
        }
        button.toolTip = summaryLines.isEmpty ? "LimitWidget" : summaryLines.joined(separator: "\n")
    }

    @objc private func handleStatusButtonClick(_ sender: Any?) {
        hoverOpenTask?.cancel()
        hoverCloseTask?.cancel()

        if NSApp.currentEvent?.type == .rightMouseUp {
            closePopover()
            showStatusMenu()
            return
        }

        if popover.isShown {
            if isPinnedByClick {
                closePopover()
            } else {
                isPinnedByClick = true
            }
        } else {
            isPinnedByClick = true
            showPopover()
        }
    }

    private func showStatusMenu() {
        guard let button = statusItem.button else { return }
        let menu = NSMenu()

        let open = NSMenuItem(title: "LimitWidget'ı Aç", action: #selector(menuOpenMainWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let refresh = NSMenuItem(title: "Şimdi Yenile", action: #selector(menuRefresh), keyEquivalent: "r")
        refresh.target = self
        refresh.isEnabled = !store.isSyncing
        menu.addItem(refresh)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Ayarlar…", action: #selector(menuOpenSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "LimitWidget'tan Çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
    }

    @objc private func menuOpenMainWindow() { bringMainWindowToFront() }
    @objc private func menuOpenSettings() { showSettingsWindow() }
    @objc private func menuRefresh() { Task { await store.syncLocalUsageAsync() } }

    // MARK: Hover

    private func handleButtonHover(_ hovering: Bool) {
        isPointerInButton = hovering
        guard preferences.opensOnHover else { return }
        if hovering {
            hoverCloseTask?.cancel()
            guard !popover.isShown else { return }
            hoverOpenTask?.cancel()
            hoverOpenTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled, let self, self.isPointerInButton else { return }
                self.isPinnedByClick = false
                self.showPopover()
            }
        } else {
            hoverOpenTask?.cancel()
            scheduleAutoCloseIfNeeded()
        }
    }

    private func handlePopoverHover(_ hovering: Bool) {
        isPointerInPopover = hovering
        if hovering {
            hoverCloseTask?.cancel()
        } else {
            scheduleAutoCloseIfNeeded()
        }
    }

    private func scheduleAutoCloseIfNeeded() {
        guard !isPinnedByClick else { return }
        hoverCloseTask?.cancel()
        hoverCloseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled,
                  let self,
                  !self.isPinnedByClick,
                  !self.isPointerInButton,
                  !self.isPointerInPopover else {
                return
            }
            self.closePopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func closePopover() {
        isPinnedByClick = false
        if popover.isShown {
            popover.performClose(nil)
        }
    }

    // MARK: Windows

    func bringMainWindowToFront() {
        NSApp.setActivationPolicy(.accessory)
        if let existing = studioWindow {
            if existing.isMiniaturized {
                existing.deminiaturize(nil)
            }
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let hosting = NSHostingController(
            rootView: MainWindowView(store: store, onOpenSettings: { [weak self] in
                self?.showSettingsWindow()
            })
            .background {
                WindowBackdrop()
                    .ignoresSafeArea()
            }
        )
        hosting.sizingOptions = [.preferredContentSize]
        hosting.sceneBridgingOptions = [.toolbars, .title]

        let window = NSWindow(contentViewController: hosting)
        window.title = "LimitWidget"
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("LimitWidgetMainWindow")
        if let minimizeButton = window.standardWindowButton(.miniaturizeButton) {
            minimizeButton.target = self
            minimizeButton.action = #selector(hideWindowToMenuBar(_:))
        }
        window.appearance = NSApp.appearance
        if !window.setFrameUsingName("LimitWidgetMainWindow") {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        studioWindow = window
    }

    func showSettingsWindow() {
        NSApp.setActivationPolicy(.accessory)
        if let existing = settingsWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let hosting = NSHostingController(
            rootView: SettingsView(store: store, preferences: preferences)
        )
        hosting.sizingOptions = [.preferredContentSize]

        let window = NSWindow(contentViewController: hosting)
        window.title = "Ayarlar"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.appearance = NSApp.appearance
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        settingsWindow = window
    }

    @objc private func hideWindowToMenuBar(_ sender: Any?) {
        let targetWindow = (sender as? NSButton)?.window ?? studioWindow
        targetWindow?.orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    func popoverDidClose(_ notification: Notification) {
        isPinnedByClick = false
        isPointerInPopover = false
    }
}

// MARK: - Window backdrop

/// Ana pencerenin arkasında masaüstünü buzlu camla gösteren zemin.
private struct WindowBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Menu bar gauge

/// Menü çubuğu için şablon (tek renk) halka göstergesi çizer; sistem rengine kendiliğinden uyar.
enum MenuBarGaugeImage {
    static func make(ratio: Double) -> NSImage {
        let clamped = min(max(ratio, 0), 1)
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let lineWidth: CGFloat = 2.2
            let inset = lineWidth / 2 + 0.75
            let circleRect = rect.insetBy(dx: inset, dy: inset)
            let center = NSPoint(x: circleRect.midX, y: circleRect.midY)
            let radius = circleRect.width / 2

            let track = NSBezierPath(ovalIn: circleRect)
            track.lineWidth = lineWidth
            NSColor.black.withAlphaComponent(0.3).setStroke()
            track.stroke()

            if clamped > 0 {
                let arc = NSBezierPath()
                arc.appendArc(
                    withCenter: center,
                    radius: radius,
                    startAngle: 90,
                    endAngle: 90 - 360 * clamped,
                    clockwise: true
                )
                arc.lineWidth = lineWidth
                arc.lineCapStyle = .round
                NSColor.black.setStroke()
                arc.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "LimitWidget"
        return image
    }
}

// MARK: - Hover tracking

/// Tıklamaları engellemeden (`hitTest -> nil`) menü çubuğu düğmesi üzerindeki fare giriş/çıkışlarını izler.
private final class StatusBarHoverTrackingView: NSView {
    private let onHoverChange: (Bool) -> Void
    private var trackingAreaRef: NSTrackingArea?

    init(frame frameRect: NSRect, onHoverChange: @escaping (Bool) -> Void) {
        self.onHoverChange = onHoverChange
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingAreaRef {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHoverChange(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverChange(false)
    }
}
