# LimitWidget Studio

macOS için geliştirilmiş; **Claude Code**, **Antigravity**, **Codex** ve **OpenCode** yapay zeka aboneliklerinin canlı kota ve kullanım oranlarını hem **Üst Menü Çubuğu (Hover & Popover)** hem **Stüdyo Yönetim Konsolu** hem de **Masaüstü WidgetKit** eklentisi üzerinden takip eden yerel SwiftUI uygulaması.

## Özellikler

- **Gerçek Zamanlı Canlı Kota Okuyucular (`LocalUsageCollector`)**:
  - **Claude Code**: `claude` CLI `get_usage` kontrol protokolü (ve `plan-usage-history.json` / proje günlükleri yedeği) ile 5 saatlik, haftalık ve model bazlı kotalar.
  - **Antigravity**: Yerel OmniRoute OAuth oturumu ve Cloud Code `retrieveUserQuota` / `retrieveUserQuotaSummary` uç noktaları üzerinden Gemini ve Claude/GPT kotaları.
  - **Codex**: `codex app-server` `account/rateLimits/read` JSON-RPC protokolü (ve `state_5.sqlite` yedeği) üzerinden 5 saatlik ve haftalık Plus/Pro limitleri.
  - **OpenCode**: `~/.local/share/opencode/auth.json` ve `opencode.ai/zen/go/v1/usage` üzerinden 5 saatlik, haftalık ve aylık kullanım yüzdeleri.
- **Üst Menü Çubuğunda Hover Desteği (`StatusBarController`)**: Menü çubuğundaki `%` göstergesinin üzerine fareyle gelindiğinde tıklamaya gerek kalmadan aşağı doğru tüm sağlayıcıların oranlarını açar.
- **Dinamik Pencere Boyutu**: Kaydırma çubuğu gerektirmeden aktif sağlayıcı sayısına göre otomatik uzayan pencere ve açılır panel.
- **Stüdyo Tasarım Sistemi ve Tema Desteği (`StudioTheme`)**: Özel vektör sağlayıcı amblemleri, ölçek çentikli `StudioMeterBar`, alt pencere telemetri modülleri ve **Sistem / Koyu / Açık** tema seçenekleri.

## Derleme ve Test

```bash
xcodegen generate
xcodebuild -project LimitWidget.xcodeproj -scheme LimitWidget -destination 'platform=macOS' build test
```
