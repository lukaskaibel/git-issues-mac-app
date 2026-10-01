import Foundation
import Security

/// Stores the GitHub token in the login keychain.
public enum KeychainTokenStore {
    private static let service = "com.lukaskbl.GitIssues.github-token"
    private static let account = "github.com"

    public static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public static func save(_ token: String) -> Bool {
        delete()
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(token.utf8),
        ]
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    public static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Reads the token of an existing GitHub CLI login. Meant for development builds.
public enum GitHubCLI {
    public static func executableURL() -> URL? {
        ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    public static var isAvailable: Bool { executableURL() != nil }

    public static func token() async throws -> String {
        guard let url = executableURL() else { throw APIError.noToken }
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = url
            process.arguments = ["auth", "token"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            process.terminationHandler = { process in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if process.terminationStatus == 0, !token.isEmpty {
                    continuation.resume(returning: token)
                } else {
                    continuation.resume(throwing: APIError.noToken)
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: APIError.noToken)
            }
        }
    }
}

/// The app's single source of truth for the GitHub token.
public actor AuthStore: TokenSource {
    public enum Method: String, Sendable {
        case keychain
        case githubCLI
    }

    private static let methodKey = "auth.method"
    private var cached: String?

    public init() {}

    public nonisolated var method: Method? {
        UserDefaults.standard.string(forKey: Self.methodKey).flatMap(Method.init)
    }

    public nonisolated var isSignedIn: Bool { method != nil }

    public func token() async throws -> String {
        if let cached { return cached }
        let token: String
        switch method {
        case .keychain:
            guard let stored = KeychainTokenStore.read() else { throw APIError.noToken }
            token = stored
        case .githubCLI:
            token = try await GitHubCLI.token()
        case nil:
            throw APIError.noToken
        }
        cached = token
        return token
    }

    public func signIn(token: String) {
        KeychainTokenStore.save(token)
        UserDefaults.standard.set(Method.keychain.rawValue, forKey: Self.methodKey)
        cached = token
    }

    public func signInWithGitHubCLI() async throws {
        cached = try await GitHubCLI.token()
        UserDefaults.standard.set(Method.githubCLI.rawValue, forKey: Self.methodKey)
    }

    public func signOut() {
        KeychainTokenStore.delete()
        UserDefaults.standard.removeObject(forKey: Self.methodKey)
        cached = nil
    }

    /// Drops the in-memory copy so the next request re-reads it (after a 401, for instance).
    public func invalidateCache() {
        cached = nil
    }
}

/// GitHub's OAuth device flow: the user enters a short code on github.com and the app polls for the token.
public struct DeviceFlow: Sendable {
    public struct Code: Sendable {
        public var deviceCode: String
        public var userCode: String
        public var verificationURL: URL
        public var interval: TimeInterval
        public var expiresAt: Date
    }

    public enum FlowError: Error, LocalizedError {
        case notConfigured
        case expired
        case denied
        case failed(String)

        public var errorDescription: String? {
            switch self {
            case .notConfigured: "This build has no GitHub OAuth client ID."
            case .expired: "The code expired. Start again."
            case .denied: "Access was denied on GitHub."
            case .failed(let detail): detail
            }
        }
    }

    public let clientID: String
    public static let scopes = "repo project read:org"

    public init(clientID: String) {
        self.clientID = clientID
    }

    /// The client ID comes from the app's Info.plist key `GitHubClientID`.
    public static var configuredClientID: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "GitHubClientID") as? String
        return (value?.isEmpty == false) ? value : nil
    }

    public func start() async throws -> Code {
        guard !clientID.isEmpty else { throw FlowError.notConfigured }
        let json = try await post("https://github.com/login/device/code", ["client_id": clientID, "scope": Self.scopes])
        guard let deviceCode = json["device_code"] as? String,
              let userCode = json["user_code"] as? String,
              let uri = (json["verification_uri"] as? String).flatMap(URL.init(string:)) else {
            throw FlowError.failed((json["error_description"] as? String) ?? "GitHub did not return a code.")
        }
        let interval = (json["interval"] as? Double) ?? 5
        let expires = (json["expires_in"] as? Double) ?? 900
        return Code(deviceCode: deviceCode, userCode: userCode, verificationURL: uri, interval: interval, expiresAt: Date().addingTimeInterval(expires))
    }

    /// Polls until the user approves on github.com, then returns the access token.
    public func waitForToken(_ code: Code) async throws -> String {
        var interval = code.interval
        while Date() < code.expiresAt {
            try await Task.sleep(for: .seconds(interval))
            let json = try await post("https://github.com/login/oauth/access_token", [
                "client_id": clientID,
                "device_code": code.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ])
            if let token = json["access_token"] as? String { return token }
            switch json["error"] as? String {
            case "authorization_pending": continue
            case "slow_down": interval += 5
            case "expired_token": throw FlowError.expired
            case "access_denied": throw FlowError.denied
            default: throw FlowError.failed((json["error_description"] as? String) ?? "Sign-in failed.")
            }
        }
        throw FlowError.expired
    }

    private func post(_ url: String, _ form: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
