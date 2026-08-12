/// Настройки. Двухуровневая структура вместо одной длинной простыни.
///
/// Было: ~25 строк подряд в шести слабо различимых секциях — чтобы найти
/// «пинг» или «раздельный туннель», приходилось перечитывать весь список.
/// Стало: на верхнем уровне видно, ЧТО вообще можно настроить, а детали живут
/// в разделах «Подключение» и «Туннель». Такой же принцип у сильных клиентов:
/// короткий верх, глубина внутри.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../state/app_state.dart';
import '../theme/app_palette.dart';
import '../widgets/settings_kit.dart';
import 'admin_screen.dart';
import 'app_icon_screen.dart';
import 'connect_guide_screen.dart';
import 'connection_settings_screen.dart';
// import 'logs_screen.dart'; // см. скрытый пункт «Логи» ниже
import 'onboarding_screen.dart';
import 'profile_screen.dart';
import 'speedtest_screen.dart';
import 'stats_screen.dart';
import 'subscriptions_screen.dart';
import 'support_screen.dart';
import 'tunnel_settings_screen.dart';
import 'ios_preview_screen.dart';

class SettingsScreen extends StatelessWidget {
  /// true — экран показан как вкладка в общей оболочке (без стрелки «назад»).
  final bool inShell;
  const SettingsScreen({super.key, this.inShell = false});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    void go(Widget screen) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

    return Scaffold(
      backgroundColor: P.bg,
      appBar: AppBar(
          automaticallyImplyLeading: !inShell, title: Text(L.t('settings'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          // ---------- аккаунт ----------
          SettingsHeader(L.t('sec_account')),
          SettingsGroup(children: [
            SettingsRow(
              icon: Icons.account_circle,
              title: L.t('profile_sub'),
              subtitle: L.t('profile_sub_d'),
              onTap: () => go(const ProfileScreen()),
            ),
            SettingsRow(
              icon: Icons.workspace_premium,
              tint: P.gold,
              title: L.t('subs_title'),
              subtitle: state.subActive
                  ? L.t('sub_active')
                  : (state.hasForeignServers
                      ? L.t('subs_own_active')
                      : L.t('subs_none')),
              onTap: () => go(const SubscriptionsScreen()),
            ),
          ]),

          // ---------- настройки VPN ----------
          SettingsHeader(L.t('sec_vpn')),
          SettingsGroup(children: [
            SettingsRow(
              icon: Icons.wifi_tethering_rounded,
              title: L.t('sec_connection'),
              subtitle: L.t('sec_connection_d'),
              onTap: () => go(const ConnectionSettingsScreen()),
            ),
            SettingsRow(
              icon: Icons.shield_outlined,
              tint: P.violetSoft,
              title: L.t('sec_tunnel'),
              subtitle: L.t('sec_tunnel_d'),
              onTap: () => go(const TunnelSettingsScreen()),
            ),
          ]),

          // ---------- интерфейс ----------
          SettingsHeader(L.t('sec_interface')),
          SettingsGroup(children: [
            SettingsExpand(
              icon: Icons.language,
              title: L.t('language'),
              subtitle: state.lang == 'en' ? 'English' : 'Русский',
              child: SegmentedButton<String>(
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith((st) =>
                      st.contains(WidgetState.selected) ? P.lime : P.surfaceLo),
                  foregroundColor: WidgetStateProperty.resolveWith((st) =>
                      st.contains(WidgetState.selected) ? P.onLime : P.textDim),
                  side: WidgetStateProperty.all(
                      const BorderSide(color: P.surfaceHi)),
                ),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'ru', label: Text('Русский')),
                  ButtonSegment(value: 'en', label: Text('English')),
                ],
                selected: {state.lang},
                onSelectionChanged: (s) => state.setLang(s.first),
              ),
            ),
            SettingsRow(
              icon: Icons.apps_outlined,
              tint: P.violetSoft,
              title: L.t('app_icon'),
              subtitle: L.t('app_icon_d'),
              onTap: () => go(const AppIconScreen()),
            ),
            SettingsSwitch(
              icon: Icons.battery_saver_outlined,
              tint: P.gold,
              title: L.t('lite_mode'),
              subtitle: L.t('lite_mode_d'),
              value: state.liteMode,
              onChanged: state.setLiteMode,
            ),
            SettingsSwitch(
              icon: Icons.volume_up_outlined,
              title: L.t('sound'),
              subtitle: L.t('sound_d'),
              value: state.soundEnabled,
              onChanged: state.setSoundEnabled,
            ),
            SettingsSwitch(
              icon: Icons.vibration,
              title: L.t('vibration'),
              subtitle: L.t('vibration_d'),
              value: state.vibrationEnabled,
              onChanged: state.setVibrationEnabled,
            ),
            SettingsSwitch(
              icon: Icons.notifications_none_rounded,
              tint: P.violetSoft,
              title: L.t('notif_server'),
              subtitle: L.t('notif_server_d'),
              value: state.notificationsEnabled,
              onChanged: state.setNotificationsEnabled,
            ),
          ]),

          // ---------- инструменты ----------
          SettingsHeader(L.t('sec_tools')),
          SettingsGroup(children: [
            SettingsRow(
              icon: Icons.insights,
              title: L.t('stats'),
              subtitle: L.t('stats_d'),
              onTap: () => go(const StatsScreen()),
            ),
            SettingsRow(
              icon: Icons.speed,
              tint: P.gold,
              title: L.t('speedtest'),
              subtitle: L.t('speedtest_d'),
              onTap: () => go(const SpeedtestScreen()),
            ),
            // «Логи» временно скрыты из этой сборки — она уходит на обзор
            // покупателю, и сырой технический вывод там лишний. Экран и весь
            // его код на месте: чтобы вернуть пункт, достаточно раскомментировать
            // строку ниже и импорт logs_screen.dart.
            // SettingsRow(
            //   icon: Icons.receipt_long,
            //   title: L.t('logs'),
            //   subtitle: L.t('logs_d'),
            //   onTap: () => go(const LogsScreen()),
            // ),
          ]),

          // ---------- помощь ----------
          SettingsHeader(L.t('sec_help')),
          SettingsGroup(children: [
            // Инструкция нужна ровно до первого удачного подключения.
            // Тому, у кого VPN уже работает, она только мешает.
            if (!state.featuresUnlocked)
              SettingsRow(
                icon: Icons.help_outline,
                title: L.t('how_connect'),
                subtitle: L.t('how_connect_d'),
                onTap: () => go(const ConnectGuideScreen()),
              ),
            // Витрина стиля iOS. Оценить отклик элементов можно только
            // пальцем, поэтому они собраны на отдельном экране.
            SettingsRow(
              icon: Icons.phone_iphone,
              tint: P.violetSoft,
              title: L.t('ios_preview'),
              subtitle: L.t('ios_preview_d'),
              onTap: () => go(const IosPreviewScreen()),
            ),
            SettingsRow(
              icon: Icons.support_agent,
              title: L.t('support'),
              subtitle: L.t('support_d'),
              onTap: () => go(const SupportScreen()),
            ),
          ]),

          if (state.isAdmin) ...[
            SettingsHeader(L.t('sec_admin')),
            SettingsGroup(children: [
              SettingsRow(
                icon: Icons.shield,
                tint: P.gold,
                title: L.t('admin_panel'),
                subtitle: L.t('admin_panel_d'),
                onTap: () => go(const AdminScreen()),
              ),
            ]),
          ],

          // ---------- выход ----------
          // Опасное действие отделено от остальных (правило
          // destructive-nav-separation): своя группа, красным, внизу.
          const SizedBox(height: 26),
          SettingsGroup(children: [
            SettingsRow(
              icon: Icons.logout,
              title: L.t('logout'),
              danger: true,
              chevron: false,
              onTap: () => _confirmLogout(context, state),
            ),
          ]),
          const SizedBox(height: 16),
          const Center(
            // Только название и версия. Приписка «Premium» ничего человеку не
            // сообщала — статус подписки и так виден на главной, — а на
            // английском выбивалась из остального русского интерфейса.
            child: Text('Various VPN · v1.0.0',
                style: TextStyle(color: P.textFaint, fontSize: 12)),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, AppState state) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(L.t('logout_q')),
        content: Text(L.t('logout_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(L.t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: P.danger),
            onPressed: () => Navigator.pop(context, true),
            child: Text(L.t('logout')),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await state.logout();
      if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const OnboardingScreen()),
          (_) => false,
        );
      }
    }
  }
}
