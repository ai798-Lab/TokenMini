import AppKit
import CryptoKit
import Foundation
import Network
import Security

/// Google Desktop OAuth：系统浏览器 + PKCE + 127.0.0.1 临时回调。
/// 客户端没有 secret，拿到的 Google ID token 仍由 MacPulse 服务端验签。
@MainActor
final class GoogleOAuthClient {
    func signIn(clientID: String) async throws -> String {
        let verifier = try randomURLSafe(byteCount: 32)
        let state = try randomURLSafe(byteCount: 24)
        let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let callbackServer = try LoopbackCallbackServer()
        let port = try await callbackServer.start()
        defer { callbackServer.cancel() }

        let redirectURI = "http://127.0.0.1:\(port)/oauth2redirect"
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        guard let authorizationURL = components.url,
              NSWorkspace.shared.open(authorizationURL) else {
            throw GoogleOAuthError.cannotOpenBrowser
        }

        let timeout = DispatchWorkItem { [weak callbackServer] in
            callbackServer?.failCallback(GoogleOAuthError.timedOut)
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 180, execute: timeout)
        defer { timeout.cancel() }

        let callback = try await callbackServer.waitForCallback()
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var values: [String: String] = [:]
        for item in items { values[item.name] = item.value ?? "" }
        guard values["state"] == state else { throw GoogleOAuthError.invalidState }
        if let error = values["error"], !error.isEmpty {
            throw error == "access_denied" ? GoogleOAuthError.cancelled : GoogleOAuthError.provider(error)
        }
        guard let code = values["code"], !code.isEmpty else { throw GoogleOAuthError.missingCode }
        return try await exchangeCode(
            code, clientID: clientID, verifier: verifier, redirectURI: redirectURI)
    }

    private func exchangeCode(
        _ code: String,
        clientID: String,
        verifier: String,
        redirectURI: String
    ) async throws -> String {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncoded([
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI,
        ]).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GoogleOAuthError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = try? JSONDecoder().decode(GoogleTokenError.self, from: data)
            throw GoogleOAuthError.provider(body?.errorDescription ?? body?.error ?? "token_exchange_failed")
        }
        let token = try JSONDecoder().decode(GoogleTokenResponse.self, from: data)
        guard !token.idToken.isEmpty else { throw GoogleOAuthError.invalidResponse }
        return token.idToken
    }

    private func randomURLSafe(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, byteCount, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw GoogleOAuthError.randomFailure
        }
        return base64URL(Data(bytes))
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func formEncoded(_ values: [String: String]) -> String {
        var components = URLComponents()
        components.queryItems = values.sorted(by: { $0.key < $1.key })
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.percentEncodedQuery ?? ""
    }
}

private struct GoogleTokenResponse: Decodable {
    let idToken: String
    enum CodingKeys: String, CodingKey { case idToken = "id_token" }
}

private struct GoogleTokenError: Decodable {
    let error: String?
    let errorDescription: String?
    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

enum GoogleOAuthError: LocalizedError {
    case cannotOpenBrowser
    case cancelled
    case invalidState
    case missingCode
    case invalidResponse
    case randomFailure
    case timedOut
    case provider(String)

    var errorDescription: String? {
        switch self {
        case .cannotOpenBrowser: return "无法打开 Google 登录页面"
        case .cancelled: return "已取消 Google 登录"
        case .invalidState: return "登录回调校验失败，请重试"
        case .missingCode, .invalidResponse: return "Google 登录返回的数据不完整"
        case .randomFailure: return "无法创建安全登录请求"
        case .timedOut: return "Google 登录已超时，请重试"
        case .provider: return "Google 登录失败，请重试"
        }
    }
}

private final class LoopbackCallbackServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "macpulse.oauth.loopback")
    private let lock = NSLock()
    private var readyContinuation: CheckedContinuation<UInt16, Swift.Error>?
    private var callbackContinuation: CheckedContinuation<URL, Swift.Error>?
    private var pendingCallback: Result<URL, Swift.Error>?

    init() throws {
        let parameters = NWParameters.tcp
        parameters.acceptLocalOnly = true
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters, on: .any)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                guard let port = self.listener.port else {
                    self.finishReady(.failure(GoogleOAuthError.invalidResponse)); return
                }
                self.finishReady(.success(port.rawValue))
            case .failed(let error):
                self.finishReady(.failure(error))
                self.finishCallback(.failure(error))
            case .cancelled:
                self.finishReady(.failure(CancellationError()))
            default: break
            }
        }
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            readyContinuation = continuation
            lock.unlock()
            listener.start(queue: queue)
        }
    }

    func waitForCallback() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let pendingCallback {
                self.pendingCallback = nil
                lock.unlock()
                continuation.resume(with: pendingCallback)
            } else {
                callbackContinuation = continuation
                lock.unlock()
            }
        }
    }

    func failCallback(_ error: Swift.Error) {
        finishCallback(.failure(error))
        listener.cancel()
    }

    func cancel() {
        listener.cancel()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(from: connection, buffer: Data())
    }

    private func receive(from connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            var next = buffer
            if let data { next.append(data) }
            if next.range(of: Data("\r\n\r\n".utf8)) != nil {
                self.process(next, connection: connection)
            } else if next.count >= 16_384 || complete || error != nil {
                self.respond(status: "400 Bad Request", body: "请求无效", connection: connection)
            } else {
                self.receive(from: connection, buffer: next)
            }
        }
    }

    private func process(_ data: Data, connection: NWConnection) {
        guard let request = String(data: data, encoding: .utf8),
              let first = request.components(separatedBy: "\r\n").first else {
            respond(status: "400 Bad Request", body: "请求无效", connection: connection); return
        }
        let parts = first.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2, parts[0] == "GET",
              let url = URL(string: "http://127.0.0.1" + String(parts[1])),
              url.path == "/oauth2redirect" else {
            respond(status: "404 Not Found", body: "页面不存在", connection: connection); return
        }
        let html = """
        <!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width">
        <title>MacPulse 登录完成</title>
        <style>body{font:16px -apple-system;margin:0;display:grid;place-items:center;min-height:100vh;background:#071014;color:#e8fbff}main{max-width:420px;padding:36px;text-align:center}h1{color:#58e4ef}p{line-height:1.7;color:#a9c4c9}</style>
        <main><h1>登录已完成</h1><p>可以关闭这个页面，返回 MacPulse。</p></main>
        <script>setTimeout(()=>window.close(),900)</script>
        """
        respond(status: "200 OK", body: html, contentType: "text/html; charset=utf-8", connection: connection)
        finishCallback(.success(url))
    }

    private func respond(
        status: String,
        body: String,
        contentType: String = "text/plain; charset=utf-8",
        connection: NWConnection
    ) {
        let payload = Data(body.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(payload.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        var response = Data(head.utf8)
        response.append(payload)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func finishReady(_ result: Result<UInt16, Swift.Error>) {
        lock.lock()
        let continuation = readyContinuation
        readyContinuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }

    private func finishCallback(_ result: Result<URL, Swift.Error>) {
        lock.lock()
        if let continuation = callbackContinuation {
            callbackContinuation = nil
            lock.unlock()
            continuation.resume(with: result)
        } else {
            if pendingCallback == nil { pendingCallback = result }
            lock.unlock()
        }
    }
}
