// SPDX-License-Identifier: GPL-3.0-only
import Combine
import Foundation

/// One injected account session for all native screens; never shares credentials with WebKit.
@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var isSignedIn = false
    @Published private(set) var isAuthenticating = false
    @Published private(set) var hasPendingRevocation=false
    @Published private(set) var revocationAttemptsRemaining=0
    @Published private(set) var sessionRevision: UInt64 = 0
    @Published private(set) var channels: [YouTubeChannel] = []
    @Published private(set) var subscriptions: [YouTubeSubscription] = []
    @Published private(set) var playlists: [YouTubePlaylist] = []
    @Published private(set) var feedVideos: [YouTubeVideo] = []
    @Published private(set) var accountLoading = false
    @Published private(set) var subscriptionsLoading = false
    @Published private(set) var playlistsLoading = false
    @Published private(set) var feedLoading = false
    @Published private(set) var hasMoreSubscriptions = false
    @Published private(set) var hasMorePlaylists = false
    @Published private(set) var hasMoreFeedChannels = false
    @Published private(set) var loadedFeedChannels = 0
    @Published private(set) var feedMessage: String?
    @Published private(set) var status = "Kontofunktionen verwenden eine separate Google-Freigabe."
    @Published var errorMessage: String?

    private let authorization: GoogleOAuthService
    let api: YouTubeAPI
    private var accountLoaded = false
    private var nextSubscriptions: String?
    private var nextPlaylists: String?
    private var feedChannels: [YouTubeSubscription] = []
    private var feedNextToken: String?
    private var feedProcessed: Set<String> = []
    private var feedUnavailable = 0
    private var feedCachedAt: Date?
    private var authOperation: UUID?

    var channel: YouTubeChannel? { channels.first }
    var configurationIssue: String? { authorization.configurationIssue }
    var hasInteractionPermission: Bool { isSignedIn && authorization.canWrite }
    var canRetryRevocation:Bool {authorization.canRetryRevocation && !isAuthenticating}

    init() {
        let service = GoogleOAuthService()
        authorization = service
        api = YouTubeAPI(authorization: service)
        isSignedIn = service.hasCredential
        hasPendingRevocation=service.hasPendingRevocation
        revocationAttemptsRemaining=service.revocationAttemptsRemaining
        errorMessage = service.restoreIssue
    }

    func checkSession(_ expected: UInt64) throws {
        guard isSignedIn, expected == sessionRevision else { throw AccountError.sessionChanged }
        try authorization.check(expected)
    }

    func signIn() async { await authorize(scopes: [AccountScopes.read]) }

    /// Explicit consent only. It never executes a pending like, comment, subscription, or playlist write.
    func authorizeInteractions() async { await authorize(scopes: [AccountScopes.read, AccountScopes.write],preservingReadGrant:true) }

    private func authorize(scopes: Set<String>,preservingReadGrant:Bool=false) async {
        guard !isAuthenticating else { return }
        guard !hasPendingRevocation else{errorMessage="Schließe zuerst den ausstehenden Google-Widerruf ab oder verwirf dessen lokale Wiederholungsdaten.";return}
        guard configurationIssue == nil else { errorMessage = configurationIssue; return }
        let operation = UUID()
        authOperation = operation
        isAuthenticating = true
        errorMessage = nil
        status = "Google-Freigabe wird geöffnet …"
        defer { if authOperation == operation { isAuthenticating = false; authOperation = nil } }
        do {
            if preservingReadGrant && authorization.hasCredential {
                authorization.invalidatePendingOperations()
                sessionRevision=authorization.revision.value
                accountLoading=false;subscriptionsLoading=false;playlistsLoading=false;feedLoading=false
            } else { _ = try invalidate() }
            let expected = sessionRevision
            try await authorization.signIn(scopes: scopes, expected: expected)
            try authorization.check(expected)
            guard authOperation == operation else { return }
            // The browser may have selected another account. Retire reads made during consent
            // before displaying data fetched with the newly committed credential.
            authorization.invalidatePendingOperations()
            clearAccountData()
            sessionRevision=authorization.revision.value
            isSignedIn = authorization.hasCredential
            status = hasInteractionPermission ? "Google-Freigabe für Lesen und Interaktionen aktiv." : "Google-Lesezugriff aktiv."
            if scopes.contains(AccountScopes.write) && !hasInteractionPermission {
                errorMessage = "Lesezugriff bleibt aktiv. Die zusätzliche Schreibfreigabe wurde nicht erteilt."
            }
            await refreshAccount()
        } catch {
            guard authOperation == operation else { return }
            isSignedIn=authorization.hasCredential
            errorMessage = error.localizedDescription
            status = isSignedIn ? "Die zusätzliche Freigabe wurde nicht abgeschlossen. Dein bisheriger Lesezugriff bleibt aktiv.":"Die Google-Anmeldung wurde nicht abgeschlossen."
        }
    }

    func signOut() async {
        authOperation = nil
        isAuthenticating = false
        do {
            _ = try invalidate()
            errorMessage = nil
            status = "Lokale Google-Verbindung gelöscht. Die Freigabe bei Google bleibt bestehen."
        } catch { errorMessage = error.localizedDescription }
    }

    func disconnect() async {
        guard !isAuthenticating else { return }
        let operation = UUID()
        authOperation = operation
        isAuthenticating = true
        defer { if authOperation == operation { isAuthenticating = false; authOperation = nil } }
        do {
            let hadGrant=authorization.hasCredential || authorization.hasPendingRevocation
            try authorization.prepareRevocation()
            syncDisconnectedSession()
            errorMessage = nil
            status = "Lokale Kontodaten gelöscht. Google-Freigabe wird widerrufen …"
            if authorization.hasPendingRevocation {try await authorization.retryPendingRevocation()}
            syncPendingRevocation()
            guard authOperation == operation else { return }
            status = hadGrant ? "Google-Freigabe widerrufen.":"Keine lokale Google-Verbindung vorhanden."
        } catch {
            guard authOperation == operation else { return }
            if !authorization.hasCredential {syncDisconnectedSession()}
            syncPendingRevocation()
            if authorization.revocationWasConfirmed {
                errorMessage="Google hat den Widerruf bestätigt. Die lokalen Wiederholungsdaten konnten noch nicht aus dem Schlüsselbund entfernt werden."
                status="Google-Freigabe widerrufen; lokale Bereinigung steht aus."
            } else {
                errorMessage = hasPendingRevocation ? "Google konnte den Widerruf nicht bestätigen. Du kannst ihn unten ausdrücklich erneut versuchen oder die Freigabe unter myaccount.google.com/connections entfernen.":error.localizedDescription
                status = isSignedIn ? "Der Widerruf konnte nicht sicher vorbereitet werden; die bisherige lokale Verbindung wurde erhalten.":"Lokale Sitzung beendet. Der Google-Widerruf ist noch nicht bestätigt."
            }
        }
    }

    func retryRevocation() async {
        guard !isAuthenticating,hasPendingRevocation else{return}
        let operation=UUID();authOperation=operation;isAuthenticating=true;errorMessage=nil
        defer {if authOperation==operation {isAuthenticating=false;authOperation=nil};syncPendingRevocation()}
        do {
            try await authorization.retryPendingRevocation()
            guard authOperation==operation else{return}
            status="Google-Freigabe widerrufen. Die geschützten Wiederholungsdaten wurden gelöscht."
        } catch {
            guard authOperation==operation else{return}
            errorMessage=error.localizedDescription
            status=authorization.revocationWasConfirmed ? "Google-Freigabe widerrufen; lokale Bereinigung steht aus.":"Google konnte den Widerruf noch nicht bestätigen. Es erfolgt kein automatischer weiterer Versuch."
        }
    }

    func discardRevocationRetry() {
        guard !isAuthenticating,hasPendingRevocation else{return}
        do {
            try authorization.discardPendingRevocation()
            syncPendingRevocation();errorMessage=nil
            status="Lokale Wiederholungsdaten gelöscht. Eine noch bestehende Freigabe kannst du bei Google entfernen."
        } catch {errorMessage=error.localizedDescription}
    }
    private func syncPendingRevocation() {
        hasPendingRevocation=authorization.hasPendingRevocation
        revocationAttemptsRemaining=authorization.revocationAttemptsRemaining
    }
    private func syncDisconnectedSession() {
        sessionRevision=authorization.revision.value
        isSignedIn=authorization.hasCredential
        clearAccountData();syncPendingRevocation()
    }

    @discardableResult
    private func invalidate() throws -> String? {
        defer {
            sessionRevision = authorization.revision.value
            isSignedIn = false
            clearAccountData()
        }
        return try authorization.reset()
    }
    private func clearAccountData() {
        channels=[];subscriptions=[];playlists=[];feedVideos=[]
        nextSubscriptions=nil;nextPlaylists=nil
        hasMoreSubscriptions=false;hasMorePlaylists=false
        accountLoaded=false;accountLoading=false;subscriptionsLoading=false;playlistsLoading=false
        clearFeed()
    }

    func loadIfNeeded() async {
        guard isSignedIn, !accountLoaded, !accountLoading else { return }
        await refreshAccount()
    }

    func refreshAccount() async {
        guard isSignedIn, !accountLoading else { return }
        let expected = sessionRevision
        accountLoading = true
        errorMessage = nil
        defer { if sessionRevision == expected { accountLoading = false } }
        do {
            async let own = api.ownChannels(expected: expected)
            async let subscriptionsPage = api.subscriptions(expected: expected)
            async let playlistsPage = api.playlists(expected: expected)
            let result = try await (own, subscriptionsPage, playlistsPage)
            try checkSession(expected)
            channels = result.0
            subscriptions = result.1.items
            nextSubscriptions = result.1.nextPageToken
            hasMoreSubscriptions = nextSubscriptions != nil
            playlists = result.2.items
            nextPlaylists = result.2.nextPageToken
            hasMorePlaylists = nextPlaylists != nil
            accountLoaded = true
            if channel == nil { status = "Google-Freigabe aktiv. Für dieses Konto wurde kein eigener YouTube-Kanal gefunden." }
        } catch { handle(error, expected: expected) }
    }

    func loadMoreSubscriptions() async {
        guard isSignedIn, !subscriptionsLoading, let token = nextSubscriptions else { return }
        let expected = sessionRevision
        subscriptionsLoading = true
        defer { if sessionRevision == expected { subscriptionsLoading = false } }
        do {
            let page = try await api.subscriptions(token: token, expected: expected)
            try checkSession(expected)
            subscriptions = unique(subscriptions + page.items)
            nextSubscriptions = page.nextPageToken
            hasMoreSubscriptions = nextSubscriptions != nil
        } catch { handle(error, expected: expected) }
    }

    func loadMorePlaylists() async {
        guard isSignedIn, !playlistsLoading, let token = nextPlaylists else { return }
        let expected = sessionRevision
        playlistsLoading = true
        defer { if sessionRevision == expected { playlistsLoading = false } }
        do {
            let page = try await api.playlists(token: token, expected: expected)
            try checkSession(expected)
            playlists = unique(playlists + page.items)
            nextPlaylists = page.nextPageToken
            hasMorePlaylists = nextPlaylists != nil
        } catch { handle(error, expected: expected) }
    }

    func loadFeedIfNeeded() async {
        guard feedCachedAt == nil || Date().timeIntervalSince(feedCachedAt!) >= 300 else { return }
        await loadFeed(reset: true)
    }

    func loadFeed(reset: Bool) async {
        guard isSignedIn, !feedLoading, reset || hasMoreFeedChannels else { return }
        let expected = sessionRevision
        feedLoading = true
        defer { if sessionRevision == expected { feedLoading = false } }
        do {
            var discovered = reset ? [] : feedChannels
            var next = reset ? nil : feedNextToken
            let processed = reset ? Set<String>() : feedProcessed
            var unavailable = reset ? 0 : feedUnavailable
            if reset || (discovered.filter { !processed.contains($0.channelID) }.count < 12 && next != nil) {
                let page = try await api.subscriptions(token: next, expected: expected)
                try checkSession(expected)
                discovered = unique(discovered + page.items)
                next = page.nextPageToken
            }
            let selection = Array(discovered.filter { !processed.contains($0.channelID) }.prefix(12))
            let batch = try await api.recentUploads(channelIDs: selection.map(\.channelID), expected: expected)
            try checkSession(expected)
            unavailable += batch.unavailable
            feedChannels = discovered
            feedNextToken = next
            feedProcessed = processed.union(selection.map(\.channelID))
            feedUnavailable = unavailable
            feedVideos = unique((reset ? [] : feedVideos) + batch.videos)
                .sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }
            loadedFeedChannels = max(0, feedProcessed.count - unavailable)
            hasMoreFeedChannels = next != nil || discovered.contains { !feedProcessed.contains($0.channelID) }
            if reset || feedCachedAt == nil { feedCachedAt = Date() }
            feedMessage = unavailable > 0 ? "\(unavailable) Kanäle sind momentan nicht abrufbar. Aktualisieren versucht sie erneut." : nil
        } catch {
            if sessionRevision == expected,!(error is CancellationError) { feedMessage = error.localizedDescription }
            handle(error, expected: expected)
        }
    }

    private func clearFeed() {
        feedChannels = []; feedNextToken = nil; feedProcessed = []; feedUnavailable = 0
        feedCachedAt = nil; feedLoading = false; hasMoreFeedChannels = false; loadedFeedChannels = 0; feedMessage = nil
    }

    func handle(_ error: Error, expected: UInt64) {
        guard expected == sessionRevision, !(error is CancellationError) else { return }
        if case AccountError.sessionChanged = error { return }
        let requiresLogin: Bool
        switch error {
        case AccountError.oauth("invalid_grant"), AccountError.api(401, _): requiresLogin = true
        default: requiresLogin = false
        }
        if requiresLogin { _ = try? invalidate() }
        errorMessage = error.localizedDescription
    }

    private func unique<T: Identifiable>(_ values: [T]) -> [T] where T.ID: Hashable {
        var seen: Set<T.ID> = []
        return values.filter { seen.insert($0.id).inserted }
    }
}
