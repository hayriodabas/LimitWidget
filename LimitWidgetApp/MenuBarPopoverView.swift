import AppKit
import SwiftUI

/// Menü çubuğu simgesinden açılan panel. Arka planı sistemin cam paneline bırakır.
struct MenuBarPopoverView: View {
    @Bindable var store: SubscriptionStore
    var onPopoverHoverChange: ((Bool) -> Void)? = nil
    var onOpenMainWindow: (() -> Void)? = nil
    var onOpenSettings: (() -> Void)? = nil

    @State private var hoveredID: UUID?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(spacing: 0) {
                header(now: context.date)

                if store.activeSubscriptions.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 2) {
                        ForEach(store.activeSubscriptions) { subscription in
                            row(for: subscription, now: context.date)
                        }
                    }
                    .padding(.horizontal, 8)
                }

                Divider()
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                footer
            }
        }
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .preferredColorScheme(store.themeMode.preferredColorScheme)
        .onHover { hovering in
            onPopoverHoverChange?(hovering)
        }
    }

    // MARK: Header

    private func header(now: Date) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("LimitWidget")
                    .font(.system(size: 13, weight: .semibold))
                Text(updatedText(now: now))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            Spacer()

            Button {
                Task { await store.syncLocalUsageAsync() }
            } label: {
                Group {
                    if store.isSyncing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .frame(width: 20, height: 20)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .disabled(store.isSyncing)
            .keyboardShortcut("r", modifiers: .command)
            .help("Kotaları şimdi yenile (⌘R)")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private func updatedText(now: Date) -> String {
        if store.isSyncing { return "Kotalar okunuyor…" }
        let seconds = now.timeIntervalSince(store.lastRefreshedAt)
        if seconds < 60 { return "Az önce güncellendi" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) dk önce güncellendi" }
        return "\(store.lastRefreshedAt.formatted(date: .omitted, time: .shortened)) itibarıyla"
    }

    // MARK: Rows

    private func row(for subscription: AISubscription, now: Date) -> some View {
        let isHovered = hoveredID == subscription.id
        return Button {
            onOpenMainWindow?()
        } label: {
            ProviderSummaryRow(subscription: subscription, now: now)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
                )
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                hoveredID = hovering ? subscription.id : (hoveredID == subscription.id ? nil : hoveredID)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.secondary)
            Text("Takip edilen sağlayıcı yok")
                .font(.system(size: 13, weight: .semibold))
            Text("Ana pencereden bir sağlayıcı ekleyin.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Button("LimitWidget'ı Aç") {
                onOpenMainWindow?()
            }
            .buttonStyle(.glassProminent)
            .controlSize(.small)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 2) {
            footerButton("LimitWidget'ı Aç", systemImage: "macwindow") {
                onOpenMainWindow?()
            }

            Spacer()

            footerButton(nil, systemImage: "gearshape", help: "Ayarlar") {
                onOpenSettings?()
            }

            footerButton(nil, systemImage: "power", help: "LimitWidget'tan çık") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func footerButton(
        _ title: String?,
        systemImage: String,
        help: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        FooterButton(title: title, systemImage: systemImage, action: action)
            .help(help ?? title ?? "")
    }
}

/// Menü öğesi gibi üzerine gelince hafifçe vurgulanan alt çubuk düğmesi.
private struct FooterButton: View {
    let title: String?
    let systemImage: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 16)
                if let title {
                    Text(title)
                        .font(.system(size: 12.5))
                }
            }
            .foregroundStyle(isHovered ? .primary : .secondary)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
