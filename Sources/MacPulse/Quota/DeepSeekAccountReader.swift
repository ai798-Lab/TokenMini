import Foundation

struct DeepSeekBalance: Sendable {
    struct Amount: Sendable {
        let currency: String
        let total: String
        var display: String { currency + " " + total }
    }
    let available: Bool
    let amounts: [Amount]
    let asOf: Date
}

/// Reads an existing API credential only after the user enables this source.
/// Requests are restricted to DeepSeek's two read-only account endpoints.
enum DeepSeekAccountReader {
    enum Failure: LocalizedError {
        case missingCredential, unauthorized, unavailable, invalidResponse
        var errorDescription: String? {
            switch self {
            case .missingCredential: return L10n.text("未找到 DeepSeek API 密钥；支持 DEEPSEEK_API_KEY 或本机 DeepSeek Harness 凭证。")
            case .unauthorized: return L10n.text("DeepSeek 拒绝了当前 API 密钥，请检查账号凭证。")
            case .unavailable: return L10n.text("暂时无法连接 DeepSeek，保留上次余额。")
            case .invalidResponse: return L10n.text("DeepSeek 返回格式无法识别，未将余额记为零。")
            }
        }
    }

    static func credential(environment: [String: String] = ProcessInfo.processInfo.environment,
                           home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> String {
        if let key = validatedKey(environment["DEEPSEEK_API_KEY"]) { return key }
        let file = home.appendingPathComponent(".dsh/.credentials.yaml")
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 64 * 1024,
              let text = try? String(contentsOf: file, encoding: .utf8),
              let key = credential(inYAML: text) else { throw Failure.missingCredential }
        return key
    }

    // Deliberately narrow parser: no generic YAML evaluation and no OAuth grant traversal.
    static func credential(inYAML text: String) -> String? {
        var inRefs = false
        for line in text.split(separator: "\n") {
            let raw = String(line), value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !raw.hasPrefix(" ") && !raw.hasPrefix("\t") {
                inRefs = value == "refs:"
            }
            guard (inRefs || raw == value), value.hasPrefix("DEEPSEEK_API_KEY:") else { continue }
            var key = String(value.dropFirst("DEEPSEEK_API_KEY:".count)).trimmingCharacters(in: .whitespaces)
            if key.hasPrefix("\""), key.hasSuffix("\"") { key = String(key.dropFirst().dropLast()) }
            if key.hasPrefix("'"), key.hasSuffix("'") { key = String(key.dropFirst().dropLast()) }
            if let valid = validatedKey(key) { return valid }
        }
        return nil
    }

    private static func validatedKey(_ key: String?) -> String? {
        guard let key, key.hasPrefix("sk-"), (20...256).contains(key.utf8.count),
              key.utf8.allSatisfy({ (45...46).contains($0) || (48...57).contains($0) || (65...90).contains($0) || $0 == 95 || (97...122).contains($0) }) else { return nil }
        return key
    }

    static func fetchBalance(key: String) async throws -> DeepSeekBalance {
        try parseBalance(await request(path: "user/balance", key: key))
    }

    static func fetchModels(key: String) async throws -> [String] {
        let data = try await request(path: "models", key: key)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["data"] as? [[String: Any]], rows.count <= 1000 else { throw Failure.invalidResponse }
        return Array(Set(rows.compactMap { $0["id"] as? String }.filter { !$0.isEmpty && $0.count <= 160 })).sorted()
    }

    static func parseBalance(_ data: Data, now: Date = Date()) throws -> DeepSeekBalance {
        struct Response: Decodable {
            struct Amount: Decodable { let currency: String; let total_balance: String }
            let is_available: Bool
            let balance_infos: [Amount]
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data), !response.balance_infos.isEmpty,
              response.balance_infos.count <= 8 else { throw Failure.invalidResponse }
        let amounts = try response.balance_infos.map { row -> DeepSeekBalance.Amount in
            guard ["CNY", "USD"].contains(row.currency), row.total_balance.count <= 40,
                  let number = Double(row.total_balance), number.isFinite else { throw Failure.invalidResponse }
            return .init(currency: row.currency, total: row.total_balance)
        }
        return .init(available: response.is_available, amounts: amounts, asOf: now)
    }

    private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }

    private static func request(path: String, key: String) async throws -> Data {
        guard ["models", "user/balance"].contains(path) else { throw Failure.invalidResponse }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 25
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/" + path)!)
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw Failure.invalidResponse }
            if [401, 403].contains(http.statusCode) { throw Failure.unauthorized }
            guard http.statusCode == 200, data.count <= 1_048_576 else { throw Failure.unavailable }
            return data
        } catch let error as Failure { throw error }
        catch { throw Failure.unavailable }
    }
}
