//  PacketTunnelProvider.swift
//  Расширение NetworkExtension — здесь реально живёт VPN на iOS.
//
//  Поток данных:
//    Система → utun (packetFlow) → tun2socks → SOCKS 127.0.0.1:10808 → Xray-ядро
//    (libXray, тот же Xray JSON, что строит приложение) → интернет.
//
//  Конфиг Xray приходит из приложения через App Group (UserDefaults ключ
//  "xray_config"). Счётчики трафика пишем обратно в App Group — приложение их
//  опрашивает и показывает в UI.
//
//  ВАЖНО (сборка на Mac): нужны две бинарные зависимости в этом таргете —
//    1) libXray.xcframework  (github.com/XTLS/libXray, gomobile) — запуск Xray;
//    2) tun2socks (hev-socks5-tunnel.xcframework ИЛИ Xray tun) — utun→socks.
//  Пока их нет, XrayCore/Tun2Socks компилируются как заглушки (см. XrayCore.swift),
//  и туннель поднимется, но трафик не пойдёт — это ожидаемо до добавления
//  xcframework. Инструкция — ios/README_iOS.md.

import NetworkExtension
import os.log

class PacketTunnelProvider: NEPacketTunnelProvider {

    private let log = OSLog(subsystem: "site.ugconnect.variousvpn", category: "tunnel")
    private let socksPort = 10808

    override func startTunnel(options: [String: NSObject]?,
                              completionHandler: @escaping (Error?) -> Void) {
        os_log("startTunnel", log: log, type: .info)

        guard let config = sharedDefaults()?.string(forKey: "xray_config"),
              !config.isEmpty else {
            completionHandler(NSError(domain: "VariousVPN", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Нет Xray-конфига в App Group"]))
            return
        }

        let settings = makeNetworkSettings()
        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self = self else { return }
            if let error = error { completionHandler(error); return }

            // 1) Поднимаем Xray-ядро на локальном SOCKS.
            do {
                try XrayCore.shared.start(configJSON: config, socksPort: self.socksPort)
            } catch {
                os_log("Xray start failed: %{public}@", log: self.log, type: .error, "\(error)")
                completionHandler(error)
                return
            }

            // 2) Запускаем tun2socks: utun ↔ SOCKS.
            Tun2Socks.shared.start(
                packetFlow: self.packetFlow,
                socksHost: "127.0.0.1",
                socksPort: self.socksPort,
                onBytes: { up, down, upSpeed, downSpeed in
                    self.writeTraffic(up: up, down: down, upSpeed: upSpeed, downSpeed: downSpeed)
                }
            )

            os_log("tunnel up", log: self.log, type: .info)
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        os_log("stopTunnel: %d", log: log, type: .info, reason.rawValue)
        Tun2Socks.shared.stop()
        XrayCore.shared.stop()
        completionHandler()
    }

    // MARK: - Сетевые настройки utun

    private func makeNetworkSettings() -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "198.18.0.1")

        let ipv4 = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]   // весь трафик — в туннель
        settings.ipv4Settings = ipv4

        let dns = NEDNSSettings(servers: ["1.1.1.1", "8.8.8.8"])
        dns.matchDomains = [""]                          // резолвим всё через туннель
        settings.dnsSettings = dns

        settings.mtu = 1500
        return settings
    }

    // MARK: - App Group

    private func sharedDefaults() -> UserDefaults? {
        let group = (protocolConfiguration as? NETunnelProviderProtocol)?
            .providerConfiguration?["group"] as? String ?? "group.site.ugconnect.variousvpn"
        return UserDefaults(suiteName: group)
    }

    private func writeTraffic(up: Int, down: Int, upSpeed: Int, downSpeed: Int) {
        guard let d = sharedDefaults() else { return }
        d.set(up, forKey: "up_bytes")
        d.set(down, forKey: "down_bytes")
        d.set(upSpeed, forKey: "up_speed")
        d.set(downSpeed, forKey: "down_speed")
    }
}
