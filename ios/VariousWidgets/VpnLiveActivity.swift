//  VpnLiveActivity.swift
//  Оформление Dynamic Island и карточки на экране блокировки.
//
//  Три состояния острова — не три варианта одного и того же, а три разговора
//  разной длины:
//    • свёрнутое (точка сбоку от камеры) — есть ли защита вообще, одним значком;
//    • расширенное (палец задержали) — страна, задержка, скорости, время;
//    • минимальное (остров занят другим событием) — только значок.
//
//  Ширина свёрнутого состояния жёстко ограничена системой: всё, что длиннее
//  пары символов, там обрезается. Поэтому слева значок, справа — код страны, и
//  ничего больше.

import SwiftUI
import WidgetKit

#if canImport(ActivityKit)
import ActivityKit

@available(iOSApplicationExtension 16.1, *)
struct VpnLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VpnActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .padding(14)
                .background(VVColor.bg)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: s.connected ? "lock.shield.fill" : "shield.slash")
                            .foregroundColor(s.connected ? VVColor.limeText : VVColor.textFaint)
                        Text(flagEmoji(s.countryCode))
                    }
                    .font(.system(size: 16, weight: .bold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    // Время держит система по точке старта: расширение не
                    // просыпается ради каждой секунды и не тратит батарею.
                    if let since = s.since, s.connected {
                        Text(since, style: .timer)
                            .font(.system(size: 15, weight: .semibold,
                                          design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(VVColor.limeText)
                            .frame(maxWidth: 64)
                    } else if !s.ping.isEmpty {
                        Text(s.ping)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(VVColor.limeText)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(s.server)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 14) {
                        Label(s.down, systemImage: "arrow.down")
                        Label(s.up, systemImage: "arrow.up")
                        Spacer()
                        Text(s.status)
                            .foregroundColor(VVColor.textDim)
                            .lineLimit(1)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(VVColor.limeText)
                }
            } compactLeading: {
                Image(systemName: s.connected ? "lock.shield.fill" : "shield.slash")
                    .foregroundColor(s.connected ? VVColor.limeText : VVColor.textFaint)
            } compactTrailing: {
                Text(flagEmoji(s.countryCode))
            } minimal: {
                Image(systemName: s.connected ? "lock.shield.fill" : "shield.slash")
                    .foregroundColor(s.connected ? VVColor.limeText : VVColor.textFaint)
            }
            .keylineTint(VVColor.lime)
        }
    }
}

@available(iOSApplicationExtension 16.1, *)
private struct LockScreenView: View {
    let state: VpnActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: state.connected ? "lock.shield.fill" : "shield.slash")
                .font(.system(size: 26))
                .foregroundColor(state.connected ? VVColor.limeText : VVColor.textFaint)
            VStack(alignment: .leading, spacing: 3) {
                Text(state.status)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundColor(.white)
                HStack(spacing: 6) {
                    Text(flagEmoji(state.countryCode))
                    Text(state.server)
                        .font(.system(size: 12))
                        .foregroundColor(VVColor.textDim)
                        .lineLimit(1)
                }
                HStack(spacing: 12) {
                    Label(state.down, systemImage: "arrow.down")
                    Label(state.up, systemImage: "arrow.up")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(VVColor.limeText)
            }
            Spacer(minLength: 0)
            if let since = state.since, state.connected {
                Text(since, style: .timer)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(VVColor.limeText)
                    .frame(maxWidth: 68)
            }
        }
    }
}
#endif
