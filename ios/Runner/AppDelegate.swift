import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let stageHandler = StageStreamHandler()
  private let trafficHandler = TrafficStreamHandler()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Бинарный мессенджер берём через registrar плагин-реестра (стабильный API,
    // в отличие от прямого .binaryMessenger, которого у bridge нет).
    if let messenger = engineBridge.pluginRegistry
      .registrar(forPlugin: "VariousVpnChannels")?.messenger() {
      setupVpnChannels(messenger)
    }
  }

  // Мост Flutter ↔ NetworkExtension (см. VPNManager.swift).
  private func setupVpnChannels(_ messenger: FlutterBinaryMessenger) {
    let method = FlutterMethodChannel(name: "various_vpn/ios", binaryMessenger: messenger)
    method.setMethodCallHandler { call, result in
      switch call.method {
      case "prepare":
        VPNManager.shared.prepare { ok in result(ok) }
      case "connect":
        let args = call.arguments as? [String: Any] ?? [:]
        let config = args["config"] as? String ?? ""
        let remark = args["remark"] as? String ?? "Various VPN"
        if config.isEmpty {
          result(FlutterError(code: "no_config", message: "empty config", details: nil))
          return
        }
        VPNManager.shared.connect(config: config, remark: remark) { ok, err in
          if ok { result(true) }
          else { result(FlutterError(code: "connect_failed", message: err, details: nil)) }
        }
      case "disconnect":
        VPNManager.shared.disconnect()
        result(nil)
      case "connectedDelay":
        // Пинг через туннель меряем на стороне Dart; тут -1 (не блокируем UI).
        result(-1)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    FlutterEventChannel(name: "various_vpn/ios/stage", binaryMessenger: messenger)
      .setStreamHandler(stageHandler)
    FlutterEventChannel(name: "various_vpn/ios/traffic", binaryMessenger: messenger)
      .setStreamHandler(trafficHandler)
  }
}
