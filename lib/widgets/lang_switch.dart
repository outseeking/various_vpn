/// Компактный переключатель языка RU/EN для ПЕРВЫХ экранов (онбординг, вход).
///
/// Раньше язык менялся только в настройках — то есть уже после того, как
/// человек прошёл весь онбординг на чужом языке. Теперь тумблер доступен с
/// первого запуска и стоит в углу, не отвлекая от главного действия.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_palette.dart';
import 'tap_scale.dart';

class LangSwitch extends StatelessWidget {
  const LangSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final ru = state.lang != 'en';

    Widget seg(String code, String label, bool active) => TapScale(
          onTap: active ? null : () => state.setLang(code),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: active ? P.lime : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: active ? P.onLime : P.textFaint,
              ),
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: P.surfaceLo,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: P.surfaceHi),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        seg('ru', 'RU', ru),
        seg('en', 'EN', !ru),
      ]),
    );
  }
}
