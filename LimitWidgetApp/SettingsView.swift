import SwiftUI

/// Sistem Ayarları düzeninde gruplanmış uygulama ayarları.
struct SettingsView: View {
    @Bindable var store: SubscriptionStore
    @Bindable var preferences: AppPreferences
    @State private var showResetConfirmation = false

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Sürüm \(version) (\(build))"
    }

    var body: some View {
        Form {
            Section("Görünüm") {
                Picker("Tema", selection: Binding(
                    get: { store.themeMode },
                    set: { store.setThemeMode($0) }
                )) {
                    Text("Sistem").tag(AppThemeMode.system)
                    Text("Açık").tag(AppThemeMode.light)
                    Text("Koyu").tag(AppThemeMode.dark)
                }
                .pickerStyle(.segmented)

                Picker("Menü çubuğunda", selection: $preferences.menuBarDisplay) {
                    ForEach(AppPreferences.MenuBarDisplay.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }

                Toggle("Üzerine gelince paneli aç", isOn: $preferences.opensOnHover)
            }

            Section {
                Picker("Kotaları yenile", selection: $preferences.refreshInterval) {
                    ForEach(AppPreferences.refreshOptions, id: \.seconds) { option in
                        Text(option.title).tag(option.seconds)
                    }
                }
            } header: {
                Text("Güncelleme")
            } footer: {
                Text("Kotalar bilgisayarınızdaki Claude Code, Codex, Antigravity ve OpenCode araçlarından okunur. Hiçbir veri bu Mac'in dışına gönderilmez.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Kota dolmak üzereyken bildir", isOn: Binding(
                    get: { preferences.notifiesNearLimit },
                    set: { preferences.setNotifiesNearLimit($0) }
                ))

                Picker("Bildirim eşiği", selection: $preferences.alertThreshold) {
                    ForEach(AppPreferences.alertThresholdOptions, id: \.self) { value in
                        Text(AISubscription.percentText(value)).tag(value)
                    }
                }
                .disabled(!preferences.notifiesNearLimit)

                if let message = preferences.notificationMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Bildirimler")
            } footer: {
                Text("Her kota dönemi için en fazla bir bildirim gönderilir.")
                    .foregroundStyle(.secondary)
            }

            Section("Başlangıç") {
                Toggle("Oturum açıldığında başlat", isOn: Binding(
                    get: { preferences.launchesAtLogin },
                    set: { preferences.setLaunchesAtLogin($0) }
                ))

                if let message = preferences.launchAtLoginMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent("Varsayılan sağlayıcılar") {
                    Button("Geri Yükle…") {
                        showResetConfirmation = true
                    }
                }
            } header: {
                Text("Sağlayıcılar")
            } footer: {
                Text("Listeyi Claude Code, Antigravity, Codex ve OpenCode ile baştan kurar. Elle eklediğiniz sağlayıcılar silinir.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("LimitWidget", value: appVersion)
            }
        }
        .formStyle(.grouped)
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: 500, height: 800)
        .onAppear {
            preferences.refreshLaunchAtLoginStatus()
        }
        .confirmationDialog(
            "Varsayılan sağlayıcılar geri yüklensin mi?",
            isPresented: $showResetConfirmation
        ) {
            Button("Geri Yükle", role: .destructive) {
                store.resetToDefaults()
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Elle eklediğiniz sağlayıcılar silinir ve kotalar yeniden okunur.")
        }
    }
}
