import Foundation
import CryptoKit
import CommonCrypto
import CoreFoundation

/// Swift adaptation of TokenTracker a726cd5, MIT. See Resources/ThirdParty.
/// Explicit opt-in only. Credentials stay in memory; requests are pinned to Trae's official host.
enum TraeUsageClient {
    struct Failure: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }
    static let endpoint = URL(string: "https://api.trae.cn/trae/api/v1/pay/query_user_usage_group_by_session")!
    static func cacheURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support/TokenMini/trae-usage.json")
    }
    static func cached(home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> [UsageRecord] {
        let url = cacheURL(home: home)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([UsageRecord].self, from: Data(contentsOf: url))
    }
    static func fetchAndSave(home: URL = FileManager.default.homeDirectoryForCurrentUser) async throws -> Int {
        guard UserDefaults.standard.bool(forKey: "traeUsageSyncEnabled") else { throw Failure(message: "尚未启用 Trae 官方用量同步。") }
        let jwt = try credential(home: home)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.httpCookieStorage = nil
        let session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let end = Int(Date().timeIntervalSince1970), start = end - 30 * 86400
        var result: [UsageRecord] = [], seen = Set<String>()
        var expectedTotal: Int?, fetched = 0, complete = false
        for page in 1...100 {
            guard UserDefaults.standard.bool(forKey: "traeUsageSyncEnabled") else { throw CancellationError() }
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Cloud-IDE-JWT " + jwt, forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["usage_type": [7], "start_time": start,
                "end_time": end, "page_num": page, "page_size": 20])
            let data: Data, response: URLResponse
            do { (data, response) = try await session.data(for: request) }
            catch { throw Failure(message: "Trae 官方用量请求失败，请稍后重试。") }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw Failure(message: "Trae 未接受查询，请在 Trae Work 中重新登录后重试。")
            }
            let parsed = try parsePage(data)
            if let total = parsed.total {
                if let previous = expectedTotal, previous != total { throw Failure(message: "查询期间用量变化，请重试以获取完整数据。") }
                expectedTotal = total
                guard total <= 2000 else { throw Failure(message: "近 30 天超过 2000 个会话，当前结果未保存，避免截断统计。") }
            }
            fetched += parsed.rows.count
            for row in parsed.rows {
                guard seen.insert(row.id).inserted else { throw Failure(message: "Trae 返回重复分页，当前结果未保存。") }
                result.append(row)
            }
            if parsed.rows.isEmpty || (expectedTotal != nil && fetched >= expectedTotal!) {
                if let total = expectedTotal, fetched != total { throw Failure(message: "Trae 用量分页不完整，原有记录已保留。") }
                complete = true; break
            }
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        guard complete else { throw Failure(message: "Trae 用量超过分页上限，原有记录已保留。") }
        guard UserDefaults.standard.bool(forKey: "traeUsageSyncEnabled") else { throw CancellationError() }
        let url = cacheURL(home: home)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(result).write(to: url, options: .atomic)
        return result.count
    }
    static func parsePage(_ data: Data) throws -> (rows: [UsageRecord], total: Int?) {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw Failure(message: "Trae 返回格式异常。") }
        let payload = root["data"] as? [String: Any] ?? root
        if let code = (payload["code"] ?? root["code"]) as? NSNumber, code.intValue != 0 { throw Failure(message: "Trae 官方用量接口返回错误。") }
        guard let rows = payload["user_usage_group_by_sessions"] as? [[String: Any]] else { throw Failure(message: "Trae 返回缺少会话列表。") }
        var total: Int?
        if let raw = payload["total"], !(raw is NSNull) {
            guard let n = raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite,
                  n.doubleValue >= 0, n.doubleValue.rounded() == n.doubleValue, n.doubleValue <= 1_000_000 else { throw Failure(message: "Trae 分页总数无效。") }
            total = n.intValue
        }
        let records = try rows.map { row -> UsageRecord in
            var extra = row["extra_info"] as? [String: Any] ?? [:]
            if let string = row["extra_info"] as? String, let data = string.data(using: .utf8),
               let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { extra = decoded }
            guard let id = row["session_id"] as? String, !id.isEmpty,
                  let date = UsageRecord.date(row["usage_time"]) else { throw Failure(message: "Trae 会话标识或时间无效。") }
            func token(_ key: String) throws -> Int {
                guard let raw = row[key] ?? extra[key] else { return 0 }
                guard let n = raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite,
                      n.doubleValue >= 0, n.doubleValue.rounded() == n.doubleValue,
                      n.doubleValue <= Double(UsageValueSanitizer.maxTokensPerEvent) else { throw Failure(message: "Trae Token 计数无效。") }
                return n.intValue
            }
            guard row["input_token"] != nil || extra["input_token"] != nil,
                  row["output_token"] != nil || extra["output_token"] != nil else { throw Failure(message: "Trae 会话缺少 Token 计数。") }
            let input = try token("input_token"), output = try token("output_token")
            let read = min(input, try token("cache_read_token"))
            let write = min(input - read, try token("cache_write_token"))
            return UsageRecord(id: "traeWork:" + id, timestamp: date, tool: .traeWork,
                model: row["model_name"] as? String ?? "unknown", input: input - read - write,
                output: output, cacheWrite: write, cacheRead: read, project: "Trae Work CN", session: "traeWork:" + id)
        }
        return (records, total)
    }
    private static func credential(home: URL) throws -> String {
        let file = home.appendingPathComponent("Library/Application Support/TRAE SOLO CN/User/globalStorage/storage.json")
        guard let data = try? Data(contentsOf: file),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = obj["iCubeAuthInfo://icube.cloudide"] else { throw Failure(message: "未找到可读的 Trae Work CN 登录状态，请先打开并登录 Trae Work。") }
        let auth: [String: Any]
        if let dictionary = value as? [String: Any] { auth = dictionary }
        else if let text = value as? String {
            let bytes: Data
            if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") { bytes = Data(text.utf8) }
            else { bytes = try decrypt(Data(base64Encoded: text) ?? Data()) }
            guard let dictionary = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw Failure(message: "Trae 登录状态格式不兼容。") }
            auth = dictionary
        } else { throw Failure(message: "Trae 登录状态格式不兼容。") }
        guard let token = auth["token"] as? String, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure(message: "Trae 登录已失效，请在原应用重新登录。") }
        return token.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    // Vendor tc-v5 format compatibility, ported from TokenTracker (MIT), not password storage.
    static func decrypt(_ blob: Data) throws -> Data {
        let failure = Failure(message: "Trae 登录状态格式不兼容，请更新适配器。")
        guard blob.count >= 54, blob.prefix(6) == Data([0x74,0x63,0x05,0x10,0,0]), (blob.count - 38) % 16 == 0 else { throw failure }
        let j: [UInt8] = [82,9,106,213,48,54,165,56,191,64,163,158,129,243,215,251,124,227,57,130,155,47,255,135,52,142,67,68,196,222,233,203,84,123,148,50,166,194,35,61,238,76,149,11,66,250,195,78,8,46,161,102,40,217,36,178,118,91,162,73,109,139,209,37]
        let k: [UInt8] = [31,221,168,51,136,7,199,49,177,18,16,89,39,128,236,95,96,81,127,169,25,181,74,13,45,229,122,159,147,201,156,239,160,224,59,77,174,42,245,176,200,235,187,60,131,83,153,97,23,43,4,126,186,119,214,38,225,105,20,99,85,33,12,125]
        let seed = Data(SHA512.hash(data: blob.subdata(in: 6..<38))) + Data(zip(j, k).map { $0 ^ $1 })
        let derived = Data(SHA512.hash(data: seed)), key = derived.prefix(16), iv = derived.subdata(in: 16..<32)
        let ciphertext = blob.subdata(in: 38..<blob.count)
        var plain = Data(count: ciphertext.count + 16), written = 0
        let capacity = plain.count
        let result = plain.withUnsafeMutableBytes { output in
            ciphertext.withUnsafeBytes { input in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, 16, ivBytes.baseAddress, input.baseAddress, ciphertext.count,
                            output.baseAddress, capacity, &written)
                    }
                }
            }
        }
        guard result == kCCSuccess, written >= 64 else { throw failure }
        plain.count = written
        let payload = plain.dropFirst(64)
        guard plain.prefix(64) == Data(SHA512.hash(data: payload)) else { throw failure }
        return Data(payload)
    }
    private final class NoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
}
