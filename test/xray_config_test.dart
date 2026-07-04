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
