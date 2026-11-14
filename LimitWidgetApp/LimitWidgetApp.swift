import AppKit
import Observation
import SwiftUI

/// LimitWidget ana uygulaması: üst menü çubuğunda üzerine gelindiğinde (hover) ve tıklandığında açılan
/// telemetri paneli ile içerik boyutuna göre otomatik uzayan stüdyo yönetim konsolu sunar.
@main
struct LimitWidgetApp: App {
    @State private var store: SubscriptionStore
    @State private var statusBarController: StatusBarController

    init() {
        let store = SubscriptionStore()
        store.startAutoSync(interval: 60)
        _store = State(initialValue: store)
        _statusBarController = State(initialValue: StatusBarController(store: store))
    }

    var body: some Scene {
        Window("LimitWidget Studio", id: "main") {
            MainWindowView(store: store)
                .frame(width: 880)
        }
        .windowResizability(.contentSize)
    }
}

/// Üst menü çubuğundaki `%XX` göstergesini yöneten, üzerine fareyle gelindiğinde (hover)
/// aşağı doğru tüm sağlayıcı oranlarını gösteren açılır panel denetleyicisi.
@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate, NSApplicationDelegate {
    private let store: SubscriptionStore
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var fallbackStudioWindow: NSWindow?
    private var isPinnedByClick = false
    private var isPointerInButton = false
    private var isPointerInPopover = false
    private var hoverOpenTask: Task<Void, Never>?
    private var hoverCloseTask: Task<Void, Never>?

    init(store: SubscriptionStore) {
        self.store = store
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()

        NSApplication.shared.delegate = self
        configurePopover()
        configureStatusButton()
        applyThemeAppearance()
        if let appIcon = NSImage(named: "AppIcon") {
            NSApplication.shared.applicationIconImage = appIcon
        }
        observeStoreChanges()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.bringMainWindowToFront()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            bringMainWindowToFront()
        }
        return true
    }

    private func applyThemeAppearance() {
        let appearance: NSAppearance?
        switch store.themeMode {
        case .system:
            appearance = nil
        case .dark:
            appearance = NSAppearance(named: .darkAqua)
        case .light:
            appearance = NSAppearance(named: .aqua)
        }
        NSApp.appearance = appearance
        popover.appearance = appearance
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

        let trackingView = StatusBarHoverTrackingView(frame: button.bounds) { [weak self] hovering in
            self?.handleButtonHover(hovering)
        }
        trackingView.autoresizingMask = [.width, .height]
        button.addSubview(trackingView)

        updateStatusButtonAppearance()
    }

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
                self.observeStoreChanges()
            }
        }
    }

    private func updateStatusButtonAppearance() {
        guard let button = statusItem.button else { return }
        let peak = store.highestUsagePercentage
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        button.image = NSImage(
            systemSymbolName: "chart.bar.xaxis",
            accessibilityDescription: "LimitWidget"
        )?.withSymbolConfiguration(symbolConfig)

        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        button.attributedTitle = NSAttributedString(
            string: " %\(peak)",
            attributes: [.font: font]
        )

        let summaryLines = store.activeSubscriptions.map { item in
            "\(item.providerName): %\(item.usagePercentage) (\(item.compactSummaryText))"
        }
        button.toolTip = summaryLines.isEmpty
            ? "LimitWidget Studio"
            : summaryLines.joined(separator: "\n")
    }

    @objc private func handleStatusButtonClick(_ sender: Any?) {
        hoverOpenTask?.cancel()
        hoverCloseTask?.cancel()

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

    private func handleButtonHover(_ hovering: Bool) {
        isPointerInButton = hovering
        if hovering {
            hoverCloseTask?.cancel()
            guard !popover.isShown else { return }
            hoverOpenTask?.cancel()
            hoverOpenTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(90))
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
            try? await Task.sleep(for: .milliseconds(260))
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

    private func bringMainWindowToFront() {
        NSApp.activate(ignoringOtherApps: true)
        if let existing = NSApp.windows.first(where: { $0.title.contains("LimitWidget") }) {
            existing.isReleasedWhenClosed = false
            existing.makeKeyAndOrderFront(nil)
            return
        }
        if let fallback = fallbackStudioWindow {
            fallback.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(
            rootView: MainWindowView(store: store).frame(width: 880)
        )
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = "LimitWidget Studio"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        fallbackStudioWindow = window
    }

    func popoverDidClose(_ notification: Notification) {
        isPinnedByClick = false
        isPointerInPopover = false
    }
}

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
