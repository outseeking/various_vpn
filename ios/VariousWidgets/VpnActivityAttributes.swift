//  VpnActivityAttributes.swift
//  Описание «живого» события для Dynamic Island и экрана блокировки.
//
//  Файл компилируется В ОБА таргета — и в приложение, и в расширение виджетов.
//  Иначе система не сопоставит событие, запущенное приложением, с оформлением
//  из расширения: она сверяет их по имени типа.
//
//  Делится на две части не для порядка: attributes задаются один раз при
//  запуске события, а ContentState система разрешает обновлять сколько угодно.
//  Всё, что меняется по ходу подключения, обязано лежать во второй части.

import Foundation

#if canImport(ActivityKit)
import ActivityKit

@available(iOS 16.1, *)
struct VpnActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var connected: Bool
        var status: String
        var server: String
        var countryCode: String
        var ping: String
        /// Скорости строкой, уже с единицами: считать их в расширении нечем, а
        /// правила округления должны совпадать с теми, что в приложении.
        var up: String
        var down: String
        /// Когда подключились. По этой точке система сама тикает секундами —
        /// расширению не нужно просыпаться раз в секунду ради таймера.
        var since: Date?
    }

    /// Заголовок берётся из приложения, чтобы событие было на языке интерфейса.
    var appName: String
}
#endif
