/// Профиль и подписка: статус, привязанный Telegram-ID, продление, рефералка,
/// ссылка на канал. Детали подписки живут в боте — отсюда быстрый переход.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../brand.dart';
import '../l10n.dart';
import '../services/backend_api.dart';
import '../services/storage.dart';
import '../state/app_state.dart';
import '../theme/app_palette.dart';
import '../widgets/brand_logo.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  ({bool active, DateTime? until})? _status;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final tgId = Storage.instance.tgId;
    if (tgId != null && tgId.isNotEmpty) {
      _loading = true;
      BackendApi().subStatus(tgId).then((s) {
        if (mounted) {
          setState(() {
            _status = s;
            _loading = false;
          });
        }
      });
    }
  }

  Future<void> _open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  Future<void> _linkTelegram() async {
    final ctrl = TextEditingController();
    final id = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: P.surface,
        title: Text(L.t('link_tg')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(L.t('link_tg_hint'),
                style: const TextStyle(color: P.textFaint, fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: P.text),
              decoration: const InputDecoration(
                hintText: '123456789',
                hintStyle: TextStyle(color: P.textFaint),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(L.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: Text(L.t('save')),
          ),
        ],
      ),
    );
    if (id != null && id.isNotEmpty && mounted) {
      final state = context.read<AppState>();
      state.setTgId(id);
      await state.refreshSubStatus();
      final s = await BackendApi().subStatus(id);
      if (mounted) setState(() => _status = s);
    }
  }

  static String _fmtDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tgId = Storage.instance.tgId;
    // Подписка активна, если так сказал бэкенд, либо есть импортированные конфиги.
    final hasSub = _status?.active ?? state.hasServers;
    final until = _status?.until;
    return Scaffold(
      backgroundColor: P.bg,
      appBar: AppBar(title: Text(L.t('profile'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        children: [
          const Center(child: BrandLogo(size: 76)),
          const SizedBox(height: 14),
          Center(
            child: Text(
              tgId != null ? 'Telegram ID: $tgId' : L.t('account_not_linked'),
              style: const TextStyle(color: P.text, fontSize: 15),
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: P.limeText)),
              ),
            ),
          const SizedBox(height: 18),

          // статус подписки
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: hasSub ? P.grad : null,
              color: hasSub ? null : P.surfaceLo,
              borderRadius: BorderRadius.circular(16),
              border: hasSub ? null : Border.all(color: P.surfaceHi),
            ),
            child: Row(
              children: [
                Icon(hasSub ? Icons.verified : Icons.lock_outline,
                    color: hasSub ? const Color(0xFF0C1206) : P.textFaint),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(hasSub ? L.t('sub_active') : L.t('sub_inactive'),
                          style: TextStyle(
                              color: hasSub ? const Color(0xFF0C1206) : P.text,
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                      Text(
                          hasSub
                              ? (until != null
                                  ? '${L.t('valid_until')} ${_fmtDate(until)}'
                                  : L.t('full_access'))
                              : L.t('subscribe_hint'),
                          style: TextStyle(
                              color: hasSub
                                  ? const Color(0xCC0C1206)
                                  : P.textFaint,
                              fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          if (tgId == null)
            _Tile(
              icon: Icons.link,
              title: L.t('link_tg'),
              subtitle: L.t('link_tg_d'),
              onTap: _linkTelegram,
            ),
          _Tile(
            icon: Icons.workspace_premium,
            title: hasSub ? L.t('renew') : L.t('subscribe'),
            onTap: () => _open(Brand.bot),
          ),
          _Tile(
            icon: Icons.card_giftcard,
            title: L.t('invite'),
            subtitle: L.t('invite_d'),
            onTap: () => _open(Brand.bot),
          ),
          _Tile(
            icon: Icons.campaign,
            title: L.t('channel'),
            subtitle: L.t('channel_d'),
            onTap: () => _open(Brand.channel),
          ),
          if (tgId != null)
            _Tile(
              icon: Icons.copy,
              title: L.t('copy_id'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: tgId));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('ID скопирован'),
                  backgroundColor: P.surface,
                ));
              },
            ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  const _Tile(
      {required this.icon,
      required this.title,
      this.subtitle,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: P.surfaceLo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: P.surfaceHi),
      ),
      child: ListTile(
        leading: Icon(icon, color: P.limeText),
        title: Text(title, style: const TextStyle(color: P.text, fontSize: 14)),
        subtitle: subtitle != null
            ? Text(subtitle!,
                style: const TextStyle(color: P.textFaint, fontSize: 12))
            : null,
        trailing: const Icon(Icons.chevron_right, color: P.textFaint),
        onTap: onTap,
      ),
    );
  }
}
