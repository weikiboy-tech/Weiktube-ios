// SPDX-License-Identifier: GPL-3.0-only
import AuthenticationServices
import Foundation
import Security
import UIKit

struct GoogleCredential: Codable, Sendable {
    let clientID: String
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date
    let scopes: Set<String>
}

struct GoogleKeychainStore<Value:Codable> {
    let account:String
    init(account:String="youtube-account") {self.account=account}
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "com.weiktube.ios") + ".google-oauth",
         kSecAttrAccount as String: account]
    }

    func read() throws -> Value? {
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(search as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw AccountError.keychain(status) }
        guard data.count<=65_536 else{throw AccountError.invalidResponse}
        return try JSONDecoder().decode(Value.self, from: data)
    }

    func write(_ credential: Value) throws {
        let data = try JSONEncoder().encode(credential)
        guard data.count<=65_536 else{throw AccountError.invalidResponse}
        let updates: [String: Any] = [kSecValueData as String: data,
                                     kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
        if status == errSecItemNotFound {
            let inserted = SecItemAdd(query.merging(updates, uniquingKeysWith: { _, new in new }) as CFDictionary, nil)
            guard inserted == errSecSuccess else { throw AccountError.keychain(inserted) }
        } else if status != errSecSuccess { throw AccountError.keychain(status) }
    }

    func remove() throws {
        let result = SecItemDelete(query as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw AccountError.keychain(result) }
    }
}

struct GooglePendingRevocation:Codable,Sendable {
    let id:UUID
    let token:String
    let createdAt:Date
    var attempts:Int
    static let maximumAttempts=5
    func valid(at date:Date) -> Bool {
        !token.isEmpty && token.utf8.count<=16_384 && (0...Self.maximumAttempts).contains(attempts) &&
        createdAt.timeIntervalSince1970.isFinite && createdAt<=date.addingTimeInterval(60) && date.timeIntervalSince(createdAt)<=7*24*60*60
    }
}

/// Authorization code + S256 PKCE through Apple's system authentication session.
/// Google documents the reversed iOS client-ID scheme; no WebView or cookies are used here.
@MainActor
final class GoogleOAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let configuration: GoogleOAuthConfiguration?
    private let keychain = GoogleKeychainStore<GoogleCredential>()
    private let revocationKeychain=GoogleKeychainStore<GooglePendingRevocation>(account:"youtube-pending-revocation")
    private let transport = YouTubeHTTPTransport.shared
    private var credential: GoogleCredential?
    private var pendingRevocation:GooglePendingRevocation?
    private var session: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<URL, Error>?
    private var authenticationID: UUID?
    private weak var presentationWindow: UIWindow?
    private var refreshTask: (id: UUID, task: Task<GoogleCredential, Error>)?
    private(set) var revision = AccountSessionRevision()
    private(set) var configurationIssue: String?
    private(set) var restoreIssue: String?
    private(set) var revocationWasConfirmed=false

    var hasCredential: Bool { credential != nil }
    var canWrite: Bool { credential?.scopes.contains(AccountScopes.write) == true }
    var hasPendingRevocation:Bool {pendingRevocation != nil}
    var revocationAttemptsRemaining:Int {max(0,GooglePendingRevocation.maximumAttempts-(pendingRevocation?.attempts ?? GooglePendingRevocation.maximumAttempts))}
    var canRetryRevocation:Bool {pendingRevocation?.valid(at:Date()) == true && revocationAttemptsRemaining>0}

    override init() {
        do { configuration = try GoogleOAuthConfiguration.load() }
        catch { configuration = nil; configurationIssue = error.localizedDescription }
        super.init()
        var suppressCredentialRestore=false
        do {
            if let saved=try revocationKeychain.read() {
                suppressCredentialRestore=true
                if saved.valid(at:Date()) {pendingRevocation=saved}
                // Remove the old main token before expiring its retry record.
                try keychain.remove()
                if pendingRevocation==nil {
                    try revocationKeychain.remove()
                    restoreIssue="Der ausstehende Google-Widerruf ist nicht mehr lokal wiederholbar. Prüfe die Freigabe unter myaccount.google.com/connections."
                }
            }
        } catch {
            suppressCredentialRestore=true
            restoreIssue="Der gespeicherte Widerruf konnte nicht geöffnet werden. Prüfe die Freigabe unter myaccount.google.com/connections."
        }
        guard !suppressCredentialRestore else{return}
        guard let configuration else { return }
        do {
            if let saved = try keychain.read() {
                if saved.clientID == configuration.clientID && AccountScopes.canRead(saved.scopes) {
                    credential = saved
                } else { try keychain.remove() }
            }
        } catch { restoreIssue = "Die gespeicherte Google-Verbindung konnte nicht geöffnet werden. Bitte erneut anmelden." }
    }

    /// Invalidates every in-flight read, write intent, and refresh before changing credentials.
    @discardableResult
    func reset() throws -> String? {
        let revocationToken = credential?.refreshToken ?? credential?.accessToken
        invalidatePendingOperations()
        credential = nil
        try keychain.remove()
        return revocationToken
    }

    /// Scope-upgrade consent invalidates old work but retains the existing read grant until success.
    func invalidatePendingOperations() {
        revision.advance()
        refreshTask?.task.cancel(); refreshTask = nil
        cancelAuthentication()
    }

    func check(_ expected: UInt64) throws {
        try Task.checkCancellation()
        try revision.check(expected)
    }

    func signIn(scopes: Set<String>, expected: UInt64) async throws {
        guard pendingRevocation==nil else {throw AccountError.invalidValue("Schließe zuerst den ausstehenden Google-Widerruf ab oder verwirf dessen lokale Wiederholungsdaten.")}
        guard let configuration else { throw AccountError.configuration(configurationIssue ?? "Google-Anmeldung nicht eingerichtet.") }
        try check(expected)
        let pkce = try OAuthPKCE()
        var url = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        url.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.sorted().joined(separator: " ")),
            URLQueryItem(name: "state", value: pkce.state),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "select_account consent")
        ]
        let callback = try await authenticate(url: url.url!, scheme: configuration.callbackScheme)
        try check(expected)
        let code = try OAuthPKCE.authorizationCode(callback: callback, redirect: configuration.redirectURI, expectedState: pkce.state)
        let result = try await tokenRequest([
            "client_id": configuration.clientID, "redirect_uri": configuration.redirectURI.absoluteString,
            "grant_type": "authorization_code", "code": code, "code_verifier": pkce.verifier
        ], previous: nil, requestedScopes: scopes)
        try check(expected)
        guard AccountScopes.canRead(result.scopes) else { throw AccountError.oauth("access_denied") }
        try keychain.write(result)
        credential = result
    }

    func accessToken(expected: UInt64, forceRefreshFor rejectedToken: String? = nil) async throws -> String {
        try check(expected)
        guard let current = credential else { throw AccountError.signedOut }
        if current.expiresAt.timeIntervalSinceNow > 60 && (rejectedToken == nil || rejectedToken != current.accessToken) {
            return current.accessToken
        }
        if let existing = refreshTask {
            let result = try await existing.task.value
            try check(expected)
            return result.accessToken
        }
        guard let refresh = current.refreshToken, !refresh.isEmpty else { throw AccountError.oauth("invalid_grant") }
        let id = UUID()
        let task = Task { @MainActor [self] () async throws -> GoogleCredential in
            let updated = try await tokenRequest([
                "client_id": current.clientID, "grant_type": "refresh_token", "refresh_token": refresh
            ], previous: current, requestedScopes: current.scopes)
            try check(expected)
            try keychain.write(updated)
            credential = updated
            return updated
        }
        refreshTask = (id, task)
        defer { if refreshTask?.id == id { refreshTask = nil } }
        let updated = try await task.value
        try check(expected)
        return updated.accessToken
    }

    func requireWrite(expected: UInt64) throws {
        try check(expected)
        guard canWrite else { throw AccountError.consentRequired }
    }

    /// Protect the retry token before deleting the main local credential. No request occurs here.
    func prepareRevocation() throws {
        revocationWasConfirmed=false
        if let token=credential?.refreshToken ?? credential?.accessToken {
            let pending=GooglePendingRevocation(id:UUID(),token:token,createdAt:Date(),attempts:0)
            guard pending.valid(at:Date()) else{throw AccountError.invalidResponse}
            try revocationKeychain.write(pending)
            pendingRevocation=pending
        }
        _=try reset()
    }

    /// Exactly one explicit attempt. This method never schedules automatic retry.
    func retryPendingRevocation() async throws {
        revocationWasConfirmed=false
        guard var pending=pendingRevocation,pending.valid(at:Date()),pending.attempts<GooglePendingRevocation.maximumAttempts else {
            throw AccountError.invalidValue("Der lokale Widerruf kann nicht erneut versucht werden. Entferne die Freigabe unter myaccount.google.com/connections.")
        }
        pending.attempts+=1
        try revocationKeychain.write(pending)
        pendingRevocation=pending
        try await revoke(token:pending.token)
        revocationWasConfirmed=true
        guard pendingRevocation?.id==pending.id else{return}
        try keychain.remove()
        try revocationKeychain.remove()
        pendingRevocation=nil
    }

    func discardPendingRevocation() throws {
        guard pendingRevocation != nil else{return}
        // Do not allow a previously failed local deletion to resurrect the old sign-in.
        try keychain.remove()
        try revocationKeychain.remove()
        pendingRevocation=nil
    }

    func revoke(token: String) async throws {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = YouTubeHTTPTransport.formBody(["token": token])
        let (_, response) = try await transport.send(request, maximumBytes: 64 * 1024)
        guard (200..<300).contains(response.statusCode) else { throw AccountError.api(response.statusCode, "revocationFailed") }
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let token_type: String
        let expires_in: Double
        let refresh_token: String?
        let scope: String?
    }

    private func tokenRequest(_ form: [String: String], previous: GoogleCredential?, requestedScopes: Set<String>) async throws -> GoogleCredential {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = YouTubeHTTPTransport.formBody(form)
        let (data, response) = try await transport.send(request, maximumBytes: 64 * 1024)
        guard (200..<300).contains(response.statusCode) else {
            struct Failure: Decodable { let error: String }
            throw AccountError.oauth((try? JSONDecoder().decode(Failure.self, from: data).error) ?? "token_error")
        }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard token.token_type.lowercased() == "bearer", !token.access_token.isEmpty,
              token.access_token.utf8.count <= 16_384, token.expires_in.isFinite,
              token.expires_in > 0, token.expires_in <= 31_536_000 else { throw AccountError.invalidResponse }
        let scopes = token.scope.map { Set($0.split(separator: " ").map(String.init)) } ?? requestedScopes
        return GoogleCredential(clientID: form["client_id"]!, accessToken: token.access_token,
                                refreshToken: token.refresh_token ?? previous?.refreshToken,
                                expiresAt: Date().addingTimeInterval(token.expires_in), scopes: scopes)
    }

    private func authenticate(url: URL, scheme: String) async throws -> URL {
        guard continuation == nil else { throw AccountError.authenticationUnavailable }
        presentationWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }.flatMap(\.windows).first(where: \.isKeyWindow)
        guard presentationWindow != nil else { throw AccountError.authenticationUnavailable }
        let identifier=UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { pending in
                continuation = pending
                authenticationID = identifier
                let auth = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { [weak self] callback, error in
                    Task { @MainActor [weak self] in
                        guard self?.authenticationID == identifier else { return }
                        if let callback { self?.finish(.success(callback)) }
                        else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                            self?.finish(.failure(AccountError.authenticationCancelled))
                        } else { self?.finish(.failure(AccountError.authenticationUnavailable)) }
                    }
                }
                auth.presentationContextProvider = self
                // Browser-managed account selection. No access to that browser's cookies.
                auth.prefersEphemeralWebBrowserSession = false
                session = auth
                if !auth.start() { finish(.failure(AccountError.authenticationUnavailable)) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.authenticationID==identifier else{return}
                self?.cancelAuthentication()
            }
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard let pending = continuation else { return }
        continuation = nil
        authenticationID = nil
        session = nil
        presentationWindow = nil
        pending.resume(with: result)
    }

    private func cancelAuthentication() {
        let active = session
        finish(.failure(AccountError.authenticationCancelled))
        active?.cancel()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        presentationWindow ?? ASPresentationAnchor()
    }
}
