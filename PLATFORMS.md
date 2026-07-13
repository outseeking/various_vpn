# Various VPN — Android и iOS в одном проекте

Одна кодовая база Flutter, но VPN-ядро у каждой ОС своё (иначе нельзя —
системные API разные). Ниже — что где лежит, чтобы **легко отличать платформы по
папкам**.

```
various_vpn/
├─ lib/                      ← общий Dart (UI, логика, подписка, роутинг) — ОБЕ ОС
│  └─ services/
│     ├─ vpn_service.dart        интерфейс VpnService (общий контракт)
│     ├─ vpn_core.dart           выбор реализации (web-stub / native)
│     ├─ vpn_core_native.dart    выбор по ОС: iOS→iOS, Android→Android
│     ├─ vpn_core_android.dart   ← ANDROID: flutter_v2ray (Xray), мультихоп, per-app, виджет
│     ├─ vpn_core_ios.dart       ← iOS: мост к NetworkExtension (MethodChannel)
│     ├─ xray_link.dart          ← iOS: сборка Xray-JSON из ссылки (на Android это делает flutter_v2ray)
│     └─ xray_config.dart        общий: роутинг (обход РФ / ИИ / AdBlock / фрагментация / free-TG)
│
├─ android/                 ← ВСЯ нативная часть ANDROID (Kotlin)
│  └─ app/src/main/kotlin/…      MainActivity, домашний виджет (VariousWidget*)
│
└─ ios/                     ← ВСЯ нативная часть iOS (Swift)
   ├─ Runner/
   │  ├─ AppDelegate.swift       мост Flutter↔VPN (MethodChannel/EventChannel)
   │  ├─ VPNManager.swift        управление профилем NETunnelProviderManager
   │  └─ Runner.entitlements     App Group + NetworkExtension
   ├─ PacketTunnelProvider/      ← РАСШИРЕНИЕ: тут реально живёт VPN на iOS
   │  ├─ PacketTunnelProvider.swift   utun + сетевые настройки
   │  ├─ XrayCore.swift               обёртки libXray + tun2socks (со стабами)
   │  ├─ Info.plist / *.entitlements
   ├─ Podfile
   ├─ setup_ios_extension.rb    скрипт подключения расширения к проекту (на Mac)
   └─ README_iOS.md             пошаговая сборка iOS
```

## Как это работает

| Возможность | Android | iOS |
|---|---|---|
| VPN-ядро | `flutter_v2ray` (Xray, встроен) | libXray в NetworkExtension |
| Xray-конфиг из ссылки | делает flutter_v2ray | делает `xray_link.dart` (Dart) |
| Роутинг (обход РФ, ИИ, AdBlock, фрагментация, free-Telegram) | `xray_config.dart` | тот же `xray_config.dart` ✅ |
| Мультихоп (цепочка) | ✅ | ⚠️ пока один хоп |
| Per-app split (правила по приложениям) | ✅ | ❌ iOS так не умеет (системное ограничение) |
| Домашний виджет | ✅ (Android widget) | ❌ (нужен WidgetKit — отдельно) |
| Импорт подписки, папки, пинги, QR, стрик, ИИ-режим, UI | ✅ | ✅ |

Всё, что **можно** сохранить на iOS — сохранено. Отпадают только вещи, которые
iOS не поддерживает в принципе (per-app VPN, Android-виджет).

## Сборка

- **Android:** `flutter build apk --release` (как раньше, ничего не менялось).
- **iOS (на Mac):** нужен Mac + Xcode + аккаунт Apple Developer. Шаги — в `ios/README_iOS.md`.
- **iOS без своего Mac — облачная сборка (GitHub Actions):**
  `.github/workflows/ci.yml`, job **Build iOS (no codesign)** собирает
  Flutter-iOS-приложение на облачном macOS. Пушишь код с Windows → в облаке
  проверяется, что iOS-версия **компилируется** (весь Dart-мост + Runner).
  Артефакт — неподписанный `Runner.app`. Установка на реальный iPhone/TestFlight
  требует аккаунта Apple Developer (подпись). CI также собирает Android APK и
  гоняет `flutter analyze` + `flutter test`.

Общий Dart-код компилируется под обе ОС; платформенные файлы подхватываются
автоматически (`Platform.isIOS` / `Platform.isAndroid` в `vpn_core_native.dart`).
