# Сборка iOS-версии Various VPN

> Нужен **Mac + Xcode** и **аккаунт Apple Developer** ($99/год) — без них iOS-приложение
> с VPN ни собрать, ни установить нельзя (ограничение Apple). Код уже готов;
> остаётся нативная сборка на Mac.

## 0. Что уже сделано (в этом репозитории)
- Dart-мост к iOS-VPN: `lib/services/vpn_core_ios.dart` + `xray_link.dart`.
- Нативный Swift: `Runner/VPNManager.swift`, `Runner/AppDelegate.swift`,
  расширение `PacketTunnelProvider/…`, entitlements, Info.plist, Podfile.
- Скрипт подключения расширения к проекту: `setup_ios_extension.rb`.

## 1. Первичная подготовка (один раз, на Mac)
```bash
cd various_vpn
flutter pub get
cd ios
sudo gem install xcodeproj      # для скрипта
ruby setup_ios_extension.rb     # добавит таргет PacketTunnelProvider в проект
pod install                     # поставит Flutter-поды
```

## 2. Подключить VPN-ядро (бинарники)
Расширению нужны две нативные библиотеки (собираются из Go/C, кладутся в таргет
`PacketTunnelProvider`):

1. **libXray.xcframework** — Xray-core (github.com/XTLS/libXray, сборка через
   `gomobile bind`). Запускает Xray с нашим JSON-конфигом.
2. **hev-socks5-tunnel** (xcframework) — качает пакеты utun ↔ локальный SOCKS.

В Xcode: выбери таргет `PacketTunnelProvider` → *General → Frameworks and
Libraries* → добавь оба `.xcframework` (Embed & Sign).

После этого в `XrayCore.swift` ветки `#if canImport(LibXray)` /
`#if canImport(HevSocks5Tunnel)` включатся автоматически. Допиши точные имена
функций под свой форк libXray (там есть пример в комментариях).

## 3. Подписание
В Xcode (`Runner.xcworkspace`):
- Открой таргеты **Runner** и **PacketTunnelProvider** → *Signing & Capabilities*.
- Выбери свою **Team**, включи автоподпись.
- Bundle id: `com.example.variousVpn` и `com.example.variousVpn.PacketTunnel`
  (или замени `com.example.variousVpn` на свой во всех местах — заодно в
  `VPNManager.swift` `VPNConst` и в обоих `*.entitlements` / App Group).
- Проверь Capability **App Groups** = `group.com.example.variousVpn` в обоих таргетах.
- Capability **Network Extensions** (Packet Tunnel) должна быть у обоих.

## 4. Сборка/запуск
```bash
flutter run --release            # на подключённый iPhone
# или архив в Xcode → TestFlight/App Store
```

## Что НЕ переносится на iOS (ограничения платформы)
- **Per-app split** (правила по приложениям) — iOS не даёт per-app VPN обычным
  приложениям. Экран «Приложения» на iOS покажет пояснение вместо списка.
- **Домашний Android-виджет** — на iOS нужен отдельный WidgetKit-таргет (можно
  добавить позже).
- **Мультихоп** (цепочка relay→exit) — в первой iOS-версии идём одним хопом.

Всё остальное (подключение, роутинг обхода РФ/ИИ/AdBlock/фрагментация,
бесплатный режим «только Telegram», импорт подписки, папки, пинги, QR, стрик,
ИИ-режим, весь UI) работает так же, как на Android.
