// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CryptoKit
import Security

enum AccountError: LocalizedError, Equatable {
    case configuration(String)
    case signedOut
    case sessionChanged
    case consentRequired
    case invalidCallback
    case invalidValue(String)
    case keychain(Int32)
    case invalidResponse
    case responseTooLarge
    case authenticationCancelled
    case authenticationUnavailable
    case oauth(String)
    case api(Int, String)

    var errorDescription: String? {
        switch self {
        case .configuration(let reason): return reason
        case .signedOut: return "Bitte zuerst unter „Du“ mit Google verbinden."
        case .sessionChanged: return "Die Google-Verbindung wurde geändert. Bitte die aktuellen Daten prüfen und die Aktion erneut auswählen."
        case .consentRequired: return "Bitte die zusätzliche Google-Freigabe für Interaktionen bestätigen."
        case .invalidCallback: return "Die Google-Antwort konnte nicht sicher zugeordnet werden. Bitte die Anmeldung erneut starten."
        case .invalidValue(let reason): return reason
        case .keychain: return "Die Zugangsdaten konnten nicht sicher im Schlüsselbund gespeichert oder entfernt werden."
        case .invalidResponse: return "Google hat keine gültige Antwort geliefert."
        case .responseTooLarge: return "Die Serverantwort überschreitet die erlaubte Größe."
        case .authenticationCancelled: return "Google-Freigabe abgebrochen."
        case .authenticationUnavailable: return "Der sichere Google-Anmeldedialog konnte nicht geöffnet werden."
        case .oauth(let reason):
            if reason == "invalid_grant" { return "Die Google-Freigabe ist abgelaufen oder wurde widerrufen. Bitte erneut anmelden." }
            if reason == "access_denied" { return "Die angeforderte Google-Freigabe wurde nicht erteilt." }
            return "Google hat die Anmeldung abgelehnt. Bitte OAuth-Konfiguration und Testnutzer-Freigabe prüfen."
        case .api(let code, let reason):
            if ["quotaExceeded", "dailyLimitExceeded"].contains(reason) { return "Das YouTube-API-Kontingent ist ausgeschöpft. Bitte später erneut versuchen." }
            if ["accessNotConfigured", "serviceDisabled"].contains(reason) { return "Die YouTube Data API ist im Google-Cloud-Projekt noch nicht aktiviert." }
            if reason == "commentsDisabled" { return "Kommentare sind für dieses Video deaktiviert." }
            if code == 401 { return "Die Google-Freigabe ist abgelaufen. Bitte erneut anmelden und die Aktion bewusst wiederholen." }
            if code == 403 { return "YouTube hat diese Aktion für das Konto oder Video abgelehnt." }
            if code == 429 { return "YouTube begrenzt die Anfragen. Bitte später erneut versuchen." }
            return "YouTube konnte die Anfrage nicht bestätigen (HTTP \(code))."
        }
    }
}

struct AccountSessionRevision: Equatable, Sendable {
    private(set) var value: UInt64 = 0
    mutating func advance() { value &+= 1 }
    func check(_ expected: UInt64) throws {
        guard expected == value else { throw AccountError.sessionChanged }
    }
}

enum AccountScopes {
    static let read = "https://www.googleapis.com/auth/youtube.readonly"
    static let write = "https://www.googleapis.com/auth/youtube.force-ssl"
    static func canRead(_ scopes: Set<String>) -> Bool { scopes.contains(read) || scopes.contains(write) }
}

struct GoogleOAuthConfiguration: Sendable, Equatable {
    let clientID: String
    let redirectURI: URL
    var callbackScheme: String { redirectURI.scheme ?? "" }

    init(clientID: String, redirectURI: String, registeredSchemes: [String]) throws {
        let client = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard client.range(of: #"^[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$"#, options: .regularExpression) != nil,
              !client.contains("YOUR_"), !client.contains("$(") else {
            throw AccountError.configuration("Die Google-Anmeldung ist noch nicht eingerichtet. GoogleOAuthClientID muss die echte iOS-OAuth-Client-ID enthalten.")
        }
        let scheme = client.split(separator: ".").reversed().joined(separator: ".")
        guard let uri = URL(string: redirectURI),
              uri.scheme == scheme, uri.host == nil, uri.user == nil, uri.password == nil,
              uri.query == nil, uri.fragment == nil,
              ["/oauthredirect", "/oauth2redirect"].contains(uri.path),
              registeredSchemes.contains(scheme) else {
            throw AccountError.configuration("GoogleOAuthRedirectURI und das URL-Scheme fehlen oder stimmen nicht überein. Verwende das umgekehrte iOS-Client-ID-Scheme mit /oauthredirect und registriere es in CFBundleURLTypes.")
        }
        self.clientID = client
        self.redirectURI = uri
    }

    static func load(bundle: Bundle = .main) throws -> GoogleOAuthConfiguration {
        let types = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        return try GoogleOAuthConfiguration(
            clientID: bundle.object(forInfoDictionaryKey: "GoogleOAuthClientID") as? String ?? "",
            redirectURI: bundle.object(forInfoDictionaryKey: "GoogleOAuthRedirectURI") as? String ?? "",
            registeredSchemes: schemes
        )
    }
}

struct OAuthPKCE: Sendable {
    let verifier: String
    let challenge: String
    let state: String

    init() throws {
        verifier = try Self.random()
        challenge = Self.challenge(for: verifier)
        state = try Self.random()
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard result == errSecSuccess else { throw AccountError.authenticationUnavailable }
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func authorizationCode(callback: URL, redirect: URL, expectedState: String) throws -> String {
        guard callback.scheme == redirect.scheme, callback.host == redirect.host,
              callback.path == redirect.path, callback.user == nil, callback.password == nil,
              callback.port == nil, callback.fragment == nil,
              let components = URLComponents(url: callback, resolvingAgainstBaseURL: false) else {
            throw AccountError.invalidCallback
        }
        let items = components.queryItems ?? []
        let states = items.filter { $0.name == "state" }
        guard states.count == 1, states[0].value == expectedState else { throw AccountError.invalidCallback }
        if items.contains(where: { $0.name == "error" }) { throw AccountError.oauth("access_denied") }
        let codes = items.filter { $0.name == "code" }
        guard codes.count == 1, let code = codes[0].value, !code.isEmpty, code.utf8.count <= 4096 else {
            throw AccountError.invalidCallback
        }
        return code
    }
}

enum YouTubeActionPolicy {
    static func channelID(_ value: String) throws -> String {
        guard value.range(of: #"^[A-Za-z0-9_-]{1,128}$"#, options: .regularExpression) != nil else {
            throw AccountError.invalidValue("Ungültige Kanal-ID.")
        }
        return value
    }
    static func videoID(_ value: String) throws -> String {
        guard value.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil else {
            throw AccountError.invalidValue("Ungültige Video-ID.")
        }
        return value
    }

    static func resourceID(_ value: String) throws -> String {
        guard !value.isEmpty, value.utf8.count <= 256,
              value.unicodeScalars.allSatisfy({ !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.controlCharacters.contains($0) }) else {
            throw AccountError.invalidValue("Ungültige YouTube-ID.")
        }
        return value
    }

    static func playlistID(_ value: String) throws -> String {
        let result = try resourceID(value)
        guard !["WL", "HL"].contains(value) else {
            throw AccountError.invalidValue("YouTube gibt „Später ansehen“ und den YouTube-Verlauf nicht über diese API frei. Bitte eine eigene Playlist wählen.")
        }
        return result
    }

    static func comment(_ value: String) throws -> String {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AccountError.invalidValue("Bitte einen Kommentar eingeben.") }
        guard text.utf16.count <= 5000 else { throw AccountError.invalidValue("Kommentare dürfen höchstens 5.000 Zeichen enthalten.") }
        return text
    }

    static func mayRetry(method: String, status: Int, attempts: Int) -> Bool {
        method == "GET" && status == 401 && attempts == 0
    }

    static func pageToken(_ token: String?) throws -> String? {
        guard let token, !token.isEmpty else { return nil }
        guard token.utf8.count <= 4096, !token.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw AccountError.invalidResponse
        }
        return token
    }
}

enum YouTubeActionPayloads {
    static func subscription(channelID: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["snippet": ["resourceId": ["kind": "youtube#channel", "channelId": YouTubeActionPolicy.channelID(channelID)]]])
    }
    static func comment(channelID: String, videoID: String, text: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["snippet": ["channelId": YouTubeActionPolicy.channelID(channelID), "videoId": YouTubeActionPolicy.videoID(videoID), "topLevelComment": ["snippet": ["textOriginal": YouTubeActionPolicy.comment(text)]]]])
    }
    static func reply(parentID: String, text: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["snippet": ["parentId": YouTubeActionPolicy.resourceID(parentID), "textOriginal": YouTubeActionPolicy.comment(text)]])
    }
    static func playlistItem(playlistID: String, videoID: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["snippet": ["playlistId": YouTubeActionPolicy.playlistID(playlistID), "resourceId": ["kind": "youtube#video", "videoId": YouTubeActionPolicy.videoID(videoID)]]])
    }
}
