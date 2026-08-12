/// Настройки → Мои подписки. Одно место, где видно ВСЁ, чем человек
/// подключается: наша подписка и добавленные подписки других сервисов.
///
/// Раньше чужую подписку добавить было нельзя вовсе, а свою — только «куда-то
/// в приложение», без возможности потом посмотреть или убрать.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../brand.dart';
import '../l10n.dart';
import '../state/app_state.dart';
import '../theme/app_palette.dart';
import '../widgets/connect_ways.dart';
import '../widgets/settings_kit.dart';
import '../widgets/tap_scale.dart';
import '../widgets/app_toast.dart';
import '../services/storage.dart';

/// Строка «подпись — значение» в карточке подписки.
class _Fact extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _Fact(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Icon(icon, size: 16, color: P.textFaint),
        const SizedBox(width: 9),
        Text(label,
            style: const TextStyle(color: P.textFaint, fontSize: 12.5)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: P.text, fontSize: 13, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

class SubscriptionsScreen extends StatelessWidget {
  const SubscriptionsScreen({super.key});

  static String _host(String url) => Uri.tryParse(url)?.host ?? url;

  /// Заголовок строки: название сервиса, если он его прислал, иначе адрес.
  /// «📟 Pager VPN» человеку понятнее, чем «sub.pagervpn.ru».
  static String _title(AppState state, String url) {
    final t = state.foreignSubInfo(url)?.title ?? '';
    return t.isNotEmpty ? t : _host(url);
  }

  /// Подпись под чужой подпиской: серверы, срок и остаток трафика.
  /// Всё берётся из ответа самого сервиса; чего он не сообщил — не показываем.
  /// Выдумывать дату или подставлять срок НАШЕЙ подписки нельзя.
  static String _subtitle(AppState state, String url, int servers) {
    final parts = <String>[L.t('subs_servers', {'n': servers})];
    final until = state.foreignSubUntil(url);
    if (until != null) parts.add(L.t('subs_until', {'d': L.date(until)}));
    final info = state.foreignSubInfo(url);
    if (info != null && info.hasTraffic) {
      parts.add('${_gb(info.used)} / ${_gb(info.total)} ${L.t('unit_gb')}');
    }
    return parts.join(' · ');
  }

  static String _gb(int bytes) {
    final v = bytes / (1024 * 1024 * 1024);
    return v >= 10 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final foreignCount = state.servers.where((s) => s.foreign).length;

    return Scaffold(
      backgroundColor: P.bg,
      appBar: AppBar(title: Text(L.t('subs_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          // --- наша подписка ---
          SettingsHeader(L.t('subs_ours')),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: P.surfaceLo,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: state.subActive
                      ? P.lime.withValues(alpha: 0.4)
                      : P.surfaceHi),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(state.subActive ? Icons.verified : Icons.info_outline,
                      size: 19, color: state.subActive ? P.lime : P.textFaint),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                        state.subActive ? L.t('sub_active') : L.t('subs_none'),
                        style: TextStyle(
                            color: state.subActive ? P.lime : P.textDim,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700)),
                  ),
                ]),
                const SizedBox(height: 10),
                if (state.subActive) ...[
                  // Кто оформил и до какого числа — всё, что здесь нужно.
                  // Юзернейм понятнее числового ID: по нему сразу видно, свой
                  // это аккаунт или чужой.
                  _Fact(
                    icon: Icons.person_outline,
                    label: L.t('subs_owner'),
                    value: state.subUsername.isNotEmpty
                        ? '@${state.subUsername}'
                        : (Storage.instance.tgId ?? '—'),
                  ),
                  if (state.subUntil != null)
                    _Fact(
                      icon: Icons.event_outlined,
                      label: L.t('subs_until_label'),
                      value: L.date(state.subUntil!),
                    ),
                ] else
                  Text(L.t('subs_ours_off'),
                      style: const TextStyle(
                          color: P.textFaint, fontSize: 12.5, height: 1.45)),
                const SizedBox(height: 12),
                TapScale(
                  onTap: () => launchUrl(Uri.parse(Brand.bot),
                      mode: LaunchMode.externalApplication),
                  haptic: true,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      gradient: P.grad,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.workspace_premium,
                            size: 18, color: P.onLime),
                        const SizedBox(width: 8),
                        Text(
                            state.subActive
                                ? L.t('renew_cta')
                                : L.t('gs_plans'),
                            style: const TextStyle(
                                color: P.onLime,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // --- чужие подписки ---
          //
          // Раздел появляется, только когда чужая подписка действительно
          // добавлена. Пустая карточка «Пока ничего не добавлено» занимала
          // пол-экрана и рассказывала про функцию, которой человек не
          // пользуется, — сразу под сообщением, что своей подписки у него нет.
          if (state.foreignSubUrls.isNotEmpty) ...[
            SettingsHeader(L.t('subs_foreign')),
            SettingsGroup(
              children: [
                for (final url in state.foreignSubUrls)
                  SettingsRow(
                    icon: Icons.cloud_outlined,
                    tint: P.violetSoft,
                    title: _title(state, url),
                    // Срок — СВОЙ у каждой подписки, из её же ответа.
                    // Показывать здесь дату нашей подписки было бы прямым
                    // обманом: это чужой сервис со своими сроками.
                    subtitle: _subtitle(state, url, foreignCount),
                    chevron: false,
                    onTap: () => _confirmRemove(context, state, url),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.info_outline, size: 14, color: P.textFaint),
              const SizedBox(width: 7),
              Expanded(
                child: Text(L.t('subs_tap_remove'),
                    style: const TextStyle(color: P.textFaint, fontSize: 11.5)),
              ),
            ]),
            const SizedBox(height: 10),
            TapScale(
              // Обновление молчало: серверы могли обновиться, а могло и не
              // получиться — на экране в обоих случаях ничего не менялось, и
              // кнопка выглядела нерабочей. Теперь всегда отвечаем.
              onTap: state.busy
                  ? null
                  : () async {
                      final n = await state.refreshForeignSubs();
                      if (!context.mounted) return;
                      if (n < 0) {
                        AppToast.error(context, L.t('subs_refresh_fail'));
                      } else {
                        AppToast.ok(context, L.t('subs_refresh_ok', {'n': n}));
                      }
                    },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: P.surfaceHi),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (state.busy)
                      const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: P.limeText),
                      )
                    else
                      const Icon(Icons.refresh_rounded,
                          size: 17, color: P.limeText),
                    const SizedBox(width: 8),
                    Text(L.t('subs_refresh'),
                        style: const TextStyle(color: P.text, fontSize: 13.5)),
                  ],
                ),
              ),
            ),
          ],

          // --- добавить ---
          //
          // Только тем, кто ещё не подключился. Показывать «Уже есть подписка?
          // Войди по ID» человеку с активной подпиской — значит намекать, что
          // его вход не сработал.
          if (!state.subActive) ...[
            SettingsHeader(L.t('subs_add')),
            const ConnectWays(compact: true),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmRemove(
      BuildContext context, AppState state, String url) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(L.t('subs_remove_q')),
        content: Text(L.t('subs_remove_body', {'h': _host(url)})),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(L.t('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: P.danger),
            onPressed: () => Navigator.pop(context, true),
            child: Text(L.t('delete')),
          ),
        ],
      ),
    );
    if (ok == true) await state.removeForeignSub(url);
  }
}
