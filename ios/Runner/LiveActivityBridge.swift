//  LiveActivityBridge.swift
//  Запуск и обновление живого события (Dynamic Island + экран блокировки).
//
//  Оформление события живёт в расширении виджетов, а вот распоряжается им
//  только приложение: расширение само себя показать не может. Отсюда этот
//  тонкий слой — Dart говорит «подключились/отключились», остальное здесь.
//
//  Событие не открывается заново на каждое обновление. Это важно: система
//  разрешает ограниченное число запусков подряд и на частые перезапуски
//  отвечает отказом. Поэтому запускаем один раз, дальше — только обновляем.

import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

enum LiveActivityBridge {

    #if canImport(ActivityKit)
    @available(iOS 16.1, *)
    private static var current: Activity<VpnActivityAttributes>? {
        Activity<VpnActivityAttributes>.activities.first
    }
    #endif

    /// Показать или обновить событие. `connected == false` его завершает:
    /// висящая на экране блокировки карточка «отключено» — мусор, который
    /// человек вынужден убирать руками.
    static func push(_ args: [String: Any]) {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        // Разрешение выдаёт человек в настройках, и его может не быть. Тогда
        // просто ничего не делаем: приложение работает и без острова.
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let connected = args["connected"] as? Bool ?? false
        guard connected else { stop(); return }

        let sinceMs = args["sinceMs"] as? Double
        let state = VpnActivityAttributes.ContentState(
            connected: true,
            status: args["status"] as? String ?? "",
            server: args["server"] as? String ?? "",
            countryCode: args["cc"] as? String ?? "",
            ping: args["ping"] as? String ?? "",
            up: args["up"] as? String ?? "",
            down: args["down"] as? String ?? "",
            since: sinceMs.map { Date(timeIntervalSince1970: $0 / 1000) }
        )

        if let activity = current {
            Task { await activity.update(using: state) }
            return
        }

        let attrs = VpnActivityAttributes(
            appName: args["appName"] as? String ?? "Various VPN")
        // Запуск может не удаться — например, событий уже слишком много.
        // Это не повод падать: остров лишь дополняет приложение.
        _ = try? Activity.request(attributes: attrs, contentState: state,
                                  pushType: nil)
        #endif
    }

    static func stop() {
        #if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        for activity in Activity<VpnActivityAttributes>.activities {
            Task { await activity.end(dismissalPolicy: .immediate) }
        }
        #endif
    }
}
