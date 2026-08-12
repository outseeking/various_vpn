/// Конструктор экранов настроек: сгруппированные карточки вместо голого
/// списка ListTile.
///
/// Было: ~25 строк подряд, разделённых только заголовками, все одинакового
/// веса — глаз не за что зацепить, найти нужное можно только перечитав всё.
/// Стало: короткие группы в скруглённых карточках, у каждой строки — цветная
/// иконка-плашка. Так работают все премиальные приложения: группа читается
/// целиком, а не построчно.
library;

import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/motion.dart';
import 'tap_scale.dart';
import 'ios_switch.dart';

/// Заголовок раздела над карточкой.
class SettingsHeader extends StatelessWidget {
  final String text;
  final IconData? icon;
  const SettingsHeader(this.text, {super.key, this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 22, 6, 8),
      child: Row(children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: P.limeText),
          const SizedBox(width: 6),
        ],
        Text(text.toUpperCase(),
            style: const TextStyle(
                color: P.limeText,
                fontSize: 11,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// Карточка-группа: строки внутри разделены тонкими линиями, углы скруглены.
class SettingsGroup extends StatelessWidget {
  final List<Widget> children;
  const SettingsGroup({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        // Линия начинается после иконки — так группа выглядит цельной,
        // а не нарезанной на равные полосы.
        rows.add(const Padding(
          padding: EdgeInsets.only(left: 58),
          child: Divider(height: 1, thickness: 1, color: P.surfaceHi),
        ));
      }
      rows.add(children[i]);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: P.surfaceLo,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: P.surfaceHi),
        ),
        child: Column(children: rows),
      ),
    );
  }
}

/// Цветная иконка-плашка слева от строки. Оттенок задаётся вызывающим кодом,
/// чтобы разделы читались с одного взгляда, но все — из фирменной гаммы.
class SettingsIcon extends StatelessWidget {
  final IconData icon;
  final Color tint;
  const SettingsIcon(this.icon, {super.key, this.tint = P.limeText});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: tint.withValues(alpha: 0.22)),
      ),
      child: Icon(icon, size: 17, color: tint),
    );
  }
}

/// Строка-переход на другой экран (со стрелкой) или действие.
class SettingsRow extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String title;
  final String? subtitle;

  /// Значение справа («3 ч», «TCP»).
  final String? value;
  final VoidCallback onTap;

  /// Заблокировано подпиской: замок вместо стрелки, строка приглушена.
  final bool locked;

  /// Опасное действие (выход, удаление) — красным.
  final bool danger;

  /// Показывать стрелку. false — для действий, которые ничего не открывают.
  final bool chevron;

  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.tint = P.limeText,
    this.subtitle,
    this.value,
    this.locked = false,
    this.danger = false,
    this.chevron = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? P.danger : P.text;
    final row = Padding(
      // 52 по высоте с запасом: минимальная цель нажатия 48dp (Material).
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      child: Row(children: [
        SettingsIcon(icon, tint: danger ? P.danger : tint),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      color: color,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!,
                    style: const TextStyle(
                        color: P.textFaint, fontSize: 12, height: 1.3)),
              ],
            ],
          ),
        ),
        if (value != null) ...[
          const SizedBox(width: 8),
          Text(value!,
              style: const TextStyle(
                  color: P.textDim,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600)),
        ],
        if (locked)
          const Padding(
            padding: EdgeInsets.only(left: 6),
            child: Icon(Icons.lock_outline, color: P.textFaint, size: 16),
          )
        else if (chevron)
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child:
                Icon(Icons.chevron_right_rounded, color: P.textFaint, size: 20),
          ),
      ]),
    );

    return TapScale(
      onTap: onTap,
      scale: 0.985,
      child: locked ? Opacity(opacity: 0.45, child: row) : row,
    );
  }
}

/// Строка с тумблером. Тумблер и текст переключаются одним тапом по всей
/// строке — попадать пальцем именно в тумблер не нужно.
class SettingsSwitch extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool locked;

  /// Что показать, если строка заблокирована подпиской.
  final VoidCallback? onLockedTap;

  const SettingsSwitch({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.tint = P.limeText,
    this.subtitle,
    this.locked = false,
    this.onLockedTap,
  });

  @override
  Widget build(BuildContext context) {
    final on = locked ? false : value;
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      child: Row(children: [
        SettingsIcon(icon, tint: tint),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: P.text,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!,
                    style: const TextStyle(
                        color: P.textFaint, fontSize: 12, height: 1.3)),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        if (locked)
          const Icon(Icons.lock_outline, color: P.textFaint, size: 16)
        else
          IosSwitch(value: on, onChanged: onChanged),
      ]),
    );

    if (locked) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onLockedTap,
        child: Opacity(opacity: 0.45, child: row),
      );
    }
    // Тап по всей строке = переключение. Без TapScale: «вжимание» строки с
    // тумблером выглядит как нажатие тумблера, хотя это не так.
    return InkWell(
      onTap: () => onChanged(!value),
      splashColor: P.lime.withValues(alpha: 0.06),
      highlightColor: P.lime.withValues(alpha: 0.04),
      child: row,
    );
  }
}

/// Строка с раскрывающимся содержимым (плавно, без прыжка вёрстки).
class SettingsExpand extends StatefulWidget {
  final IconData icon;
  final Color tint;
  final String title;
  final String? subtitle;
  final Widget child;
  const SettingsExpand({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.tint = P.limeText,
    this.subtitle,
  });

  @override
  State<SettingsExpand> createState() => _SettingsExpandState();
}

class _SettingsExpandState extends State<SettingsExpand> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TapScale(
        onTap: () => setState(() => _open = !_open),
        scale: 0.985,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          child: Row(children: [
            SettingsIcon(widget.icon, tint: widget.tint),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title,
                      style: const TextStyle(
                          color: P.text,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600)),
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(widget.subtitle!,
                        style: const TextStyle(
                            color: P.textFaint, fontSize: 12, height: 1.3)),
                  ],
                ],
              ),
            ),
            AnimatedRotation(
              turns: _open ? 0.5 : 0,
              duration: M.state,
              curve: M.standard,
              child: const Icon(Icons.keyboard_arrow_down_rounded,
                  color: P.textFaint, size: 22),
            ),
          ]),
        ),
      ),
      AnimatedSize(
        duration: M.state,
        curve: M.standard,
        alignment: Alignment.topCenter,
        child: _open
            ? Padding(
                padding: const EdgeInsets.fromLTRB(13, 0, 13, 13),
                child: widget.child,
              )
            : const SizedBox(width: double.infinity),
      ),
    ]);
  }
}
