/// Реализация-фабрика для web (и любой платформы без dart:io): заглушка.
library;

import 'vpn_service.dart';

VpnService createVpnService() => StubVpnService();
