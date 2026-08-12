//  LibXrayBridge.swift
//  Мост к готовому бинарнику libXray (LibXray.xcframework).
//
//  У библиотеки ровно одна точка входа: CGoInvoke(json) → json. Всё общение
//  идёт запросами вида {"apiVersion":2,"method":"runXray","payload":{...}}.
//  Список методов и форму запросов взяты из invoke_model.go самой библиотеки,
//  а не выдуманы: apiVersion сверяется на стороне Go, и при несовпадении
//  вызов возвращает ошибку, а не работает «как-нибудь».
//
//  Отдельно важное про geo-списки. Правила маршрутизации приложения опираются
//  на geosite: и geoip: — обход РФ, блокировка рекламы, домены ИИ. Xray ищет
//  файлы geoip.dat и geosite.dat в каталоге из переменной окружения
//  XRAY_LOCATION_ASSET. Если её не выставить, Xray не «пропустит» правило, а
//  ОТКАЖЕТСЯ СТАРТОВАТЬ — то есть VPN не включится вовсе. Поэтому переменная
//  ставится до первого обращения к ядру, в setupAssets().

import Foundation
import os.log

private let bridgeLog = OSLog(subsystem: "site.ugconnect.variousvpn",
                              category: "libxray")

enum LibXrayError: LocalizedError {
    case notLinked
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notLinked:
            return "LibXray.xcframework не подключён к таргету"
        case .failed(let message):
            return message
        }
    }
}

enum LibXrayBridge {

    /// Версия протокола общения с библиотекой. Должна совпадать с
    /// LibXrayAPIVersion в invoke_model.go — иначе любой вызов вернёт ошибку.
    private static let apiVersion = 2

    // MARK: - Каталог geo-списков

    /// Готовит каталог с geoip.dat / geosite.dat и сообщает о нём ядру.
    ///
    /// Файлы лежат в бандле расширения, но Xray умеет читать только из
    /// каталога на диске, путь к которому взят из окружения. Копируем их в
    /// общий контейнер один раз: перезапись при каждом старте туннеля стоила
    /// бы лишних мегабайт записи на флеш.
    @discardableResult
    static func setupAssets() -> String? {
        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory,
                                    in: .userDomainMask).first else {
            return nil
        }
        let dir = support.appendingPathComponent("xray-assets", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        for name in ["geoip.dat", "geosite.dat"] {
            let dst = dir.appendingPathComponent(name)
            guard !fm.fileExists(atPath: dst.path) else { continue }
            guard let src = Bundle.main.url(forResource: name, withExtension: nil)
            else {
                os_log("%{public}@ нет в бандле — правила geosite/geoip работать не будут",
                       log: bridgeLog, type: .error, name)
                continue
            }
            try? fm.copyItem(at: src, to: dst)
        }

        setenv("XRAY_LOCATION_ASSET", dir.path, 1)
        os_log("geo-списки: %{public}@", log: bridgeLog, type: .info, dir.path)
        return dir.path
    }

    // MARK: - Вызовы

    static func run(config: String) throws {
        setupAssets()
        _ = try invoke(method: "runXray", payload: ["xrayJson": config])
    }

    static func stop() {
        _ = try? invoke(method: "stopXray", payload: nil)
    }

    static func isRunning() -> Bool {
        guard let data = try? invoke(method: "getXrayState", payload: nil),
              let dict = data as? [String: Any] else { return false }
        return dict["running"] as? Bool ?? false
    }

    static func version() -> String {
        guard let data = try? invoke(method: "xrayVersion", payload: nil),
              let dict = data as? [String: Any] else { return "неизвестно" }
        return dict["version"] as? String ?? "неизвестно"
    }

    /// Замер задержки СРАЗУ ПО МНОГИМ конфигам одним вызовом.
    ///
    /// Ради этого метод и стоит отдельно. На Android каждый замер поднимает
    /// собственный экземпляр ядра: два десятка серверов — полсотни запусков за
    /// полминуты, и живой туннель остаётся без процессора. Здесь библиотека
    /// меряет весь список внутри себя, одним вызовом и без такой платы.
    static func pingBatch(configs: [(json: String, tag: String)],
                          url: String,
                          timeoutSeconds: Int) throws -> [Int] {
        let payload: [String: Any] = [
            "configs": configs.map { ["xrayJson": $0.json, "outboundTag": $0.tag] },
            "timeout": timeoutSeconds,
            "url": url,
        ]
        let data = try invoke(method: "pingBatch", payload: payload)
        guard let dict = data as? [String: Any],
              let results = dict["results"] as? [[String: Any]] else { return [] }
        return results.map { item in
            // −1 у нас всюду означает «не ответил»: та же величина, что и на
            // Android, чтобы верхний слой не разбирался в различиях платформ.
            (item["success"] as? Bool ?? false)
                ? Int(item["delay"] as? Int64 ?? -1)
                : -1
        }
    }

    // MARK: - Транспорт

    private static func invoke(method: String,
                               payload: [String: Any]?) throws -> Any? {
        #if canImport(LibXray)
        var request: [String: Any] = [
            "apiVersion": apiVersion,
            "method": method,
        ]
        if let payload { request["payload"] = payload }

        let body = try JSONSerialization.data(withJSONObject: request)
        guard let text = String(data: body, encoding: .utf8) else {
            throw LibXrayError.failed("запрос не собрался")
        }

        guard let raw = CGoInvoke(strdup(text)) else {
            throw LibXrayError.failed("библиотека не ответила")
        }
        // Память под ответ выделена на стороне Go — освобождать обязана она же.
        defer { CGoFree(raw) }

        let answer = String(cString: raw)
        guard let parsed = try JSONSerialization.jsonObject(
            with: Data(answer.utf8)) as? [String: Any] else {
            throw LibXrayError.failed("ответ не разобрался: \(answer.prefix(200))")
        }
        if parsed["success"] as? Bool == true { return parsed["data"] }
        throw LibXrayError.failed(parsed["error"] as? String ?? "неизвестная ошибка")
        #else
        throw LibXrayError.notLinked
        #endif
    }
}
