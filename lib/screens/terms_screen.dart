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
    '1. Общие положения',
    'Настоящее Пользовательское соглашение (публичная оферта) регулирует использование сервиса Various VPN («Сервис»). Устанавливая приложение, активируя пробный доступ или оформляя подписку, вы подтверждаете, что прочитали и приняли эти условия. Если вы не согласны — не используйте Сервис.'
  ),
  (
    '2. Что такое Сервис',
    'Various VPN — сервис шифрования интернет-трафика и защищённого доступа к сайтам и приложениям. Соединение шифруется по современным протоколам (VLESS + Reality, TLS 1.3), а умный роутинг подбирает быстрый рабочий сервер. Сервис предназначен для законной защиты приватности и обхода технических ограничений сети.'
  ),
  (
    '3. Приватность и отсутствие логов',
    'Мы придерживаемся политики «нет логов»: НЕ храним историю посещённых сайтов, содержимое трафика, DNS-запросы и списки приложений. Для работы подписки хранится необходимый минимум: ваш числовой идентификатор, срок действия подписки, число устройств и технические события оплаты. Мы не продаём и не передаём эти данные третьим лицам, кроме случаев, прямо предусмотренных законом.'
  ),
  (
    '4. Пробный доступ',
    'Бесплатный режим («только Telegram») и пробные дни предоставляются для ознакомления и могут быть изменены или прекращены в любой момент. Пробный доступ — одноразовое предложение на аккаунт.'
  ),
  (
    '5. Подписка, устройства и оплата',
    'Полный доступ предоставляется по платной подписке. Одна подписка рассчитана на ограниченное число устройств (по умолчанию — 3) и является личной: не передавайте ссылку и ID подписки третьим лицам. Оплата производится через бота выбранным способом. Цена и сроки указываются в момент покупки.'
  ),
  (
    '6. Возврат средств',
    'У нас лояльная политика возврата. Если качество Сервиса вас не устроило или он не работает по нашей технической вине и проблему не удалось решить, вы вправе запросить возврат за неиспользованный период. Заявки обрабатываются в течение 10 рабочих дней. Возврат не предоставляется при нарушении правил использования или при блокировках со стороны сторонних сетей, на которые мы не влияем.'
  ),
  (
    '7. Правила использования',
    'Запрещено использовать Сервис для незаконных действий: рассылки спама, DDoS-атак, фишинга, распространения вредоносного ПО, мошенничества, запрещённого контента и любых действий, нарушающих закон вашей юрисдикции. Автоматическая система анализа трафика может приостановить доступ при подозрительной активности без предупреждения; такое решение можно обжаловать в поддержке. Вы несёте полную ответственность за свои действия.'
  ),
  (
    '7a. Реферальная программа',
    'За приглашение новых пользователей могут начисляться бонусы. Оператор вправе в одностороннем порядке изменить или прекратить программу, а также аннулировать бонусы при злоупотреблениях или мошенничестве.'
  ),
  (
    '8. Возраст',
    'Сервис предназначен для пользователей, достигших возраста, с которого по закону их страны допускается самостоятельное заключение подобных соглашений.'
  ),
  (
    '9. Доступность и ответственность',
    'Мы стремимся к бесперебойной работе, но не гарантируем 100% доступность: возможны профилактика, сбои у провайдеров и блокировки со стороны сетей. Сервис предоставляется «как есть»; наша ответственность ограничена стоимостью оплаченного и неиспользованного периода подписки.'
  ),
  (
    '10. Изменения условий',
    'Мы можем обновлять эти условия и цены. Актуальная версия всегда доступна в приложении. Продолжая пользоваться Сервисом после изменений, вы принимаете новую версию.'
  ),
  (
    '11. Контакты и поддержка',
    'Все вопросы, возвраты и техническая поддержка — в Telegram-боте @variousvpnbot. Мы отвечаем быстро и помогаем с подключением.'
  ),
];

const List<(String, String)> _en = [
  (
    '1. General',
    'This User Agreement (public offer) governs the use of the Various VPN service (the “Service”). By installing the app, activating trial access or purchasing a subscription, you confirm that you have read and accepted these terms. If you disagree, do not use the Service.'
  ),
  (
    '2. What the Service is',
    'Various VPN encrypts your internet traffic and provides secure access to sites and apps. Connections use modern protocols (VLESS + Reality, TLS 1.3), and smart routing picks a fast working server. The Service is intended for lawful privacy protection and bypassing technical network restrictions.'
  ),
  (
    '3. Privacy & no-logs',
    'We follow a no-logs policy: we do NOT store your browsing history, traffic contents, DNS queries or app lists. To run your subscription we keep only the minimum needed: your numeric identifier, subscription expiry, device count and technical payment events. We do not sell or share this data except as required by law.'
  ),
  (
    '4. Trial access',
    'The free mode (“Telegram only”) and trial days are provided for evaluation and may be changed or discontinued at any time. Trial access is a one-time offer per account.'
  ),
  (
    '5. Subscription, devices & payment',
    'Full access requires a paid subscription. One subscription covers a limited number of devices (3 by default) and is personal: do not share your link or ID. Payment is made via the bot. Price and terms are shown at purchase.'
  ),
  (
    '6. Refunds',
    'We offer a fair refund policy. If you are not satisfied with the quality, or the Service fails due to our technical fault and cannot be fixed, you may request a refund for the unused period. Requests are processed within 10 business days. No refund applies if you break the usage rules or when blocking is caused by third-party networks beyond our control.'
  ),
  (
    '7. Acceptable use',
    'You must not use the Service for illegal activity: spam, DDoS attacks, phishing, malware, fraud, prohibited content, or anything breaking the law of your jurisdiction. An automated traffic-anomaly system may suspend access without notice for suspicious activity; such decisions can be appealed via support. You are fully responsible for your actions.'
  ),
  (
    '7a. Referral program',
    'Bonuses may be granted for inviting new users. The operator may unilaterally change or end the program and may cancel bonuses for abuse or fraud.'
  ),
  (
    '8. Age',
    'The Service is intended for users who have reached the age at which their country’s law allows them to enter into such agreements.'
  ),
  (
    '9. Availability & liability',
    'We aim for uninterrupted service but do not guarantee 100% uptime (maintenance, upstream outages, network blocking). The Service is provided “as is”; our liability is limited to the cost of the paid, unused subscription period.'
  ),
  (
    '10. Changes',
    'We may update these terms and prices. The current version is always available in the app. Continuing to use the Service after changes means you accept the new version.'
  ),
  (
    '11. Contact & support',
    'All questions, refunds and technical support — in our Telegram bot @variousvpnbot. We reply fast and help you get connected.'
  ),
];
