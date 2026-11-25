// SPDX-License-Identifier: GPL-3.0-only
import Combine
import Foundation
import CoreFoundation
import WebKit
import UIKit

@MainActor
final class WebSession: NSObject, ObservableObject, WKNavigationDelegate {
    enum Role: String { case home, player, shorts }
    let role: Role
    let webView: WKWebView
    @Published private(set) var loading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var canGoBack = false
    @Published private(set) var currentURL: URL?
    @Published private(set) var snapshot = MediaSnapshot()
    var onRoute: ((URL) -> Void)?
    var onExternalURL: ((URL) -> Void)?
    var onMedia: ((MediaSnapshot) -> Void)?
    var onAccountRequested: (() -> Void)?
    var onMuteIntent: ((Bool) -> Void)?
    var onProcessTerminated: (() -> Void)?
    var onFullscreenRequested: (() -> Void)?
    private let adBlock: AdBlockService
    private var observations: [NSKeyValueObservation] = []
    private var configurationTask: Task<Void, Never>?
    private var bridgeActivationTask: Task<Void, Never>?
    private var documentProbeTask: Task<Void, Never>?
    private var suspensionTask: Task<Void, Never>?
    private var suspensionRevision = 0
    private var token = UUID().uuidString
    private(set) var generation = 0
    private var expectedVideoID: String?
    private var suspended = true
    private var userMuted = false
    private var originalControls = false
    private var pendingURL: URL?
    private var ready = false
    private var recoverySourceIdentity: String?
    private var recoverySourceURL: URL?
    private var automaticRecoveryUsed = false
    private var documentWasHealthy = false
    private var destroyed = false
    private static let world = WKContentWorld.defaultClient

    init(role: Role, adBlock: AdBlockService) {
        self.role = role
        self.adBlock = adBlock
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        // Autoplay remains subject to content, system policy and actual playback results.
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.allowsBackForwardNavigationGestures = role != .player
        webView.navigationDelegate = self
        webView.accessibilityIdentifier = "web.\(role.rawValue)"
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.configuration.userContentController.add(WeakScriptHandler(owner: self), contentWorld: Self.world, name: "weiktube")
        if let url = Bundle.main.url(forResource: "MediaBridge", withExtension: "js"),
           let source = try? String(contentsOf: url, encoding: .utf8) {
            webView.configuration.userContentController.addUserScript(
                WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: Self.world))
        } else {
            errorMessage = "Die Medienintegration fehlt im App-Bundle. Bitte den Build prüfen."
        }
        observations = [
            webView.observe(\.isLoading, options: [.new]) { [weak self] _, value in
                Task { @MainActor [weak self] in self?.loading = value.newValue ?? false }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] _, value in
                Task { @MainActor [weak self] in self?.canGoBack = value.newValue ?? false }
            }
        ]
        configurationTask = Task { [weak self] in
            guard let self else { return }
            await adBlock.configure(controller: webView.configuration.userContentController)
            guard !Task.isCancelled else { return }
            await setSuspended(suspended)
            guard !Task.isCancelled, !destroyed else { return }
            ready = true
            if let pendingURL { self.pendingURL = nil; load(pendingURL, expectedVideoID: expectedVideoID) }
        }
    }

    func load(_ url: URL, expectedVideoID: String? = nil) {
        guard !destroyed, Self.permitsPage(url) else {
            errorMessage = "Dieser Link kann nicht in der YouTube-Ansicht geöffnet werden."
            return
        }
        self.expectedVideoID = expectedVideoID
        selectRecoverySource(url)
        guard ready else { pendingURL = url; return }
        loadSelectedDocument(url)
    }

    private func loadSelectedDocument(_ url: URL) {
        documentProbeTask?.cancel()
        generation += 1
        token = UUID().uuidString
        errorMessage = nil
        snapshot = MediaSnapshot()
        currentURL = url
        webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30))
    }

    func setSuspended(_ value: Bool) async {
        guard !destroyed else { return }
        suspended = value
        suspensionRevision += 1
        let revision = suspensionRevision
        let previous = suspensionTask
        let task = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, !destroyed, revision == suspensionRevision else { return }
            // Native suspension is authoritative: page code cannot restart a non-owning view.
            await webView.setAllMediaPlaybackSuspended(value)
            guard !destroyed, revision == suspensionRevision else { return }
            _ = await command("suspend", values: ["value": value])
        }
        suspensionTask = task
        await task.value
        if !value { inspectFinishedDocument() }
    }

    func setUserMuted(_ value: Bool) async {
        userMuted = value
        _ = await command("mute", values: ["value": value])
    }

    func showOriginalControls(_ value: Bool) async {
        originalControls = value
        _ = await command("originalControls", values: ["value": value])
    }

    @discardableResult
    func command(_ name: String, values: [String: Any] = [:], elementID: String? = nil) async -> [String: Any]? {
        guard !destroyed, webView.url.map(Self.permitsPage) == true else { return nil }
        let capturedGeneration = generation
        var arguments = values
        arguments["token"] = token
        arguments["generation"] = generation
        if let elementID { arguments["elementID"] = elementID }
        do {
            let result = try await webView.callAsyncJavaScript(
                "return window.WeiktubeMedia ? window.WeiktubeMedia.command(name, values) : {ok:false};",
                arguments: ["name": name, "values": arguments], in: nil, contentWorld: Self.world)
            guard capturedGeneration == generation else { return nil }
            return result as? [String: Any]
        } catch { return nil }
    }

    func back() {
        guard webView.canGoBack else { return }
        if let url = webView.backForwardList.backItem?.url { selectRecoverySource(url) }
        documentProbeTask?.cancel()
        generation += 1; token = UUID().uuidString
        webView.goBack()
    }

    func reload() {
        guard let url = currentURL ?? webView.url else { return }
        load(url, expectedVideoID: expectedVideoID)
    }

    private func activateBridge() {
        guard let url = webView.url, Self.permitsPage(url), !destroyed else { return }
        if let expectedVideoID, Self.videoID(url) != expectedVideoID { return }
        let capturedGeneration = generation
        let context: [String: Any] = ["role": role.rawValue, "token": token, "generation": generation,
                                      "suspended": suspended, "userMuted": userMuted, "originalControls": originalControls]
        bridgeActivationTask?.cancel()
        bridgeActivationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            _ = try? await webView.callAsyncJavaScript(
                "return window.WeiktubeMedia ? window.WeiktubeMedia.activate(context) : false;",
                arguments: ["context": context], in: nil, contentWorld: Self.world)
            guard !Task.isCancelled, generation == capturedGeneration else { return }
            await setSuspended(suspended)
        }
    }

    fileprivate func receive(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              message.frameInfo.securityOrigin.protocol == "https",
              Self.permittedHosts.contains(message.frameInfo.securityOrigin.host.lowercased()),
              let data = message.body as? [String: Any], data.count <= 32,
              let kind = data["kind"] as? String else { return }
        if kind == "ready" { activateBridge(); return }
        guard data["token"] as? String == token,
              let reportedGeneration = data["generation"] as? NSNumber,
              CFGetTypeID(reportedGeneration) != CFBooleanGetTypeID(),
              reportedGeneration.doubleValue == Double(generation) else { return }
        switch kind {
        case "media":
            guard let sample = MediaSnapshot.decode(data) else { return }
            if let expectedVideoID, sample.videoID != expectedVideoID { return }
            snapshot = sample
            onMedia?(sample)
        case "route":
            guard let text = data["url"] as? String, text.utf8.count <= 4096,
                  let url = URL(string: text), Self.permitsPage(url),
                  let route = YouTubeLinkRouter.route(url) else { return }
            onRoute?(route.url)
        case "fullscreen":
            guard role == .player, snapshot.ready, !snapshot.elementID.isEmpty else { return }
            onFullscreenRequested?()
        case "muteIntent":
            if let muted = data["muted"] as? NSNumber, CFGetTypeID(muted) == CFBooleanGetTypeID() {
                userMuted = muted.boolValue; onMuteIntent?(muted.boolValue)
            }
        default: break
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        currentURL = webView.url
        Task { @MainActor [weak self] in
            guard let self, !destroyed else { return }
            await setSuspended(suspended)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        errorMessage = nil
        currentURL = webView.url
        activateBridge()
        inspectFinishedDocument()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { navigationFailed(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { navigationFailed(error) }
    private func navigationFailed(_ error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        errorMessage = "YouTube konnte nicht geladen werden. Prüfe die Verbindung und versuche es erneut."
        DiagnosticsStore.shared.record(.navigationFailure)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        let host = url.host?.lowercased()
        if host == "accounts.google.com" || host == "accounts.youtube.com" {
            decisionHandler(.cancel)
            if navigationAction.targetFrame?.isMainFrame != false { onAccountRequested?() }
            return
        }
        if navigationAction.targetFrame?.isMainFrame == false {
            let allowedFrame = url.absoluteString == "about:blank" ||
                (url.scheme == "https" && Self.permittedFrameHosts.contains(host ?? "") &&
                 url.user == nil && url.password == nil && (url.port == nil || url.port == 443))
            decisionHandler(allowedFrame ? .allow : .cancel)
            return
        }
        if navigationAction.navigationType == .linkActivated,
           Self.permitsPage(url),url.path == "/redirect",
           let components=URLComponents(url:url,resolvingAgainstBaseURL:false) {
            let targets=(components.queryItems ?? []).filter { $0.name == "q" || $0.name == "url" }
            if targets.count == 1,let raw=targets[0].value,let target=URL(string:raw),Self.permitsExternalURL(target),!Self.permitsPage(target) {
                decisionHandler(.cancel);onExternalURL?(target);return
            }
        }
        guard Self.permitsPage(url) else {
            decisionHandler(.cancel)
            if navigationAction.navigationType == .linkActivated,Self.permitsExternalURL(url) {onExternalURL?(url)}
            return
        }
        if navigationAction.navigationType == .linkActivated, let videoID = Self.videoID(url),
           !(role == .shorts && url.path.hasPrefix("/shorts")),
           !(role == .player && expectedVideoID == videoID) {
            decisionHandler(.cancel); onRoute?(url); return
        }
        if navigationAction.targetFrame == nil {
            decisionHandler(.cancel)
            load(url)
            return
        }
        if navigationAction.navigationType == .linkActivated { selectRecoverySource(url) }
        decisionHandler(.allow)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard !destroyed else { return }
        DiagnosticsStore.shared.record(.webProcessTerminated)
        recoverSelectedDocument()
    }

    private func selectRecoverySource(_ url: URL) {
        guard Self.permitsPage(url) else { return }
        let identity: String
        if role == .player, let expectedVideoID { identity = "watch:" + expectedVideoID }
        else { identity = YouTubeLinkRouter.route(url)?.identity ?? url.absoluteString }
        if recoverySourceIdentity != identity {
            recoverySourceIdentity = identity
            automaticRecoveryUsed = false
            documentWasHealthy = false
        }
        recoverySourceURL = url
    }

    /// A finished, script-free empty document is a concrete loss signal, not a slow-page timer.
    /// Merely missing a video, bridge callback, thumbnail, or readyState transition never reloads a page.
    private func inspectFinishedDocument() {
        guard !destroyed, ready, !webView.isLoading, recoverySourceURL != nil else { return }
        let capturedGeneration = generation
        documentProbeTask?.cancel()
        documentProbeTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled, !destroyed, generation == capturedGeneration, !webView.isLoading else { return }
            let script = """
                const body = document.body;
                const content = !!body && (body.children.length > 0 || (body.textContent || '').trim().length > 0);
                const renderingScript = Array.from(document.scripts).some(script => {
                    const type = (script.type || '').toLowerCase();
                    return !type || type === 'module' || type === 'text/javascript' || type === 'application/javascript';
                });
                return {href:String(location.href),complete:document.readyState === 'complete',content,renderingScript};
                """
            guard let result = try? await webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: Self.world),
                  let values = result as? [String: Any], !Task.isCancelled, !destroyed,
                  generation == capturedGeneration, !webView.isLoading,
                  let href = values["href"] as? String, let complete = values["complete"] as? Bool,
                  let content = values["content"] as? Bool, let renderingScript = values["renderingScript"] as? Bool else { return }
            let location = URL(string: href)
            let expectedPage = location.map(Self.permitsPage) == true && location?.host != "consent.youtube.com"
            if complete && content && expectedPage { documentWasHealthy = true; return }
            let lostBlank = documentWasHealthy && (href.isEmpty || href == "about:blank")
            guard complete, !content, !renderingScript, expectedPage || lostBlank else { return }
            DiagnosticsStore.shared.record(.navigationFailure)
            recoverSelectedDocument()
        }
    }

    private func recoverSelectedDocument() {
        guard !destroyed, ready, let fallback = recoverySourceURL else { return }
        // Capture playback position/intent before the document generation changes.
        onProcessTerminated?()
        guard !automaticRecoveryUsed else {
            errorMessage = "Die Webansicht konnte nach einem automatischen Wiederherstellungsversuch nicht stabil geladen werden. Bitte gezielt neu laden."
            return
        }
        automaticRecoveryUsed = true
        let current = webView.url.flatMap { Self.permitsPage($0) ? $0 : nil }
        let target: URL
        if role == .player, let expectedVideoID {
            target = current.flatMap { Self.videoID($0) == expectedVideoID ? $0 : nil } ?? fallback
        } else { target = current ?? fallback }
        // This private load deliberately retains the one-attempt budget for the selected source.
        loadSelectedDocument(target)
    }

    func shutdown() {
        destroyed = true
        generation += 1
        suspensionRevision += 1
        configurationTask?.cancel()
        bridgeActivationTask?.cancel()
        documentProbeTask?.cancel()
        let previous = suspensionTask
        let view = webView
        suspensionTask = Task { @MainActor in
            await previous?.value
            await view.setAllMediaPlaybackSuspended(true)
            await view.closeAllMediaPresentations()
        }
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "weiktube", contentWorld: Self.world)
        observations.removeAll()
        webView.navigationDelegate = nil
    }

    private static let permittedHosts: Set<String> = ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "consent.youtube.com"]
    private static let permittedFrameHosts = permittedHosts.union(["youtube-nocookie.com", "www.youtube-nocookie.com", "consent.google.com"])
    static func permitsPage(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && permittedHosts.contains(url.host?.lowercased() ?? "") &&
        url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
    }
    static func permitsExternalURL(_ url:URL) -> Bool {
        guard url.absoluteString.utf8.count<=8192,!url.absoluteString.contains("\\"),
              let components=URLComponents(url:url,resolvingAgainstBaseURL:false),
              components.scheme?.lowercased()=="https",let host=components.host,!host.isEmpty,
              components.user==nil,components.password==nil,components.port==nil || components.port==443 else{return false}
        return !url.absoluteString.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
    static func videoID(_ url: URL) -> String? {
        guard permitsPage(url) else { return nil }
        return YouTubeLinkRouter.route(url)?.videoID
    }
}

@MainActor
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var owner: WebSession?
    init(owner: WebSession) { self.owner = owner }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.receive(message)
    }
}
