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
let appGroup = "group.site.ugconnect.variousvpn"

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
