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
      case "liveActivity":
        // Живое событие: Dynamic Island и карточка на экране блокировки.
        // Отдаём результат сразу — показ события идёт своим чередом и ждать
        // его незачем, а Dart из-за ожидания притормозил бы обновление экрана.
        LiveActivityBridge.push(call.arguments as? [String: Any] ?? [:])
        result(nil)
      case "liveActivityStop":
        LiveActivityBridge.stop()
        result(nil)
      case "connectedDelay":
        // Пинг через туннель меряем на стороне Dart; тут -1 (не блокируем UI).
        result(-1)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Смена значка приложения. Канал общий с Android — экран выбора один и
    // тот же, и разводить его по платформам значило бы дублировать логику.
    let status = FlutterMethodChannel(name: "various_vpn/status",
                                      binaryMessenger: messenger)
    status.setMethodCallHandler { call, result in
      switch call.method {
      case "setAppIcon":
        let args = call.arguments as? [String: Any] ?? [:]
        let key = args["key"] as? String ?? "classic"
        // Основной значок задаётся не именем, а его отсутствием: так система
        // отличает возврат к штатному от выбора запасного.
        let name: String? = (key == "classic") ? nil : key
        guard UIApplication.shared.supportsAlternateIcons else {
          result(false)
          return
        }
        // Переключение обязано идти с главной очереди — иначе система молча
        // ничего не делает, и разбираться будет не в чем.
        DispatchQueue.main.async {
          UIApplication.shared.setAlternateIconName(name) { error in
            result(error == nil)
          }
        }
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
