import Foundation

/// Talks to the Supabase project configured in Info.plist (FMFBackendURL / FMFBackendKey).
enum Backend {
    static let baseURL: URL? = {
        guard let s = (Bundle.main.object(forInfoDictionaryKey: "FMFBackendURL") as? String)?.nilIfBlank else { return nil }
        return URL(string: s.hasSuffix("/") ? s : s + "/")
    }()
    static let apiKey: String? = (Bundle.main.object(forInfoDictionaryKey: "FMFBackendKey") as? String)?.nilIfBlank

    static var isConfigured: Bool { baseURL != nil && apiKey != nil }

    @discardableResult
    static func send(_ path: String, method: String = "POST", body: Any?, token: String? = nil,
                     headers: [String: String] = [:]) async throws -> Data {
        guard let base = baseURL, let key = apiKey, let url = URL(string: path, relativeTo: base) else {
            throw FMFError("Sign-in isn't available right now.")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue(key, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token ?? key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }

        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: req) }
        catch { throw FMFError("Couldn't reach the server. Check your internet connection.") }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw FMFError(errorMessage(data, status: status)) }
        return data
    }

    private static func errorMessage(_ data: Data, status: Int) -> String {
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let raw = (obj?["msg"] ?? obj?["error_description"] ?? obj?["message"]) as? String
        if status == 429 { return "Too many attempts. Please wait a minute and try again." }
        if let raw, raw.lowercased().contains("expired") || raw.lowercased().contains("invalid") {
            return "That code is incorrect or has expired."
        }
        return raw ?? "Something went wrong (error \(status))."
    }
}

struct AuthSession: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: String
    var email: String
}

@MainActor
final class Account: ObservableObject {
    @Published private(set) var session: AuthSession?
    @Published private(set) var localEmail: String?
    @Published private(set) var acceptedTermsVersion: String?
    @Published private(set) var acceptedTermsAt: Date?

    private let defaults = UserDefaults.standard
    private var sessionFile: URL { Paths.support.appendingPathComponent("session.json") }
    private var pendingFile: URL { Paths.support.appendingPathComponent("pending-submissions.json") }

    init() {
        acceptedTermsVersion = defaults.string(forKey: "termsVersion")
        acceptedTermsAt = defaults.object(forKey: "termsAcceptedAt") as? Date
        localEmail = defaults.string(forKey: "localEmail")
        if let data = try? Data(contentsOf: sessionFile) {
            session = try? JSON.decoder.decode(AuthSession.self, from: data)
        }
    }

    var hasAcceptedTerms: Bool { acceptedTermsVersion == Legal.version }
    var isSignedIn: Bool { Backend.isConfigured ? session != nil : localEmail != nil }
    var email: String? { session?.email ?? localEmail }

    func acceptTerms() {
        let now = Date()
        acceptedTermsVersion = Legal.version
        acceptedTermsAt = now
        defaults.set(Legal.version, forKey: "termsVersion")
        defaults.set(now, forKey: "termsAcceptedAt")
    }

    // MARK: Sign in with a one-time email code

    func sendCode(to email: String) async throws {
        guard Backend.isConfigured else { return }
        try await Backend.send("auth/v1/otp", body: ["email": email, "create_user": true])
    }

    func verify(email: String, code: String) async throws {
        guard Backend.isConfigured else {
            localEmail = email
            defaults.set(email, forKey: "localEmail")
            return
        }
        let data = try await Backend.send("auth/v1/verify", body: ["type": "email", "email": email, "token": code])
        let s = try Self.parseSession(data)
        store(s)
        await recordTermsAcceptance()
        await flushPending()
    }

    func signOut() {
        session = nil
        localEmail = nil
        try? FileManager.default.removeItem(at: sessionFile)
        defaults.removeObject(forKey: "localEmail")
    }

    private func store(_ s: AuthSession) {
        session = s
        if let data = try? JSON.encoder.encode(s) {
            try? data.write(to: sessionFile, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sessionFile.path)
        }
    }

    private static func parseSession(_ data: Data) throws -> AuthSession {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = obj["access_token"] as? String,
              let refresh = obj["refresh_token"] as? String,
              let user = obj["user"] as? [String: Any],
              let id = user["id"] as? String else { throw FMFError("Unexpected response from the server.") }
        let expiresIn = (obj["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        return AuthSession(accessToken: access, refreshToken: refresh,
                           expiresAt: Date().addingTimeInterval(expiresIn),
                           userID: id, email: (user["email"] as? String) ?? "")
    }

    func validAccessToken() async throws -> String {
        guard let s = session else { throw FMFError("Not signed in.") }
        if s.expiresAt.timeIntervalSinceNow > 120 { return s.accessToken }
        let data = try await Backend.send("auth/v1/token?grant_type=refresh_token", body: ["refresh_token": s.refreshToken])
        let fresh = try Self.parseSession(data)
        store(fresh)
        return fresh.accessToken
    }

    // MARK: Records

    private func recordTermsAcceptance() async {
        guard let s = session, let token = try? await validAccessToken() else { return }
        let body: [String: Any] = [
            "id": s.userID,
            "email": s.email,
            "terms_version": acceptedTermsVersion ?? Legal.version,
            "terms_accepted_at": ISO8601DateFormatter().string(from: acceptedTermsAt ?? Date()),
            "app_version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev",
        ]
        try? await Backend.send("rest/v1/profiles?on_conflict=id", body: body, token: token,
                                headers: ["Prefer": "resolution=merge-duplicates,return=minimal"])
    }

    /// Every link submitted for download is recorded, as described in the Terms.
    func logSubmission(url: String, format: AudioFormat, title: String, trackCount: Int) {
        guard Backend.isConfigured else { return }
        let row: [String: Any] = [
            "url": url,
            "format": format.rawValue,
            "title": title,
            "track_count": trackCount,
            "email": email ?? "",
            "submitted_at": ISO8601DateFormatter().string(from: Date()),
        ]
        Task {
            var queue = loadPending()
            queue.append(row)
            savePending(queue)
            await flushPending()
        }
    }

    private func flushPending() async {
        var queue = loadPending()
        guard !queue.isEmpty, let token = try? await validAccessToken() else { return }
        while let row = queue.first {
            do {
                try await Backend.send("rest/v1/submissions", body: row, token: token, headers: ["Prefer": "return=minimal"])
                queue.removeFirst()
                savePending(queue)
            } catch { break }
        }
    }

    private func loadPending() -> [[String: Any]] {
        guard let data = try? Data(contentsOf: pendingFile) else { return [] }
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    private func savePending(_ rows: [[String: Any]]) {
        if let data = try? JSONSerialization.data(withJSONObject: rows) { try? data.write(to: pendingFile, options: .atomic) }
    }
}
