//  VPNManager.swift
//  Управление системным VPN (NetworkExtension) со стороны основного приложения.
//
//  Приложение НЕ гоняет трафик само — оно только устанавливает/запускает
//  профиль NETunnelProviderManager, который поднимает расширение
//  PacketTunnelProvider (там и живёт Xray-ядро). Конфиг передаётся расширению
//  через App Group (общие UserDefaults), статус — через KVO NEVPNStatus.
//
//  Разделение платформ: этот файл — ТОЛЬКО iOS. Android-ядро живёт в
//  android/ (Kotlin + flutter_v2ray). См. PLATFORMS.md.

import Foundation
import NetworkExtension
import Flutter

enum VPNConst {
    // App Group — общий контейнер приложения и расширения (должен совпадать в
    // обоих entitlements). При смене bundle id поменяй и здесь.
    static let appGroup = "group.com.example.variousVpn"
    // Bundle id расширения Packet Tunnel Provider.
    static let tunnelBundleId = "com.example.variousVpn.PacketTunnel"
    static let serverAddress = "Various VPN"
}

final class VPNManager: NSObject {
    static let shared = VPNManager()

    private var manager: NETunnelProviderManager?
    var onStage: ((String) -> Void)?
    var onTraffic: (([String: Int]) -> Void)?
    private var trafficTimer: Timer?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(statusChanged),
            name: .NEVPNStatusDidChange, object: nil)
    }

    // MARK: - Публичный API (вызывается из MethodChannel)

    /// Устанавливает профиль (первый раз показывает системный диалог разрешения).
    func prepare(_ completion: @escaping (Bool) -> Void) {
        loadOrCreate { mgr in
            guard let mgr = mgr else { completion(false); return }
            mgr.isEnabled = true
            mgr.saveToPreferences { err in
                completion(err == nil)
            }
        }
    }

    /// Сохраняет конфиг в App Group и запускает туннель.
    func connect(config: String, remark: String, completion: @escaping (Bool, String?) -> Void) {
        // 1) конфиг Xray → в общий контейнер (его читает расширение)
        if let d = UserDefaults(suiteName: VPNConst.appGroup) {
            d.set(config, forKey: "xray_config")
            d.set(remark, forKey: "remark")
            d.removeObject(forKey: "up_bytes")
            d.removeObject(forKey: "down_bytes")
            d.synchronize()
        }
        // 2) грузим/создаём профиль и стартуем
        loadOrCreate { mgr in
            guard let mgr = mgr else { completion(false, "no manager"); return }
            mgr.isEnabled = true
            mgr.saveToPreferences { saveErr in
                if let saveErr = saveErr { completion(false, saveErr.localizedDescription); return }
                mgr.loadFromPreferences { _ in
                    do {
                        try mgr.connection.startVPNTunnel(options: [
                            "remark": remark as NSObject
                        ])
                        self.startTrafficPolling()
                        completion(true, nil)
                    } catch {
                        completion(false, error.localizedDescription)
                    }
                }
            }
        }
    }

    func disconnect() {
        manager?.connection.stopVPNTunnel()
        stopTrafficPolling()
    }

    // MARK: - Профиль

    private func loadOrCreate(_ done: @escaping (NETunnelProviderManager?) -> Void) {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            if let error = error { print("VPN load error: \(error)"); done(nil); return }
            let mgr = managers?.first ?? NETunnelProviderManager()
            let proto = (mgr.protocolConfiguration as? NETunnelProviderProtocol)
                ?? NETunnelProviderProtocol()
            proto.providerBundleIdentifier = VPNConst.tunnelBundleId
            proto.serverAddress = VPNConst.serverAddress
            proto.providerConfiguration = ["group": VPNConst.appGroup]
            mgr.protocolConfiguration = proto
            mgr.localizedDescription = "Various VPN"
            self.manager = mgr
            done(mgr)
        }
    }

    // MARK: - Статус

    @objc private func statusChanged() {
        let status = manager?.connection.status ?? .invalid
        onStage?(Self.stageString(status))
        if status == .disconnected || status == .invalid {
            stopTrafficPolling()
        }
    }

    static func stageString(_ s: NEVPNStatus) -> String {
        switch s {
        case .connected: return "CONNECTED"
        case .connecting: return "CONNECTING"
        case .reasserting: return "REASSERTING"
        case .disconnecting: return "DISCONNECTING"
        case .disconnected, .invalid: return "DISCONNECTED"
        @unknown default: return "DISCONNECTED"
        }
    }

    // MARK: - Трафик (расширение пишет счётчики в App Group)

    private func startTrafficPolling() {
        DispatchQueue.main.async {
            self.trafficTimer?.invalidate()
            self.trafficTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let d = UserDefaults(suiteName: VPNConst.appGroup) else { return }
                let up = d.integer(forKey: "up_bytes")
                let down = d.integer(forKey: "down_bytes")
                let upS = d.integer(forKey: "up_speed")
                let downS = d.integer(forKey: "down_speed")
                self?.onTraffic?([
                    "up": up, "down": down, "upSpeed": upS, "downSpeed": downS
                ])
            }
        }
    }

    private func stopTrafficPolling() {
        DispatchQueue.main.async {
            self.trafficTimer?.invalidate()
            self.trafficTimer = nil
        }
    }
}

// MARK: - Flutter EventChannel stream handlers

final class StageStreamHandler: NSObject, FlutterStreamHandler {
    func onListen(withArguments _: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        VPNManager.shared.onStage = { stage in events(stage) }
        // сразу отдаём текущий статус
        events(VPNManager.stageString(VPNManager.shared.currentStatus))
        return nil
    }
    func onCancel(withArguments _: Any?) -> FlutterError? {
        VPNManager.shared.onStage = nil
        return nil
    }
}

final class TrafficStreamHandler: NSObject, FlutterStreamHandler {
    func onListen(withArguments _: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        VPNManager.shared.onTraffic = { m in events(m) }
        return nil
    }
    func onCancel(withArguments _: Any?) -> FlutterError? {
        VPNManager.shared.onTraffic = nil
        return nil
    }
}

extension VPNManager {
    var currentStatus: NEVPNStatus { manager?.connection.status ?? .disconnected }
}
