//  VariousWidgetsBundle.swift
//  Точка входа расширения: перечисляет всё, что оно умеет показывать.
//
//  Живое событие добавляется только начиная с iOS 16.1 — на более ранних
//  версиях типа ActivityKit просто нет, и упоминание его в списке не даст
//  расширению собраться. Отсюда проверка версии прямо в теле.

import SwiftUI
import WidgetKit

/// Общая группа приложения и его расширений. Через неё передаётся состояние:
/// напрямую в чужой процесс заглянуть нельзя.
///
/// Собирается от адреса ПРИЛОЖЕНИЯ, а не пишется строкой. При установке в
/// обход магазина программы вроде Sideloadly переименовывают приложение под
/// учётную запись, которой подписывают, и расширения вместе с ним. Записанная
/// строка после этого указывает в пустоту: виджет читает чужой контейнер и
/// показывает «откройте приложение», сколько бы раз его ни открывали.
///
/// Своё имя у расширения — это адрес приложения плюс суффикс, поэтому суффикс
/// и отрезаем.
let appGroup: String = {
    let own = Bundle.main.bundleIdentifier ?? "site.ugconnect.variousvpn"
    let app = own.hasSuffix(".Widgets") ? String(own.dropLast(".Widgets".count)) : own
    return "group.\(app)"
}()

@main
struct VariousWidgetsBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        VariousStatusWidget()
        #if canImport(ActivityKit)
        if #available(iOSApplicationExtension 16.1, *) {
            VpnLiveActivity()
        }
        #endif
    }
}
