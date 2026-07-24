/// Пользовательское соглашение + политика конфиденциальности Various VPN.
/// Используется двумя способами:
///  • как экран-читалка из Настроек (TermsScreen);
///  • как ГЕЙТ согласия на первом запуске (ConsentGate) — без принятия дальше
///    в приложение не пускаем (кнопка «Принимаю»).
library;

import 'package:flutter/material.dart';

import '../l10n.dart';
import '../services/storage.dart';
import '../theme/app_palette.dart';
import '../widgets/tap_scale.dart';

const _kTermsAccepted = 'terms_accepted';

/// Оборачивает [child]: пока соглашение не принято — показываем гейт.
class ConsentGate extends StatefulWidget {
  final Widget child;
  const ConsentGate({super.key, required this.child});

  @override
  State<ConsentGate> createState() => _ConsentGateState();
}

class _ConsentGateState extends State<ConsentGate> {
  late bool _accepted =
      Storage.instance.getBool(_kTermsAccepted, def: false);

  @override
  Widget build(BuildContext context) {
    if (_accepted) return widget.child;
    return TermsScreen(
      onAccept: () {
        Storage.instance.setBool(_kTermsAccepted, true);
        setState(() => _accepted = true);
      },
    );
  }
}

class TermsScreen extends StatelessWidget {
  /// Если задан — показываем режим согласия (кнопки «Принимаю» внизу).
  final VoidCallback? onAccept;
  const TermsScreen({super.key, this.onAccept});

  bool get _gate => onAccept != null;

  @override
  Widget build(BuildContext context) {
    final ru = L.current != 'en';
    final sections = ru ? _ru : _en;
    return Scaffold(
      backgroundColor: P.bg,
      appBar: _gate
          ? null
          : AppBar(title: Text(ru ? 'Пользовательское соглашение' : 'Terms of Service')),
      body: SafeArea(
        child: Column(
          children: [
            if (_gate) ...[
              const SizedBox(height: 18),
              const Icon(Icons.verified_user_outlined,
                  color: P.limeText, size: 40),
              const SizedBox(height: 10),
              Text(ru ? 'Добро пожаловать в Various VPN' : 'Welcome to Various VPN',
                  style: const TextStyle(
                      color: P.text, fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                  ru
                      ? 'Пара слов о правилах — и вперёд'
                      : 'A few rules — then you’re in',
                  style: const TextStyle(color: P.textFaint, fontSize: 13)),
              const SizedBox(height: 12),
            ],
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                children: [
                  for (final s in sections) _Block(title: s.$1, body: s.$2),
                  const SizedBox(height: 8),
                  Text(
                    ru
                        ? 'Дата вступления в силу: 24 июля 2026 г.'
                        : 'Effective date: 24 July 2026',
                    style: const TextStyle(color: P.textFaint, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (_gate)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
                  child: Column(
                    children: [
                      Text(
                        ru
                            ? 'Нажимая «Принимаю», вы соглашаетесь с условиями и политикой конфиденциальности.'
                            : 'By tapping “I agree” you accept the Terms and Privacy Policy.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: P.textFaint, fontSize: 11.5),
                      ),
                      const SizedBox(height: 10),
                      TapScale(
                        onTap: onAccept,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          decoration: BoxDecoration(
                            gradient: P.grad,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            ru ? 'Принимаю' : 'I agree',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Color(0xFF0C1206),
                                fontSize: 16,
                                fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Block extends StatelessWidget {
  final String title;
  final String body;
  const _Block({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: P.text, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text(body,
              style: const TextStyle(
                  color: P.textDim, fontSize: 13.5, height: 1.5)),
        ],
      ),
    );
  }
}

const List<(String, String)> _ru = [
  (
    '1. О сервисе',
    'Various VPN — сервис для защищённого и приватного доступа в интернет. Мы шифруем ваш трафик и помогаем открывать сайты и приложения, которые могут быть недоступны в вашей сети.'
  ),
  (
    '2. Приватность и логи',
    'Мы НЕ ведём журналы вашей активности: не храним историю посещённых сайтов, содержимое трафика и DNS-запросы. Для работы подписки храним только технические данные: ваш идентификатор, срок подписки и количество устройств.'
  ),
  (
    '3. Правила использования',
    'Сервис нельзя использовать для незаконных действий, рассылки спама, атак на чужие системы, а также любых действий, нарушающих законы вашей страны. При нарушении доступ может быть ограничен без возврата средств.'
  ),
  (
    '4. Устройства и подписка',
    'Одна подписка рассчитана на ограниченное число устройств (по умолчанию — 3). Подписка личная; не передавайте ссылку и ID подписки третьим лицам.'
  ),
  (
    '5. Оплата и возврат',
    'Оплата подписки производится через бота. Пробный период предоставляется бесплатно. Возврат возможен, если сервис не работает по нашей вине и проблему не удалось решить.'
  ),
  (
    '6. Ответственность',
    'Мы стремимся к бесперебойной работе, но не гарантируем 100% доступность (профилактика, сбои у провайдеров и т. п.). Сервис предоставляется «как есть».'
  ),
  (
    '7. Изменения',
    'Условия могут обновляться. Продолжая пользоваться приложением после изменений, вы принимаете новую версию соглашения.'
  ),
  (
    '8. Контакты',
    'Вопросы и поддержка — в нашем Telegram-боте @variousvpnbot.'
  ),
];

const List<(String, String)> _en = [
  (
    '1. About the service',
    'Various VPN provides secure and private internet access. We encrypt your traffic and help you reach sites and apps that may be unavailable on your network.'
  ),
  (
    '2. Privacy & logs',
    'We do NOT keep activity logs: no browsing history, traffic contents or DNS queries. To run your subscription we store only technical data: your identifier, subscription expiry and device count.'
  ),
  (
    '3. Acceptable use',
    'The service must not be used for illegal activity, spam, attacks on other systems, or anything breaking the laws of your country. Violations may lead to access being restricted without a refund.'
  ),
  (
    '4. Devices & subscription',
    'One subscription covers a limited number of devices (3 by default). The subscription is personal — do not share your subscription link or ID with others.'
  ),
  (
    '5. Payment & refunds',
    'Subscriptions are purchased via the bot. A free trial is available. Refunds are possible if the service fails through our fault and the issue cannot be resolved.'
  ),
  (
    '6. Liability',
    'We aim for uninterrupted service but do not guarantee 100% uptime (maintenance, upstream outages, etc.). The service is provided “as is”.'
  ),
  (
    '7. Changes',
    'These terms may be updated. By continuing to use the app after changes, you accept the new version.'
  ),
  (
    '8. Contact',
    'Questions and support — in our Telegram bot @variousvpnbot.'
  ),
];
