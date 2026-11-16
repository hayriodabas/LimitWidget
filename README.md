# LimitWidget

macOS için menü çubuğunda yaşayan yapay zekâ kota izleyicisi. **Claude Code**, **Antigravity**, **Codex** ve **OpenCode** aboneliklerinin kalan kotasını menü çubuğunda, ana pencerede ve masaüstü widget'ında gösterir. macOS 26 ve sonrasında Liquid Glass görünümüyle çalışır.

## Özellikler

- **Menü çubuğu:** Halka gösterge ve en yüksek kullanım yüzdesi. Üzerine gelince (isteğe bağlı) ya da tıklayınca sistem cam panelinde tüm sağlayıcılar açılır; sağ tık menüsünden yenile, ayarlar ve çıkış.
- **Ana pencere:** Özet kartı (en yüksek kullanım, ortalama, sıradaki yenilenme) ve sağlayıcı listesi. Cam araç çubuğunda sıralama/filtre, yenile (⌘R), sağlayıcı ekle (⌘N) ve ayarlar (⌘,).
- **Sağlayıcı işlemleri:** Düzenle, ana kota dönemini değiştir (5 saatlik / haftalık / aylık), menü çubuğunda gizle, yukarı/aşağı taşı, onaylı silme.
- **Masaüstü widget'ı:** Küçük ve orta boyda Pil widget'ı düzeninde halkalar, büyük boyda satır listesi. Masaüstü tek renkli moddayken de okunur.
- **Ayarlar:** Tema (Sistem / Açık / Koyu), menü çubuğu gösterimi, yenileme sıklığı, kota eşiği bildirimi, oturum açılışında başlatma, varsayılan sağlayıcılara dönüş.
- **Canlı kota okuyucular (`LocalUsageCollector`):**
  - **Claude Code:** `claude` CLI kullanım sorgusu (yedek: `plan-usage-history.json` ve proje günlükleri).
  - **Antigravity:** Yerel OmniRoute OAuth oturumu ve Cloud Code kota uç noktaları.
  - **Codex:** `codex app-server` `account/rateLimits/read` (yedek: `state_5.sqlite`).
  - **OpenCode:** `~/.local/share/opencode/auth.json` ve `opencode.ai/zen/go/v1/usage`.

## Logolar

Sağlayıcı logoları [LobeHub Icons](https://github.com/lobehub/lobe-icons) koleksiyonundan (MIT) alınmıştır (`Shared/ProviderLogos.xcassets`). Logolar ve markalar sahiplerine (Anthropic, Google, OpenAI, OpenCode, Anysphere, GitHub, Windsurf, DeepSeek) aittir ve yalnızca ilgili hizmeti tanıtmak için kullanılır.

## Yapı

- `Shared/DesignSystem.swift` — renk tonları, sağlayıcı simgeleri, kullanım çubuğu ve halkası
- `Shared/ProviderRows.swift` — panel ve widget satırları
- `LimitWidgetApp/` — menü çubuğu denetleyicisi, ana pencere, ayarlar, tercihler ve bildirimler
- `LimitWidgetApp/AppIcon.icon` — Icon Composer biçiminde cam uygulama simgesi
- `LimitWidgetExtension/` — WidgetKit masaüstü widget'ı

## Derleme, test ve kurulum

```bash
xcodegen generate
xcodebuild -project LimitWidget.xcodeproj -scheme LimitWidget -destination 'platform=macOS' -derivedDataPath .derivedData build test
xcodebuild -project LimitWidget.xcodeproj -scheme LimitWidget -configuration Release -destination 'platform=macOS' -derivedDataPath .derivedData build
ditto .derivedData/Build/Products/Release/LimitWidget.app /Applications/LimitWidget.app
```
