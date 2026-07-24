/// Настройки пользователя (как в Happ): подключение, интерфейс, уведомления,
/// дополнительно. Тёмная тема. Реальные переключатели сохраняются в Storage,
/// часть опций — задел под бэкенд (помечены как «скоро»).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../brand.dart';
import '../l10n.dart';
import '../state/app_state.dart';
import '../theme/app_palette.dart';
import 'admin_screen.dart';
import 'connect_guide_screen.dart';
import 'import_screen.dart';
import 'profile_screen.dart';
import 'logs_screen.dart';
import 'onboarding_screen.dart';
import 'network_settings_screen.dart';
import 'per_app_screen.dart';
import 'custom_servers_screen.dart';
import 'auto_wifi_screen.dart';
import 'diagnostics_screen.dart';
import 'terms_screen.dart';
import 'killswitch_guide_screen.dart';
import 'ping_settings_screen.dart';
import 'speedtest_screen.dart';
import 'stats_screen.dart';
import 'support_screen.dart';

class SettingsScreen extends StatelessWidget {
  /// true — экран показан как вкладка в общей оболочке (без стрелки «назад»).
  final bool inShell;
  const SettingsScreen({super.key, this.inShell = false});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    // Бесплатный режим: настройки маршрутизации/подключения недоступны (серые) —
    // работает только Telegram. Оставляем активными базовые (язык, уведомления,
    // тема, вибро). Остальное — с замком, тап открывает предложение купить.
    final free = state.telegramOnly;
    return Scaffold(
      backgroundColor: P.bg,
      appBar: AppBar(
          automaticallyImplyLeading: !inShell, title: Text(L.t('settings'))),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _Section(L.t('sec_account')),
          _NavRow(
            title: L.t('profile_sub'),
            icon: Icons.account_circle,
            subtitle: L.t('profile_sub_d'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
          ),
          // Добавление/обновление подписки прямо в приложении (перенесено из
          // «Дополнительно» — логичнее в разделе аккаунта).
          _NavRow(
            title: L.t('acc_subscription'),
            icon: Icons.link,
            subtitle: L.t('acc_subscription_d'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ImportScreen()),
            ),
          ),
          _NavRow(
            title: L.t('link_tg'),
            icon: Icons.telegram,
            subtitle: L.t('link_tg_d'),
            onTap: () => showLinkTelegramDialog(context),
          ),
          _NavRow(
            title: L.t('channel'),
            icon: Icons.campaign,
            subtitle: L.t('channel_d'),
            onTap: () => launchUrl(Uri.parse(Brand.channel),
                mode: LaunchMode.externalApplication),
          ),

          _Section(L.t('sec_connection')),
          _SwitchRow(
            title: L.t('autoconnect'),
            subtitle: L.t('autoconnect_d'),
            value: state.autoConnect,
            onChanged: state.setAutoConnect,
            locked: free,
          ),
          _SwitchRow(
            title: L.t('ondemand'),
            subtitle: L.t('ondemand_d'),
            value: state.onDemand,
            onChanged: state.setOnDemand,
            locked: free,
          ),
          _SwitchRow(
            title: L.t('bypass_ru'),
            subtitle: L.t('bypass_ru_d'),
            value: state.bypassRu,
            onChanged: state.setBypassRu,
            locked: free,
          ),
          _SwitchRow(
            title: L.t('adblock'),
            subtitle: L.t('adblock_d'),
            value: state.adBlock,
            onChanged: state.setAdBlock,
            locked: free,
          ),
          _SwitchRow(
            title: L.t('smart_ai'),
            subtitle: L.t('smart_ai_d'),
            value: state.smartAi,
            onChanged: state.setSmartAi,
            locked: free,
          ),
          _SwitchRow(
            title: L.t('autorefresh'),
            subtitle: L.t('autorefresh_d'),
            value: state.autoRefreshSub,
            onChanged: state.setAutoRefreshSub,
            locked: free,
          ),
          if (state.autoRefreshSub && !free)
            _NavRow(
              title: L.t('autorefresh_every'),
              icon: Icons.schedule,
              trailing: '${state.autoRefreshHours} '
                  '${L.current == 'en' ? 'h' : 'ч'}',
              onTap: () => _pickRefreshInterval(context, state),
            ),
          _NavRow(
            title: L.t('per_app'),
            trailing: '${state.rules.length}',
            locked: free,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PerAppScreen()),
            ),
          ),
          _NavRow(
            title: L.t('ping_label'),
            icon: Icons.speed_outlined,
            trailing: state.pingType == 'proxy' ? 'via Proxy' : 'TCP',
            locked: free,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PingSettingsScreen()),
            ),
          ),
          _NavRow(
            title: L.t('net_settings'),
            icon: Icons.lan_outlined,
            subtitle: L.t('net_settings_d'),
            trailing: state.ipStrategy.label,
            locked: free,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NetworkSettingsScreen()),
            ),
          ),
          _NavRow(
            title: L.t('awifi_nav'),
            icon: Icons.wifi_lock,
            subtitle: L.t('awifi_nav_d'),
            locked: free,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AutoWifiScreen()),
            ),
          ),
          _NavRow(
            title: L.t('diag_nav'),
            icon: Icons.wifi_find,
            subtitle: L.t('diag_nav_d'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DiagnosticsScreen()),
            ),
          ),
          _NavRow(
            title: L.t('ks_nav'),
            icon: Icons.gpp_maybe_outlined,
            subtitle: L.t('ks_nav_d'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const KillSwitchGuideScreen()),
            ),
          ),
          _NavRow(
            title: L.t('cs_nav'),
            icon: Icons.tune,
            subtitle: L.t('cs_nav_d'),
            locked: free,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CustomServersScreen()),
            ),
          ),

          _Section(L.t('sec_interface')),
          // Язык — настоящий переключатель RU/EN.
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(L.t('language'),
                    style: const TextStyle(color: P.text, fontSize: 14)),
                SegmentedButton<String>(
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith((st) =>
                        st.contains(WidgetState.selected)
                            ? P.lime
                            : P.surfaceLo),
                    foregroundColor: WidgetStateProperty.resolveWith((st) =>
                        st.contains(WidgetState.selected)
                            ? const Color(0xFF0C1206)
                            : P.textDim),
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
              ],
            ),
          ),
          _SwitchRow(
            title: L.t('lite_mode'),
            subtitle: L.t('lite_mode_d'),
            value: state.liteMode,
            onChanged: state.setLiteMode,
          ),
          _SwitchRow(
            title: L.t('sound'),
            subtitle: L.t('sound_d'),
            value: state.soundEnabled,
            onChanged: state.setSoundEnabled,
          ),
          _SwitchRow(
            title: L.t('vibration'),
            subtitle: L.t('vibration_d'),
            value: state.vibrationEnabled,
            onChanged: state.setVibrationEnabled,
          ),

          _Section(L.t('sec_notifications')),
          _SwitchRow(
            title: L.t('notif_server'),
            subtitle: L.t('notif_server_d'),
            value: state.notificationsEnabled,
            onChanged: state.setNotificationsEnabled,
          ),

          _Section(L.t('sec_extra')),
          _NavRow(
            title: L.t('stats'),
            icon: Icons.insights,
            subtitle: L.t('stats_d'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const StatsScreen()),
            ),
          ),
          _NavRow(
            title: L.t('speedtest'),
            icon: Icons.speed,
            subtitle: L.t('speedtest_d'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SpeedtestScreen()),
            ),
          ),
          _NavRow(
            title: L.t('how_connect'),
            icon: Icons.help_outline,
            subtitle: L.t('how_connect_d'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ConnectGuideScreen()),
            ),
          ),
          _NavRow(
            title: L.t('logs'),
            icon: Icons.receipt_long,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LogsScreen()),
            ),
          ),
          _NavRow(
            title: L.t('support'),
            icon: Icons.support_agent,
            subtitle: L.t('support_d'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SupportScreen()),
            ),
          ),
          _NavRow(
            title: L.t('terms'),
            icon: Icons.description_outlined,
            subtitle: L.t('terms_d'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TermsScreen()),
            ),
          ),

          if (state.isAdmin) ...[
            _Section(L.t('sec_admin')),
            _NavRow(
              title: L.t('admin_panel'),
              icon: Icons.shield,
              subtitle: L.t('admin_panel_d'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AdminScreen()),
              ),
            ),
          ],

          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.logout, color: Color(0xFFE2504A)),
            title: Text(L.t('logout'),
                style: const TextStyle(color: Color(0xFFE2504A))),
            onTap: () => _confirmLogout(context, state),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text('Various VPN · v1.0.0',
                style: TextStyle(color: P.textFaint, fontSize: 12)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, AppState state) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: P.surface,
        title: Text(L.t('logout_q')),
        content: Text(L.t('logout_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(L.t('cancel')),
          ),
          FilledButton(
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

/// Выбор интервала авто-обновления подписки (1/3/6/12/24 ч).
void _pickRefreshInterval(BuildContext context, AppState state) {
  const options = [1, 3, 6, 12, 24];
  final en = L.current == 'en';
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: P.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(L.t('autorefresh_every'),
                style: const TextStyle(
                    color: P.text, fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          for (final h in options)
            ListTile(
              title: Text('$h ${en ? 'h' : 'ч'}',
                  style: const TextStyle(color: P.text)),
              trailing: state.autoRefreshHours == h
                  ? const Icon(Icons.check, color: P.lime)
                  : null,
              onTap: () {
                state.setAutoRefreshHours(h);
                Navigator.pop(context);
              },
            ),
        ],
      ),
    ),
  );
}

class _Section extends StatelessWidget {
  final String text;
  const _Section(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 6),
      child: Text(text.toUpperCase(),
          style: const TextStyle(
              color: P.limeText,
              fontSize: 11,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w600)),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool locked; // бесплатный режим: настройка недоступна
  const _SwitchRow({
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    final tile = SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 2),
      title: Text(title, style: const TextStyle(color: P.text, fontSize: 14)),
      subtitle: subtitle != null
          ? Text(subtitle!,
              style: const TextStyle(color: P.textFaint, fontSize: 12))
          : null,
      value: locked ? false : value,
      activeThumbColor: P.lime,
      onChanged: locked ? null : onChanged,
    );
    if (!locked) return tile;
    return Opacity(
      opacity: 0.4,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showFreeLockedDialog(context),
        child: AbsorbPointer(child: tile),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? trailing;
  final IconData? icon;
  final VoidCallback onTap;
  final bool locked;
  const _NavRow({
    required this.title,
    this.subtitle,
    this.trailing,
    this.icon,
    required this.onTap,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    final tile = ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 2),
      leading: icon != null ? Icon(icon, color: P.limeText) : null,
      title: Text(title, style: const TextStyle(color: P.text, fontSize: 14)),
      subtitle: subtitle != null
          ? Text(subtitle!,
              style: const TextStyle(color: P.textFaint, fontSize: 12))
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (locked)
            const Icon(Icons.lock_outline, color: P.textFaint, size: 16)
          else ...[
            if (trailing != null)
              Text(trailing!,
                  style: const TextStyle(color: P.textFaint, fontSize: 12)),
            const Icon(Icons.chevron_right, color: P.textFaint),
          ],
        ],
      ),
      onTap: locked ? () => showFreeLockedDialog(context) : onTap,
    );
    if (!locked) return tile;
    return Opacity(opacity: 0.4, child: tile);
  }
}
