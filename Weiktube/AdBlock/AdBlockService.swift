// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Combine
import WebKit
import CryptoKit

@MainActor
final class AdBlockService: NSObject, ObservableObject {
    @Published private(set) var preferences: AdBlockPreferences
    @Published private(set) var status = "Werbeschutz wird vorbereitet"
    @Published private(set) var version = 0
    @Published private(set) var ruleCount = 0
    @Published private(set) var dataRemoved = 0
    @Published private(set) var cosmeticHidden = 0
    @Published private(set) var breakthroughs = 0
    @Published private(set) var scriptErrors = 0
    @Published private(set) var isUpdating = false
    @Published private(set) var requiresReload = false
    @Published private(set) var lastUpdate: Date?
    var enabled: Bool { preferences.enabled }
    private let defaults: UserDefaults
    private var snapshot: FilterSnapshot?
    private var compiled: WKContentRuleList?
    private var prepareTask: Task<Void, Never>?
    private var compileRevision = UUID()
    private var registrations: [Registration] = []
    private let transport = PublicServiceTransport(hosts: ["github.com", "raw.githubusercontent.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com"], allowRedirects: true)
    private static let scriptMarker = "/* WEIKTUBE_FILTER_SCRIPT_V1 */"
    private static let updateRoot = "https://github.com/weikiboy-tech/Weiktube/releases/download/adblock-rules-v1/"
    private struct Envelope: Codable { let payload: Data; let signature: String }
    private final class Registration {
        weak var controller: WKUserContentController?
        let token = UUID().uuidString
        let proxy: Bridge
        var list: WKContentRuleList?
        init(controller: WKUserContentController, owner: AdBlockService) {
            self.controller = controller; proxy = Bridge(owner: owner)
        }
    }
    private final class Bridge: NSObject, WKScriptMessageHandler {
        weak var owner: AdBlockService?
        init(owner: AdBlockService) { self.owner = owner }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            owner?.receive(message, controller: userContentController)
        }
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferences = defaults.data(forKey: "adblock.preferences").flatMap { try? JSONDecoder().decode(AdBlockPreferences.self, from: $0) } ?? .init()
        lastUpdate = defaults.object(forKey: "adblock.lastUpdate") as? Date
        super.init()
    }
    func configure(controller: WKUserContentController) async {
        registrations.removeAll { $0.controller == nil }
        if registrations.contains(where: { $0.controller === controller }) { return }
        if snapshot == nil {
            if let prepareTask { await prepareTask.value }
            else {
                let task = Task { await self.prepare() }; prepareTask = task
                await task.value; prepareTask = nil
            }
        }
        guard !registrations.contains(where: { $0.controller === controller }) else { return }
        let registration = Registration(controller: controller, owner: self)
        registrations.append(registration)
        controller.add(registration.proxy, contentWorld: .page, name: "weiktubeAdEvents")
        apply(to: registration)
    }
    func setEnabled(_ enabled: Bool) async {
        var changed = preferences; changed.enabled = enabled
        await setPreferences(changed)
    }
    func setPreferences(_ value: AdBlockPreferences) async {
        guard value != preferences else { return }
        preferences = value
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: "adblock.preferences") }
        requiresReload = !registrations.isEmpty
        if let snapshot { await compile(snapshot) }
    }
    func setDomainLists(custom: String, exceptions: String) async throws {
        var changed = preferences
        changed.customDomains = try DomainListParser.parse(custom)
        changed.exceptions = try DomainListParser.parse(exceptions)
        await setPreferences(changed)
    }
    /// Called by the app after its user-requested reload has replaced affected documents.
    func didReloadPages() { requiresReload = false }
    func resetCounters() { dataRemoved = 0; cosmeticHidden = 0; breakthroughs = 0; scriptErrors = 0 }

    private func prepare() async {
        do {
            let key = try FilterResources.text("update-public-key", extension: "txt")
            let bundled = try SignedFilterPackage.verify(data: FilterResources.data("rules", extension: "json"),
                                                        signature: FilterResources.text("rules", extension: "sig"), publicKey: key)
            var selected = bundled
            if let url = cacheURL(), let data = try? Data(contentsOf: url), data.count <= 2 * FilterSnapshot.maxBytes,
               let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
               let cached = try? SignedFilterPackage.verify(data: envelope.payload, signature: envelope.signature, publicKey: key, minimumVersion: bundled.version) { selected = cached }
            _ = try FilterResources.text("vendor-scriptlets", extension: "js")
            _ = try FilterResources.text("filter-runtime-ios", extension: "js")
            await compile(selected)
        } catch {
            status = "Werbeschutz konnte nicht vorbereitet werden. Mitgelieferte Filter prüfen."
        }
    }
    private func compile(_ candidate: FilterSnapshot) async {
        let revision = UUID(); compileRevision = revision
        do {
            let json = try WebKitRuleCompiler.rules(snapshot: candidate, preferences: preferences, appDomain: Bundle.main.bundleIdentifier ?? "com.weiktube.ios")
            let digest = SHA256.hash(data: Data(json.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
            let list: WKContentRuleList = try await withCheckedThrowingContinuation { continuation in
                WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "weiktube-\(digest)", encodedContentRuleList: json) { list, error in
                    if let list { continuation.resume(returning: list) }
                    else { continuation.resume(throwing: error ?? PublicServiceError.invalidResponse) }
                }
            }
            guard revision == compileRevision else { return }
            // Replace attached lists only after candidate compilation succeeds.
            snapshot = candidate; compiled = list; version = candidate.version
            ruleCount = (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [Any])?.count ?? 0
            registrations.removeAll { $0.controller == nil }
            for registration in registrations { apply(to: registration) }
            status = preferences.enabled ? "Filter bereit · vollständige Werbefreiheit ist nicht garantiert" : "Netzwerkfilter ausgeschaltet"
        } catch {
            guard revision == compileRevision else { return }
            status = compiled == nil ? "WebKit konnte die Filter nicht kompilieren" : "Neue Filter ungültig. Der letzte gültige Regelsatz bleibt aktiv."
        }
    }
    private func apply(to registration: Registration) {
        guard let controller = registration.controller else { return }
        if let previous = registration.list { controller.remove(previous) }
        if preferences.enabled, let compiled { controller.add(compiled); registration.list = compiled }
        else { registration.list = nil }
        // WKUserContentController has no remove-one-script operation. Preserve all unrelated app scripts.
        let unrelated = controller.userScripts.filter { !$0.source.hasPrefix(Self.scriptMarker) }
        controller.removeAllUserScripts(); unrelated.forEach(controller.addUserScript)
        guard let snapshot, preferences.enabled, preferences.ads else { return }
        do {
            var config = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as! [String: Any]
            config["token"] = registration.token; config["enabled"] = true
            config["exceptions"] = preferences.exceptions.sorted()
            let text = String(data: try JSONSerialization.data(withJSONObject: config, options: [.sortedKeys]), encoding: .utf8)!
            let vendor = try FilterResources.text("vendor-scriptlets", extension: "js")
            let runtime = try FilterResources.text("filter-runtime-ios", extension: "js")
            let source = Self.scriptMarker + "\n(function(){'use strict';if(location.protocol!=='https:'||(location.port&&location.port!=='443')||!/^(?:(?:m|www)\\.)?youtube(?:-nocookie)?\\.com$/.test(location.hostname))return;window.__weiktubeAdConfig=" + text + ";\n" + vendor + "\n" + runtime + "\n})();"
            controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page))
        } catch { scriptErrors += 1; status = "Scriptlet-Ressourcen fehlen. Netzwerkfilter bleiben aktiv." }
    }
    private func receive(_ message: WKScriptMessage, controller: WKUserContentController) {
        guard preferences.enabled, message.name == "weiktubeAdEvents",
              let registration = registrations.first(where: { $0.controller === controller }),
              let data = message.body as? [String: Any], data.count <= 6,
              data["token"] as? String == registration.token, data["version"] as? Int == version,
              let type = data["type"] as? String, let count = data["count"] as? Int, (0...10000).contains(count) else { return }
        let origin = message.frameInfo.securityOrigin
        guard origin.protocol == "https", [0, 443].contains(origin.port),
              ["youtube.com", "www.youtube.com", "m.youtube.com", "youtube-nocookie.com", "www.youtube-nocookie.com"].contains(origin.host) else { return }
        // These are page-reported aggregate diagnostics, never auth decisions or blocked-request totals.
        switch type {
        case "data": dataRemoved = min(1_000_000_000, dataRemoved + count)
        case "cosmetic": cosmeticHidden = min(1_000_000_000, cosmeticHidden + count)
        case "breakthrough": breakthroughs = min(1_000_000_000, breakthroughs + count)
        case "error": scriptErrors = min(1_000_000_000, scriptErrors + max(1, count))
        default: break
        }
    }
    func checkForUpdates(manual: Bool = true) async {
        guard !isUpdating else { return }
        if !manual, let last = defaults.object(forKey: "adblock.lastAttempt") as? Date, Date().timeIntervalSince(last) < 86400 { return }
        if snapshot == nil { await prepare() }
        guard let current = snapshot else { return }
        isUpdating = true; defaults.set(Date(), forKey: "adblock.lastAttempt")
        defer { isUpdating = false }
        do {
            let data = try await transport.get(URL(string: Self.updateRoot + "youtube-filter.json")!, limit: FilterSnapshot.maxBytes, userAgent: "Weiktube-iOS/FilterUpdater")
            let signatureResponse = try await transport.get(URL(string: Self.updateRoot + "youtube-filter.sig")!, limit: 4096, userAgent: "Weiktube-iOS/FilterUpdater")
            guard data.status == 200, signatureResponse.status == 200, let signature = String(data: signatureResponse.data, encoding: .utf8) else { throw PublicServiceError.invalidResponse }
            let candidate = try SignedFilterPackage.verify(data: data.data, signature: signature,
                                                          publicKey: FilterResources.text("update-public-key", extension: "txt"), minimumVersion: current.version)
            if candidate.version > current.version {
                await compile(candidate)
                guard snapshot?.version == candidate.version else { throw PublicServiceError.invalidResponse }
                if let url = cacheURL() {
                    try JSONEncoder().encode(Envelope(payload: data.data, signature: signature)).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                }
                requiresReload = !registrations.isEmpty
                status = "Signiertes Filterupdate bereit. Scriptlets gelten ab dem nächsten Seitenaufruf."
            } else { status = "Der letzte veröffentlichte Regelsatz ist bereits installiert." }
            lastUpdate = Date(); defaults.set(lastUpdate, forKey: "adblock.lastUpdate")
        } catch {
            status = "Update nicht verfügbar oder ungültig. Vorhandene Filter bleiben aktiv."
        }
    }
    private func cacheURL() -> URL? {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let directory = root.appendingPathComponent("WeiktubeFilters", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("signed-filter.json")
    }
}
