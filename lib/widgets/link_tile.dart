/// Строка-ссылка наружу: бот, канал, страница документа.
///
/// Жила внутри экрана соглашения. Сам экран убран — весь юридический текст
/// теперь только в боте, — а плитка нужна и в поддержке, поэтому переехала
/// сюда.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_palette.dart';
import 'tap_scale.dart';

class LinkTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String url;
  const LinkTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    return TapScale(
      onTap: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: P.surfaceLo,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: P.surfaceHi),
        ),
        child: Row(children: [
          Icon(icon, size: 19, color: P.limeText),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: P.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style: const TextStyle(color: P.limeText, fontSize: 12.5)),
              ],
            ),
          ),
          const Icon(Icons.open_in_new, size: 16, color: P.textFaint),
        ]),
      ),
    );
  }
}
