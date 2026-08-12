//  VpnState.swift
//  Чтение состояния VPN, которое приложение кладёт в общую группу.
//
//  Ключи — те же, что уже пишет Dart (lib/services/home_widget_sync.dart) для
//  домашнего виджета Android. Один набор на обе системы: иначе одно и то же
//  состояние описывалось бы дважды и рано или поздно разошлось бы.
//
//  Приставка «flutter.» не наша выдумка: её добавляет плагин home_widget,
//  когда сохраняет значение. Читать надо ровно с ней.

import Foundation

struct VpnState {
    var connected: Bool
    var status: String
    var server: String
    var ping: String
    var countryCode: String
    /// Бесплатный режим: сервер подбирается сам, работает только Telegram.
    var free: Bool
    var hasServer: Bool

    /// Что показать, пока приложение ни разу не запускали. Не «ошибка» и не
    /// пустой экран: виджет мог попасть на домашний экран раньше первого
    /// запуска, и он обязан выглядеть осмысленно.
    static let placeholder = VpnState(
        connected: false, status: "Не подключено", server: "Откройте приложение",
        ping: "", countryCode: "", free: false, hasServer: false
    )

    static func load(group: String) -> VpnState {
        guard let d = UserDefaults(suiteName: group) else { return .placeholder }
        func s(_ k: String) -> String { d.string(forKey: "flutter.\(k)") ?? "" }
        func b(_ k: String) -> Bool { s(k) == "true" }

        let status = s("vv_status")
        if status.isEmpty { return .placeholder }

        return VpnState(
            connected: b("vv_connected"),
            status: status,
            server: s("vv_server"),
            ping: s("vv_ping"),
            countryCode: s("vv_cc"),
            free: b("vv_free"),
            hasServer: b("vv_has_server")
        )
    }
}

/// Флаг страны эмодзи из кода вида «NL».
///
/// Собирается из символов-индикаторов: буква A соответствует U+1F1E6, дальше по
/// алфавиту. Так флаг рисует сама система — не нужны ни картинки в бандле, ни
/// перерисовка при смене темы.
func flagEmoji(_ code: String) -> String {
    let c = code.uppercased()
    guard c.count == 2 else { return "" }
    var out = ""
    for ch in c.unicodeScalars {
        guard ch.value >= 65, ch.value <= 90 else { return "" }
        out.unicodeScalars.append(UnicodeScalar(127397 + ch.value)!)
    }
    return out
}
