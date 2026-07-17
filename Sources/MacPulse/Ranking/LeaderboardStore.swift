import Combine
import Foundation

@MainActor
final class LeaderboardStore: ObservableObject {
    @Published var metric: RankingMetric = .tokens
    @Published private(set) var isJoined = false
    @Published private(set) var profile: RankingProfile?
    @Published private(set) var ranking: RankingListResponse?
    @Published private(set) var rankingError: String?
    @Published private(set) var me: RankingMeResponse?
    @Published private(set) var loading = false
    @Published private(set) var signingIn = false
    @Published private(set) var syncing = false
    @Published private(set) var lastSyncAt: Date?
    @Published var message: String?

    private let api = RankingAPIClient(baseURL: AppInfo.homepage)
    private weak var usage: UsageStore?
    private var usageScanObservation: AnyCancellable?
    private var accessToken: String?
    private var refreshToken: String?
    private var refreshTask: Task<RankingRefreshResponse, Swift.Error>?
    private var lastUploadFingerprint: String?
    private var started = false

    init() {
        accessToken = RankingKeychain.load(.access)
        refreshToken = RankingKeychain.load(.refresh)
        isJoined = refreshToken != nil
    }

    func start(usage: UsageStore) {
        guard !started else { return }
        started = true
        self.usage = usage
        usageScanObservation = usage.$lastScan
            .compactMap { $0 }
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.syncIfNeeded()
                }
            }
        guard isJoined else { return }
        Task { [weak self] in
            await self?.syncIfNeeded(force: true)
        }
    }

    /// 打开排行榜窗口时调用。公开榜单不要求登录。
    func load() async {
        loading = true
        rankingError = nil
        let selected = metric
        do {
            async let publicResult = api.rankings(metric: selected)
            if isJoined {
                async let myResult: RankingMeResponse = authorized { token in
                    try await self.api.myRanking(accessToken: token)
                }
                let (nextRanking, nextMe) = try await (publicResult, myResult)
                guard metric == selected else { loading = false; return }
                ranking = nextRanking
                me = nextMe
                profile = nextMe.profile
            } else {
                let nextRanking = try await publicResult
                guard metric == selected else { loading = false; return }
                ranking = nextRanking
                me = nil
            }
        } catch {
            rankingError = readable(error)
        }
        loading = false
    }

    /// 唯一加入入口：Google 登录成功即加入，默认打码展示。
    func signInAndJoin() async {
        guard !signingIn else { return }
        signingIn = true
        message = nil
        do {
            let config = try await api.config()
            guard config.authReady, let clientID = config.googleDesktopClientID, !clientID.isEmpty else {
                throw RankingAPIError.configuration("排行榜登录尚未开放")
            }
            let idToken = try await GoogleOAuthClient().signIn(clientID: clientID)
            let auth = try await api.googleLogin(idToken: idToken, appVersion: AppInfo.displayVersion)
            do {
                try persist(access: auth.accessToken, refresh: auth.refreshToken)
            } catch {
                try? await api.leaveRanking(accessToken: auth.accessToken)
                throw RankingAPIError.keychain
            }
            profile = auth.profile
            isJoined = true
            await syncIfNeeded(force: true)
            await load()
        } catch {
            message = readable(error)
        }
        signingIn = false
    }

    func setPublicName(_ enabled: Bool) async {
        guard isJoined else { return }
        message = nil
        do {
            try await authorized { token in
                try await self.api.setDisplayMode(enabled ? "public" : "masked", accessToken: token)
            }
            if var next = profile {
                next.displayMode = enabled ? "public" : "masked"
                profile = next
            }
            if var next = me {
                next.profile.displayMode = enabled ? "public" : "masked"
                me = next
            }
            await load()
        } catch {
            message = readable(error)
        }
    }

    /// 退出排行榜会先让服务端删除公开榜单数据和刷新会话，成功后再清本机钥匙串。
    func leave() async {
        guard isJoined else { return }
        message = nil
        do {
            try await authorized { token in
                try await self.api.leaveRanking(accessToken: token)
            }
            clearLocalSession()
            rankingError = nil
            await load()
        } catch {
            message = readable(error)
        }
    }

    func syncIfNeeded(force: Bool = false) async {
        guard isJoined, let usage, !syncing else { return }
        let aggregate = usage.rankingDailyAggregate()
        let fingerprint = "\(aggregate.localDay):\(aggregate.totalTokens):\(aggregate.estimatedCostMicroUSD)"
        if !force {
            if lastUploadFingerprint == fingerprint { return }
            if let lastSyncAt, Date().timeIntervalSince(lastSyncAt) < 10 * 60 { return }
        }
        syncing = true
        do {
            try await authorized { token in
                try await self.api.upload(aggregate, accessToken: token)
            }
            lastUploadFingerprint = fingerprint
            lastSyncAt = Date()
            if me != nil {
                me = try? await authorized { token in
                    try await self.api.myRanking(accessToken: token)
                }
                profile = me?.profile ?? profile
            }
        } catch {
            // 排行榜故障不影响本地监控；错误仅在排行榜页中展示。
            if message == nil { message = "排行榜同步暂时不可用，本地监控不受影响" }
        }
        syncing = false
    }

    private func authorized<T>(_ operation: @escaping (String) async throws -> T) async throws -> T {
        guard let accessToken else { return try await retryAfterRefresh(operation) }
        do {
            return try await operation(accessToken)
        } catch RankingAPIError.unauthorized {
            return try await retryAfterRefresh(operation)
        }
    }

    private func retryAfterRefresh<T>(
        _ operation: @escaping (String) async throws -> T
    ) async throws -> T {
        let token = try await refreshAccessToken()
        return try await operation(token)
    }

    private func refreshAccessToken() async throws -> String {
        if let refreshTask {
            return try await applyRefresh(refreshTask.value)
        }
        guard let refreshToken else {
            clearLocalSession()
            throw RankingAPIError.unauthorized
        }
        let task = Task { try await api.refresh(refreshToken: refreshToken) }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            return try await applyRefresh(task.value)
        } catch RankingAPIError.unauthorized {
            clearLocalSession()
            throw RankingAPIError.unauthorized
        }
    }

    private func applyRefresh(_ response: RankingRefreshResponse) throws -> String {
        try persist(access: response.accessToken, refresh: response.refreshToken)
        return response.accessToken
    }

    private func persist(access: String, refresh: String) throws {
        do {
            try RankingKeychain.store(access, as: .access)
            try RankingKeychain.store(refresh, as: .refresh)
        } catch {
            RankingKeychain.clear()
            throw error
        }
        accessToken = access
        refreshToken = refresh
    }

    private func clearLocalSession() {
        RankingKeychain.clear()
        accessToken = nil
        refreshToken = nil
        refreshTask?.cancel()
        refreshTask = nil
        isJoined = false
        profile = nil
        me = nil
        lastUploadFingerprint = nil
        lastSyncAt = nil
    }

    private func readable(_ error: Swift.Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription { return description }
        return "服务暂时不可用，请稍后重试"
    }
}

private struct RankingAPIClient {
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: URL) {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration)
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    func config() async throws -> RankingConfigResponse {
        try await request(path: "/api/v1/config")
    }

    func googleLogin(idToken: String, appVersion: String) async throws -> RankingAuthResponse {
        try await request(
            path: "/api/v1/auth/google", method: "POST",
            body: GoogleLoginBody(idToken: idToken, displayMode: "masked", appVersion: appVersion))
    }

    func refresh(refreshToken: String) async throws -> RankingRefreshResponse {
        try await request(
            path: "/api/v1/auth/refresh", method: "POST",
            body: RefreshBody(refreshToken: refreshToken))
    }

    func rankings(metric: RankingMetric) async throws -> RankingListResponse {
        try await request(path: "/api/v1/rankings", query: [URLQueryItem(name: "metric", value: metric.rawValue)])
    }

    func myRanking(accessToken: String) async throws -> RankingMeResponse {
        try await request(path: "/api/v1/rankings/me", accessToken: accessToken)
    }

    func upload(_ aggregate: RankingDailyAggregate, accessToken: String) async throws {
        let _: EmptyResponse = try await request(
            path: "/api/v1/me/daily-usage", method: "PUT",
            accessToken: accessToken, body: aggregate)
    }

    func setDisplayMode(_ mode: String, accessToken: String) async throws {
        let _: EmptyResponse = try await request(
            path: "/api/v1/me/display-mode", method: "PATCH",
            accessToken: accessToken, body: DisplayModeBody(displayMode: mode))
    }

    func leaveRanking(accessToken: String) async throws {
        let _: EmptyResponse = try await request(
            path: "/api/v1/me/ranking", method: "DELETE", accessToken: accessToken)
    }

    private func request<Response: Decodable>(
        path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        accessToken: String? = nil
    ) async throws -> Response {
        try await perform(path: path, method: method, query: query, accessToken: accessToken, body: nil)
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        query: [URLQueryItem] = [],
        accessToken: String? = nil,
        body: Body
    ) async throws -> Response {
        try await perform(
            path: path, method: method, query: query,
            accessToken: accessToken, body: try encoder.encode(body))
    }

    private func perform<Response: Decodable>(
        path: String,
        method: String,
        query: [URLQueryItem],
        accessToken: String?,
        body: Data?
    ) async throws -> Response {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { throw RankingAPIError.configuration("服务地址无效") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("MacPulse/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RankingAPIError.invalidResponse }
        if http.statusCode == 401 { throw RankingAPIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            let server = try? decoder.decode(ServerErrorBody.self, from: data)
            throw RankingAPIError.server(server?.message ?? "服务暂时不可用", http.statusCode)
        }
        if Response.self == EmptyResponse.self {
            return EmptyResponse() as! Response
        }
        do { return try decoder.decode(Response.self, from: data) }
        catch { throw RankingAPIError.invalidResponse }
    }
}

private struct GoogleLoginBody: Encodable {
    let idToken: String
    let displayMode: String
    let appVersion: String
}

private struct RefreshBody: Encodable { let refreshToken: String }
private struct DisplayModeBody: Encodable { let displayMode: String }
private struct ServerErrorBody: Decodable { let message: String }
private struct EmptyResponse: Decodable { init() {} }

private enum RankingAPIError: LocalizedError {
    case unauthorized
    case invalidResponse
    case server(String, Int)
    case configuration(String)
    case keychain

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "登录已失效，请重新使用 Google 登录"
        case .invalidResponse: return "排行榜服务返回了无法识别的数据"
        case .server(let message, _): return message
        case .configuration(let message): return message
        case .keychain: return "无法把登录状态安全保存到钥匙串"
        }
    }
}
