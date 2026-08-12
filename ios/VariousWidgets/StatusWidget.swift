//  StatusWidget.swift
//  Виджет на домашний экран — во всех размерах, которые даёт система.
//
//  Размеры не копии друг друга с разным шрифтом: в маленьком помещается только
//  главное (защищён или нет), в среднем — ещё страна и задержка, в большом —
//  подсказка, что делать дальше. Отдельно сделаны «дополнительные» размеры для
//  экрана блокировки: там доступен лишь силуэт, поэтому цвет не используется.
//
//  Кнопки включения здесь нет намеренно. Поднять туннель можно только из
//  приложения — система спрашивает разрешение и показывает свой запрос, а
//  виджету такого не позволено. Поэтому нажатие просто открывает приложение.

import SwiftUI
import WidgetKit

struct VpnEntry: TimelineEntry {
    let date: Date
    let state: VpnState
}

struct VpnProvider: TimelineProvider {
    func placeholder(in context: Context) -> VpnEntry {
        VpnEntry(date: Date(), state: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (VpnEntry) -> Void) {
        completion(VpnEntry(date: Date(), state: VpnState.load(group: appGroup)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VpnEntry>) -> Void) {
        // Обновления присылает само приложение при каждой смене состояния, а
        // расписание тут — страховка на случай, если его выгрузили из памяти.
        // Раз в 15 минут: чаще система всё равно не пустит.
        let entry = VpnEntry(date: Date(), state: VpnState.load(group: appGroup))
        let next = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - разметка

private struct StatusDot: View {
    let on: Bool
    var body: some View {
        Circle()
            .fill(on ? VVColor.lime : Color.white.opacity(0.28))
            .frame(width: 9, height: 9)
            // Свечение только у включённого: у выключенного оно читалось бы
            // как «что-то происходит».
            .shadow(color: on ? VVColor.lime.opacity(0.7) : .clear, radius: 5)
    }
}

private struct SmallView: View {
    let s: VpnState
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                StatusDot(on: s.connected)
                Text("VPN")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(VVColor.textFaint)
                Spacer()
                if !s.countryCode.isEmpty && s.hasServer {
                    Text(flagEmoji(s.countryCode)).font(.system(size: 14))
                }
            }
            Spacer(minLength: 0)
            Text(s.status)
                .font(.system(size: 17, weight: .heavy))
                .foregroundColor(s.connected ? VVColor.limeText : .white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(s.server)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(VVColor.textDim)
                .lineLimit(1)
        }
    }
}

private struct MediumView: View {
    let s: VpnState
    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    StatusDot(on: s.connected)
                    Text(s.status)
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundColor(s.connected ? VVColor.limeText : .white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Text(s.server)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(VVColor.textDim)
                    .lineLimit(1)
                if !s.ping.isEmpty {
                    Text(s.ping)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(VVColor.limeText)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            // Флаг вместо картинки: рисует система, значит он не размывается на
            // любом экране и не тянет ресурсы в бандл.
            if !s.countryCode.isEmpty && s.hasServer {
                Text(flagEmoji(s.countryCode)).font(.system(size: 40))
            } else {
                Image(systemName: s.connected ? "lock.shield.fill" : "shield.slash")
                    .font(.system(size: 34))
                    .foregroundStyle(s.connected ? VVColor.grad
                                     : LinearGradient(colors: [VVColor.textFaint,
                                                               VVColor.textFaint],
                                                      startPoint: .top,
                                                      endPoint: .bottom))
            }
        }
    }
}

private struct LargeView: View {
    let s: VpnState
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MediumView(s: s)
            Divider().overlay(Color.white.opacity(0.10))
            // В большом размере есть место объяснить, что делать дальше. Пустое
            // место под уже сказанным ничего не добавляет.
            Text(s.connected
                 ? (s.free
                    ? "Бесплатный режим: работает только Telegram."
                    : "Трафик идёт через выбранный сервер.")
                 : "Откройте приложение, чтобы подключиться.")
                .font(.system(size: 13))
                .foregroundColor(VVColor.textDim)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text("Various VPN")
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(VVColor.textFaint)
        }
    }
}

/// Экран блокировки и «Смарт-стопка». Цвета там нет — только силуэт, поэтому
/// смысл несут форма значка и текст, а не оттенок.
@available(iOSApplicationExtension 16.0, *)
private struct AccessoryView: View {
    let s: VpnState
    let family: WidgetFamily
    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: s.connected ? "lock.shield.fill" : "shield.slash")
                    .font(.system(size: 20, weight: .bold))
            }
        case .accessoryInline:
            Label(s.connected ? s.server : s.status,
                  systemImage: s.connected ? "lock.shield.fill" : "shield.slash")
        default:
            VStack(alignment: .leading, spacing: 1) {
                Text("VPN").font(.system(size: 12, weight: .heavy))
                Text(s.status).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                if !s.server.isEmpty {
                    Text(s.server).font(.system(size: 12)).lineLimit(1).opacity(0.8)
                }
            }
        }
    }
}

struct VariousWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: VpnEntry

    var body: some View {
        let s = entry.state
        Group {
            if #available(iOSApplicationExtension 16.0, *),
               family == .accessoryCircular || family == .accessoryInline
                || family == .accessoryRectangular {
                AccessoryView(s: s, family: family)
            } else {
                switch family {
                case .systemSmall: SmallView(s: s)
                case .systemLarge, .systemExtraLarge: LargeView(s: s)
                default: MediumView(s: s)
                }
            }
        }
        .vvContainerBackground(connected: s.connected)
    }
}

private extension View {
    /// Фон виджета. С iOS 17 система требует объявлять его особым способом и
    /// сама решает, показывать ли — на некоторых экранах фон убирают. На более
    /// старых версиях такого требования нет, поэтому красим обычным способом.
    @ViewBuilder
    func vvContainerBackground(connected: Bool) -> some View {
        let bg = LinearGradient(
            colors: connected
                ? [VVColor.surface, VVColor.bg]
                : [VVColor.bg, VVColor.bg],
            startPoint: .top, endPoint: .bottom)
        if #available(iOSApplicationExtension 17.0, *) {
            self.containerBackground(for: .widget) { bg }
        } else {
            self.padding(14).background(bg)
        }
    }
}

struct VariousStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VariousStatusWidget", provider: VpnProvider()) { entry in
            VariousWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Various VPN")
        .description("Состояние подключения и выбранный сервер.")
        .supportedFamilies(supportedFamilies)
    }

    private var supportedFamilies: [WidgetFamily] {
        var f: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]
        if #available(iOSApplicationExtension 16.0, *) {
            f += [.accessoryCircular, .accessoryRectangular, .accessoryInline]
        }
        return f
    }
}
