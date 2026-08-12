/// Настройки → Резервная копия. Сохранить все настройки в файл и восстановить
/// их на другом устройстве или после переустановки.
///
/// Что попадает в копию: правила по приложениям, свои серверы, сайты в обход,
/// маршрутизация, интерфейс. Чего в копии НЕТ: токен доступа и привязка
/// подписки — файл может уйти в облако или мессенджер, а это ключ от аккаунта.
library;

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../services/storage.dart';
import '../state/app_state.dart';
import '../theme/app_palette.dart';
import '../widgets/settings_kit.dart';
import '../widgets/app_toast.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  String? _lastPath;
  bool _busy = false;

  void _say(String text) => AppToast.show(context, text);

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final data = Storage.instance.exportSettings();
      final json = const JsonEncoder.withIndent('  ').convert({
        'app': 'various_vpn',
        'version': 1,
        'created': DateTime.now().toIso8601String(),
        'settings': data,
      });
      final dir = await getApplicationDocumentsDirectory();
      final stamp = DateTime.now()
          .toIso8601String()
          .substring(0, 16)
          .replaceAll(RegExp(r'[:T]'), '-');
      final file = File('${dir.path}/various-vpn-$stamp.json');
      await file.writeAsString(json);
      if (!mounted) return;
      setState(() => _lastPath = file.path);
      _say(L.t('bk_saved', {'n': data.length}));
    } catch (e) {
      if (mounted) _say('${L.t('bk_fail')}: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final res = await FilePicker.platform.pickFiles(withData: true);
    if (res == null || res.files.isEmpty) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final f = res.files.first;
      final raw = f.bytes != null
          ? utf8.decode(f.bytes!)
          : await File(f.path!).readAsString();
      final map = jsonDecode(raw);
      if (map is! Map || map['app'] != 'various_vpn') {
        throw const FormatException('не наш файл');
      }
      final settings = (map['settings'] as Map).cast<String, Object?>();
      final n = Storage.instance.importSettings(settings);
      if (!mounted) return;
      // Перечитываем настройки в память, иначе применятся только после
      // перезапуска и человек решит, что восстановление не сработало.
      await context.read<AppState>().reloadSettings();
      if (!mounted) return;
      _say(L.t('bk_restored', {'n': n}));
    } catch (e) {
      if (mounted) _say('${L.t('bk_bad_file')}: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(L.t('bk_reset_q')),
        content: Text(L.t('bk_reset_body')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(L.t('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: P.danger),
            onPressed: () => Navigator.pop(context, true),
            child: Text(L.t('bk_reset')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await Storage.instance.resetSettings();
    if (!mounted) return;
    await context.read<AppState>().reloadSettings();
    if (!mounted) return;
    _say(L.t('bk_reset_done'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: P.bg,
      appBar: AppBar(title: Text(L.t('backup'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Text(L.t('bk_intro'),
              style: const TextStyle(
                  color: P.textDim, fontSize: 13.5, height: 1.5)),
          SettingsHeader(L.t('bk_grp_copy')),
          SettingsGroup(children: [
            SettingsRow(
              icon: Icons.save_alt_rounded,
              title: L.t('bk_export'),
              subtitle: L.t('bk_export_d'),
              chevron: false,
              onTap: _busy ? () {} : _export,
            ),
            SettingsRow(
              icon: Icons.restore_rounded,
              tint: P.violetSoft,
              title: L.t('bk_import'),
              subtitle: L.t('bk_import_d'),
              chevron: false,
              onTap: _busy ? () {} : _import,
            ),
          ]),
          if (_lastPath != null) ...[
            const SizedBox(height: 12),
            _SavedPath(path: _lastPath!),
          ],
          SettingsHeader(L.t('bk_grp_reset')),
          SettingsGroup(children: [
            SettingsRow(
              icon: Icons.restart_alt_rounded,
              title: L.t('bk_reset'),
              subtitle: L.t('bk_reset_d'),
              danger: true,
              chevron: false,
              onTap: _reset,
            ),
          ]),
        ],
      ),
    );
  }
}

/// Куда лёг файл: путь длинный, поэтому даём скопировать одним тапом.
class _SavedPath extends StatelessWidget {
  final String path;
  const _SavedPath({required this.path});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: P.lime.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: P.lime.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        const Icon(Icons.folder_open, size: 17, color: P.limeText),
        const SizedBox(width: 10),
        Expanded(
          child: Text(path,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: P.textDim, fontSize: 11.5)),
        ),
        IconButton(
          tooltip: L.t('paste'),
          icon: const Icon(Icons.copy_rounded, size: 17, color: P.limeText),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: path));
            AppToast.ok(context, L.t('bk_copied'));
          },
        ),
      ]),
    );
  }
}
