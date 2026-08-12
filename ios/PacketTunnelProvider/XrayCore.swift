//  XrayCore.swift
//  Обёртка над двумя половинами VPN на iOS:
//    • XrayCore  — Xray-ядро (LibXray.xcframework, готовый бинарник из релизов);
//    • Tun2Socks — перекачка utun ↔ локальный SOCKS (Tun2SocksKit, тоже готовый).
//
//  Почему половин именно две. Система отдаёт расширению сырые IP-пакеты, а
//  Xray умеет разговаривать только по SOCKS. Между ними нужен переводчик со
//  своим стеком TCP/IP — им и работает hev-socks5-tunnel внутри Tun2SocksKit.
//  Без него ядро запустится, туннель поднимется, а трафик стоять будет.
//
//  Обе зависимости подключаются автоматически: xcframework ядра скачивает
//  сборка, Tun2SocksKit приходит подом (см. ios/Podfile). Ветки `#if
//  canImport` оставлены, чтобы проект собирался и без них — тогда туннель
//  поднимется пустым, и это видно в логах, а не превращается в загадку.

import Foundation
import NetworkExtension
import os.log

#if canImport(Tun2SocksKit)
import Tun2SocksKit
#endif

private let coreLog = OSLog(subsystem: "site.ugconnect.variousvpn", category: "core")

// MARK: - Xray-ядро

final class XrayCore {
    static let shared = XrayCore()
    private init() {}

    /// Запускает Xray с готовым JSON-конфигом (тем же, что строит приложение).
    /// SOCKS-инбаунд внутри конфига слушает 127.0.0.1:socksPort.
    func start(configJSON: String, socksPort: Int) throws {
        #if canImport(LibXray)
        try LibXrayBridge.run(config: configJSON)
        os_log("Xray запущен, версия %{public}@",
               log: coreLog, type: .info, LibXrayBridge.version())
        #else
        os_log("ЗАГЛУШКА: LibXray не подключён — трафика не будет",
               log: coreLog, type: .error)
        #endif
    }

    func stop() {
        #if canImport(LibXray)
        LibXrayBridge.stop()
        #endif
        os_log("Xray остановлен", log: coreLog, type: .info)
    }
}

// MARK: - tun2socks (utun ↔ SOCKS)

final class Tun2Socks {
    static let shared = Tun2Socks()
    private init() {}

    private var statsTimer: DispatchSourceTimer?
    private var lastUp = 0
    private var lastDown = 0

    /// Перекачивает пакеты между системным туннелем и локальным SOCKS.
    ///
    /// packetFlow в параметрах остался для единообразия с Android-веткой, но
    /// не используется: библиотека сама находит файловый дескриптор туннеля,
    /// перебирая открытые сокеты расширения. Передать его снаружи нельзя —
    /// NEPacketTunnelFlow дескриптор не отдаёт.
    func start(packetFlow: NEPacketTunnelFlow,
               socksHost: String,
               socksPort: Int,
               onBytes: @escaping (_ up: Int, _ down: Int,
                                   _ upSpeed: Int, _ downSpeed: Int) -> Void) {
        #if canImport(Tun2SocksKit)
        // Конфиг hev-socks5-tunnel. MTU 8500 — значение из их же примеров:
        // крупные пакеты снижают число переходов через границу стека.
        // Логи выключены намеренно: расширению отведено мало памяти, и
        // подробный лог на нагруженном туннеле её съедает.
        let config = """
        tunnel:
          mtu: 8500
        socks5:
          address: \(socksHost)
          port: \(socksPort)
          udp: udp
        misc:
          task-stack-size: 20480
          log-level: none
        """

        Socks5Tunnel.run(withConfig: .string(content: config)) { code in
            os_log("tun2socks завершился с кодом %d", log: coreLog, type: .info, code)
        }
        os_log("tun2socks запущен → %{public}@:%d",
               log: coreLog, type: .info, socksHost, socksPort)

        startStatsPolling(onBytes: onBytes)
        #else
        os_log("ЗАГЛУШКА: Tun2SocksKit не подключён — трафика не будет",
               log: coreLog, type: .error)
        readLoop(packetFlow: packetFlow)
        #endif
    }

    func stop() {
        statsTimer?.cancel()
        statsTimer = nil
        #if canImport(Tun2SocksKit)
        Socks5Tunnel.quit()
        #endif
        _running = false
        os_log("tun2socks остановлен", log: coreLog, type: .info)
    }

    #if canImport(Tun2SocksKit)
    /// Раз в секунду снимает счётчики и отдаёт приложению.
    ///
    /// Библиотека даёт накопленные суммы, а показать надо ещё и скорость —
    /// считаем её сами как разницу с прошлым замером. Секунда выбрана не
    /// случайно: чаще опрашивать незачем, цифры на экране всё равно
    /// обновляются раз в секунду, а расширение тратит на это батарею.
    private func startStatsPolling(
        onBytes: @escaping (Int, Int, Int, Int) -> Void) {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let s = Socks5Tunnel.stats
            let up = s.up.bytes
            let down = s.down.bytes
            let upSpeed = max(0, up - self.lastUp)
            let downSpeed = max(0, down - self.lastDown)
            self.lastUp = up
            self.lastDown = down
            onBytes(up, down, upSpeed, downSpeed)
        }
        timer.resume()
        statsTimer = timer
    }
    #endif

    private var _running = true

    /// Запасной путь без библиотеки: просто вычитываем пакеты, чтобы система
    /// не копила очередь. Трафик при этом никуда не идёт.
    private func readLoop(packetFlow: NEPacketTunnelFlow) {
        packetFlow.readPackets { [weak self] _, _ in
            guard let self, self._running else { return }
            self.readLoop(packetFlow: packetFlow)
        }
    }
}
