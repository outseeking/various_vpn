//  XrayCore.swift
//  Тонкая обёртка над нативными бинарями VPN-ядра для iOS:
//    • XrayCore   — запуск Xray-core (libXray.xcframework, gomobile);
//    • Tun2Socks  — перекачка utun ↔ локальный SOCKS (hev-socks5-tunnel).
//
//  Чтобы проект СОБИРАЛСЯ и БЕЗ этих бинарей (у нас пока нет Mac/Xcode для их
//  сборки), здесь стоят условные заглушки через `#if canImport(...)`. Когда на
//  Mac добавишь xcframework в таргет PacketTunnelProvider, ветка `#if` включит
//  реальный код. Инструкция: ios/README_iOS.md.

import Foundation
import NetworkExtension
import os.log

private let coreLog = OSLog(subsystem: "site.ugconnect.variousvpn", category: "core")

// MARK: - Xray-ядро

final class XrayCore {
    static let shared = XrayCore()
    private init() {}

    /// Запускает Xray с готовым JSON-конфигом (тот же, что строит приложение).
    /// SOCKS-инбаунд внутри конфига слушает 127.0.0.1:socksPort.
    func start(configJSON: String, socksPort: Int) throws {
        #if canImport(LibXray)
        // Реальная интеграция (пример; уточни имя функции под свой форк libXray):
        //   let datDir = FileManager.default.temporaryDirectory.path
        //   let res = LibXrayRunXrayFromJSON(datDir, configJSON)
        //   if let err = parseLibXrayError(res) { throw err }
        LibXrayBridge.run(config: configJSON)
        os_log("Xray started (libXray)", log: coreLog, type: .info)
        #else
        // Заглушка: ядро не слинковано. Туннель поднимется (проверка обвязки),
        // но трафик через SOCKS не пойдёт, пока не добавишь libXray.xcframework.
        os_log("Xray STUB — libXray не подключён, трафика не будет", log: coreLog, type: .error)
        #endif
    }

    func stop() {
        #if canImport(LibXray)
        LibXrayBridge.stop()
        #endif
        os_log("Xray stopped", log: coreLog, type: .info)
    }
}

// MARK: - tun2socks (utun ↔ SOCKS)

final class Tun2Socks {
    static let shared = Tun2Socks()
    private init() {}

    /// Перекачивает пакеты между utun (packetFlow) и локальным SOCKS-прокси.
    /// onBytes отдаёт накопленные байты/скорость для показа в приложении.
    func start(packetFlow: NEPacketTunnelFlow,
               socksHost: String,
               socksPort: Int,
               onBytes: @escaping (_ up: Int, _ down: Int, _ upSpeed: Int, _ downSpeed: Int) -> Void) {
        #if canImport(HevSocks5Tunnel)
        // Реальная интеграция hev-socks5-tunnel: сгенерировать YAML-конфиг с
        // tunnel-fd (из packetFlow) и socks5 { address, port } и запустить.
        HevSocks5TunnelBridge.start(packetFlow: packetFlow, socksHost: socksHost,
                                    socksPort: socksPort, onBytes: onBytes)
        os_log("tun2socks started (hev)", log: coreLog, type: .info)
        #else
        // Заглушка: только читаем пакеты из utun, чтобы система не копила очередь.
        os_log("tun2socks STUB — hev-socks5-tunnel не подключён", log: coreLog, type: .error)
        readLoop(packetFlow: packetFlow)
        #endif
    }

    func stop() {
        #if canImport(HevSocks5Tunnel)
        HevSocks5TunnelBridge.stop()
        #endif
        _running = false
    }

    private var _running = true
    private func readLoop(packetFlow: NEPacketTunnelFlow) {
        packetFlow.readPackets { [weak self] _, _ in
            guard let self = self, self._running else { return }
            self.readLoop(packetFlow: packetFlow) // держим очередь пустой
        }
    }
}
