import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:various_vpn/services/xray_link.dart';
import 'package:various_vpn/services/xray_config.dart';

void main() {
  test('VLESS+Reality gRPC → корректный Xray outbound', () {
    const link =
        'vless://11111111-2222-3333-4444-555555555555@example.com:443'
        '?type=grpc&security=reality&pbk=PUBKEY&sid=ab12&sni=www.microsoft.com'
        '&fp=chrome&flow=xtls-rprx-vision&serviceName=grpcsvc#DE-1';
    final cfg = buildXrayConfig(link);

    final out = (cfg['outbounds'] as List).first as Map<String, dynamic>;
    expect(out['protocol'], 'vless');
    expect(out['tag'], 'proxy');
    final vnext = (out['settings']['vnext'] as List).first as Map;
    expect(vnext['address'], 'example.com');
    expect(vnext['port'], 443);
    final user = (vnext['users'] as List).first as Map;
    expect(user['id'], '11111111-2222-3333-4444-555555555555');
    expect(user['flow'], 'xtls-rprx-vision');
    final ss = out['streamSettings'] as Map;
    expect(ss['network'], 'grpc');
    expect(ss['security'], 'reality');
    expect((ss['realitySettings'] as Map)['publicKey'], 'PUBKEY');
    expect((ss['grpcSettings'] as Map)['serviceName'], 'grpcsvc');

    // inbounds socks на нужном порту
    final inb = (cfg['inbounds'] as List).first as Map;
    expect(inb['protocol'], 'socks');
    expect(inb['port'], kXraySocksPort);
  });

  test('applyNetOptions поверх iOS-конфига: free-Telegram роутинг', () {
    const link = 'vless://uuid@1.2.3.4:443?type=tcp&security=reality&pbk=X#RU';
    final base = buildXrayConfigJson(link);
    final routed =
        applyNetOptions(base, const NetOptions(telegramOnly: true));
    final cfg = jsonDecode(routed) as Map<String, dynamic>;
    final rules = (cfg['routing']['rules'] as List).cast<Map>();
    // должно быть правило blackhole для всего прочего трафика
    expect(rules.any((r) => r['outboundTag'] == 'blocked'), isTrue);
    // и правило proxy для Telegram-доменов
    expect(rules.any((r) => r['outboundTag'] != 'blocked'), isTrue);
  });

  test('Trojan ws → корректный outbound', () {
    const link =
        'trojan://pass@host.net:443?type=ws&security=tls&sni=host.net&path=%2Fws#NL';
    final cfg = buildXrayConfig(link);
    final out = (cfg['outbounds'] as List).first as Map<String, dynamic>;
    expect(out['protocol'], 'trojan');
    expect((out['settings']['servers'] as List).first['password'], 'pass');
    expect((out['streamSettings'] as Map)['network'], 'ws');
    expect(((out['streamSettings'] as Map)['wsSettings'] as Map)['path'], '/ws');
  });
}
