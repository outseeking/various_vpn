/// Тесты генерации Xray-конфига: реально проверяем, что тумблеры «обход РФ»,
/// «умный ИИ» и «AdBlock» дописывают правильные правила маршрутизации.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:various_vpn/services/xray_config.dart';

/// Минимальный базовый конфиг, как отдаёт flutter_v2ray из vless://-ссылки:
/// один proxy-outbound (tag 'proxy') — на нём и проверяем маршрутизацию.
String _base() => jsonEncode({
      'outbounds': [
        {'protocol': 'vless', 'tag': 'proxy', 'streamSettings': {}},
      ],
      'routing': {'rules': []},
    });

Map<String, dynamic> _apply(NetOptions o) =>
    jsonDecode(applyNetOptions(_base(), o)) as Map<String, dynamic>;

List _rules(Map<String, dynamic> cfg) =>
    ((cfg['routing'] as Map)['rules'] as List);

bool _hasRuleTo(Map<String, dynamic> cfg, String tag,
    {String? domainContains}) {
  for (final r in _rules(cfg)) {
    if ((r as Map)['outboundTag'] != tag) continue;
    if (domainContains == null) return true;
    final doms = (r['domain'] as List?)?.map((e) => e.toString()) ?? const [];
    if (doms.any((d) => d.contains(domainContains))) return true;
  }
  return false;
}

void main() {
  _muxSafetyTests();
  test('обход РФ: .ru и geoip:ru идут в direct (тумблер работает)', () {
    final cfg = _apply(const NetOptions(bypassRu: true, smartAi: false));
    // должен появиться direct-outbound
    final tags = (cfg['outbounds'] as List).map((o) => (o as Map)['tag']);
    expect(tags, contains('direct'));
    // правило: .ru-домены → direct
    expect(_hasRuleTo(cfg, 'direct', domainContains: '.ru'), isTrue);
    // правило: российские IP (geoip:ru) → direct
    final ruIp = _rules(cfg).any((r) =>
        (r as Map)['outboundTag'] == 'direct' &&
        (r['ip'] as List?)?.contains('geoip:ru') == true);
    expect(ruIp, isTrue);
  });

  test('обход РФ выключен: правил для .ru нет', () {
    final cfg = _apply(const NetOptions(bypassRu: false, smartAi: false));
    expect(_hasRuleTo(cfg, 'direct', domainContains: '.ru'), isFalse);
  });

  test('умный ИИ: домены нейросетей идут через proxy', () {
    final cfg = _apply(const NetOptions(smartAi: true));
    expect(_hasRuleTo(cfg, 'proxy', domainContains: 'openai.com'), isTrue);
  });

  test('AdBlock: реклама уходит в blackhole (blocked)', () {
    final cfg = _apply(const NetOptions(adBlock: true, smartAi: false));
    final tags = (cfg['outbounds'] as List)
        .map((o) => (o as Map)['tag'] as String)
        .toList();
    // должен появиться blackhole-outbound
    final hasBlackhole = (cfg['outbounds'] as List).any((o) =>
        (o as Map)['protocol'] == 'blackhole' && o['tag'] == 'blocked');
    expect(hasBlackhole, isTrue, reason: 'tags=$tags');
    expect(_hasRuleTo(cfg, 'blocked', domainContains: 'doubleclick.net'), isTrue);
  });

  test('AdBlock выключен: blackhole не добавляется', () {
    final cfg = _apply(const NetOptions(adBlock: false, smartAi: false));
    final hasBlackhole = (cfg['outbounds'] as List)
        .any((o) => (o as Map)['tag'] == 'blocked');
    expect(hasBlackhole, isFalse);
  });

  test('динамические списки из панели переопределяют встроенные', () {
    final cfg = _apply(const NetOptions(
      smartAi: true,
      bypassRu: true,
      adBlock: true,
      aiDomains: ['my-ai.example'],
      ruDomains: ['my-bank.ru'],
      adDomains: ['my-ads.example'],
    ));
    // голые домены нормализуются в domain:X
    expect(_hasRuleTo(cfg, 'proxy', domainContains: 'domain:my-ai.example'), isTrue);
    expect(_hasRuleTo(cfg, 'direct', domainContains: 'domain:my-bank.ru'), isTrue);
    expect(_hasRuleTo(cfg, 'blocked', domainContains: 'domain:my-ads.example'), isTrue);
  });
}

/// Мультиплексирование и поток XTLS Vision несовместимы: ядро молча
/// обрывает соединения. Проверено на живом сервере — тот же конфиг без mux
/// отдаёт 204, с mux не отдаёт ничего. Этот тест не даёт ошибке вернуться.
void _muxSafetyTests() {
  String cfgWith({required String flow}) => jsonEncode({
        'outbounds': [
          {
            'tag': 'proxy',
            'protocol': 'vless',
            'settings': {
              'vnext': [
                {
                  'address': '203.0.113.10',
                  'port': 443,
                  'users': [
                    {'id': 'u', 'encryption': 'none', 'flow': flow}
                  ],
                }
              ]
            },
            'streamSettings': {'network': 'tcp', 'security': 'reality'},
          },
        ],
      });

  bool muxEnabled(String out) {
    final o = (jsonDecode(out)['outbounds'] as List).first as Map;
    return (o['mux'] as Map?)?['enabled'] == true;
  }

  test('mux НЕ включается на сервере с flow=xtls-rprx-vision', () {
    final out = applyNetOptions(
        cfgWith(flow: 'xtls-rprx-vision'), const NetOptions(mux: true));
    expect(muxEnabled(out), isFalse,
        reason: 'это убивает туннель: connection closed, скачано ноль');
  });

  test('mux включается там, где потока XTLS нет', () {
    final out = applyNetOptions(cfgWith(flow: ''), const NetOptions(mux: true));
    expect(muxEnabled(out), isTrue);
  });

  test('без настройки mux не появляется вовсе', () {
    final out =
        applyNetOptions(cfgWith(flow: ''), const NetOptions(mux: false));
    expect(muxEnabled(out), isFalse);
  });
}
