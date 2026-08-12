//  Palette.swift
//  Те же цвета, что и в приложении (lib/theme/app_palette.dart).
//
//  Продублированы намеренно: виджет и Live Activity рисует система в своём
//  процессе, до Flutter она не достучится. Значения держим здесь одним местом,
//  чтобы при смене фирменного цвета правилась одна строка, а не десять.

import SwiftUI

enum VVColor {
    static let bg = Color(red: 0.016, green: 0.024, blue: 0.043)      // #04060B
    static let surface = Color(red: 0.047, green: 0.075, blue: 0.141) // #0C1324
    static let lime = Color(red: 0.561, green: 0.808, blue: 0.106)    // #8FCE1B
    static let limeText = Color(red: 0.706, green: 0.886, blue: 0.306)// #B4E24E
    static let violet = Color(red: 0.420, green: 0.204, blue: 0.722)  // #6B34B8
    static let onLime = Color(red: 0.039, green: 0.063, blue: 0.016)  // #0A1004
    static let textDim = Color.white.opacity(0.70)
    static let textFaint = Color.white.opacity(0.45)

    /// Фирменный градиент: лайм → фиолет, тот же угол, что и в приложении.
    static let grad = LinearGradient(
        colors: [lime, violet],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
