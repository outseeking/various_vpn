/// Шторка «нужна подписка» — самая частая точка продажи в приложении: её
/// видит каждый, кто тапнул по закрытой настройке или чужому серверу.
///
/// Раньше здесь был обычный AlertDialog с текстом и кнопкой «Купить». Это
/// худшее место, где можно сэкономить на дизайне: человек уже проявил интерес
/// (нажал на платное), а мы отвечали ему системным окном. Теперь — короткий
/// оффер: что даёт подписка, сколько стоит, и два пути (взять бесплатно /
/// войти, если уже оплатил).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../brand.dart';
import '../l10n.dart';
import '../services/backend_api.dart';
import '../state/app_state.dart';
import '../theme/app_palette.dart';
import 'connect_ways.dart';
import 'tap_scale.dart';
import 'app_toast.dart';

Future<void> showPaywallSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: P.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (_) => const _PaywallBody(),
  );
}

class _PaywallBody extends StatefulWidget {
  const _PaywallBody();

  @override
  State<_PaywallBody> createState() => _PaywallBodyState();
}

class _PaywallBodyState extends State<_PaywallBody> {
  int _price = 200;

  @override
  void initState() {
    super.initState();
    BackendApi().minPlanPrice().then((p) {
      if (p != null && mounted) setState(() => _price = p);
    });
  }

  @override
  Widget build(BuildContext context) {
    final perks = [
      (Icons.public, L.t('pw_perk_countries')),
      (Icons.speed, L.t('pw_perk_speed')),
      (Icons.devices, L.t('pw_perk_devices')),
      (Icons.tune, L.t('pw_perk_settings')),
    ];

    return SafeArea(
      top: false,
      child: Padding(
        // Клавиатура поднимает шторку целиком: поле ввода ID не должно
        // прятаться под ней.
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: P.grad,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(Icons.workspace_premium,
                      color: P.onLime, size: 23),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(L.t('pw_title'),
                          style: const TextStyle(
                              color: P.text,
                              fontSize: 19,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(L.t('gs_from_price', {'p': _price}),
                          style: const TextStyle(
                              color: P.limeText,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 18),

              // Что именно откроется — конкретикой, а не «полный доступ».
              for (final (icon, text) in perks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 11),
                  child: Row(children: [
                    Icon(icon, size: 17, color: P.limeText),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(text,
                          style: const TextStyle(
                              color: P.textDim, fontSize: 13.5, height: 1.4)),
                    ),
                  ]),
                ),
              const SizedBox(height: 10),

              // Главное действие — забрать бесплатно, а не «купить»: платить
              // сразу на этом шаге человек ещё не готов.
              TapScale(
                onTap: () {
                  Navigator.pop(context);
                  launchUrl(Uri.parse(Brand.bot),
                      mode: LaunchMode.externalApplication);
                },
                haptic: true,
                scale: 0.975,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    gradient: P.grad,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                          color: P.lime.withValues(alpha: 0.30),
                          blurRadius: 22,
                          spreadRadius: -6,
                          offset: const Offset(0, 6)),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.card_giftcard,
                          size: 19, color: P.onLime),
                      const SizedBox(width: 9),
                      Text(L.t('pw_cta'),
                          style: const TextStyle(
                              color: P.onLime,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 9),
              Center(
                child: Text(L.t('pw_no_card'),
                    style: const TextStyle(color: P.textFaint, fontSize: 11.5)),
              ),
              const SizedBox(height: 16),

              // Уже оплатил — не заставляем идти в бота второй раз.
              _AlreadyPaid(),
            ],
          ),
        ),
      ),
    );
  }
}

/// «Уже есть подписка» — свёрнуто, чтобы не спорить с главным действием, но
/// в один тап: вернувшимся не нужно искать вход в настройках.
class _AlreadyPaid extends StatefulWidget {
  @override
  State<_AlreadyPaid> createState() => _AlreadyPaidState();
}

class _AlreadyPaidState extends State<_AlreadyPaid> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    if (!_open) {
      return Center(
        child: TextButton(
          onPressed: () => setState(() => _open = true),
          child: Text(L.t('pw_have_sub'),
              style: const TextStyle(color: P.textDim, fontSize: 13)),
        ),
      );
    }
    return ConnectWays(
      compact: true,
      onSuccess: () {
        if (!context.mounted) return;
        Navigator.pop(context);
        AppToast.ok(context, L.t('pw_unlocked'));
      },
    );
  }
}

/// Показывать ли платную шторку. Тем, кто пользуется своей (чужой) подпиской,
/// продавать наши серверы всё ещё уместно — но давить нечем: у них всё работает.
bool shouldPaywall(BuildContext context) => !context.read<AppState>().hasAccess;
