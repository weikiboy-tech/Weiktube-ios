// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Security
import CryptoKit

struct FilterSnapshot: Codable, Equatable {
    struct NetworkRule: Codable, Equatable { let id: String; let host: String; let pathPrefix: String }
    struct Scriptlet: Codable, Equatable { let name: String; let args: [String]; let ruleId: String }
    let schemaVersion: Int
    let version: Int
    let networkRules: [NetworkRule]
    let scriptlets: [Scriptlet]
    let cosmeticSelectors: [String]
    static let maxBytes = 1_048_576
    static let requestMatcher = #"url:/^(?:https:\/\/(?:m\.|www\.)?youtube\.com)?\/(?:youtubei\/v\d+\/(?:player|next|browse|get_watch)(?:\?|$)|watch\?|playlist\?|get_watch\?)/"#

    static func parse(_ data: Data) throws -> FilterSnapshot {
        guard (1...maxBytes).contains(data.count),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["schemaVersion", "version", "networkRules", "scriptlets", "cosmeticSelectors"],
              let networks = object["networkRules"] as? [[String: Any]],
              let scripts = object["scriptlets"] as? [[String: Any]],
              networks.allSatisfy({ Set($0.keys) == ["id", "host", "pathPrefix"] }),
              scripts.allSatisfy({ Set($0.keys) == ["name", "args", "ruleId"] }) else { throw PublicServiceError.invalidResponse }
        let result = try JSONDecoder().decode(FilterSnapshot.self, from: data)
        guard result.schemaVersion == 1, (1...Int(Int32.max)).contains(result.version),
              result.networkRules.count <= 128, (1...64).contains(result.scriptlets.count), result.cosmeticSelectors.count <= 64 else { throw PublicServiceError.invalidResponse }
        let domains: Set<String> = ["doubleclick.net", "googlesyndication.com", "googleadservices.com", "adservice.google.com"]
        let paths: Set<String> = ["/pagead/", "/api/stats/ads"]
        let prune: Set<String> = ["playerResponse.adPlacements", "playerResponse.playerAds", "playerResponse.adSlots", "adPlacements", "playerAds", "adSlots"]
        let constants: Set<String> = ["ytInitialPlayerResponse.adPlacements", "ytInitialPlayerResponse.playerAds", "ytInitialPlayerResponse.adSlots", "playerResponse.adPlacements", "playerResponse.adSlots"]
        var identifiers = Set<String>()
        func validID(_ id: String) -> Bool { id.range(of: "^[A-Za-z0-9_.-]{1,80}$", options: .regularExpression) != nil }
        for rule in result.networkRules {
            guard validID(rule.id), identifiers.insert(rule.id).inserted,
                  (domains.contains(rule.host) && rule.pathPrefix.isEmpty) || (rule.host == "youtube.com" && paths.contains(rule.pathPrefix)) else { throw PublicServiceError.invalidResponse }
        }
        for rule in result.scriptlets {
            guard validID(rule.ruleId), identifiers.insert(rule.ruleId).inserted,
                  (1...8).contains(rule.args.count), rule.args.allSatisfy({ $0.utf8.count <= 4096 && !$0.contains("\0") }) else { throw PublicServiceError.invalidResponse }
            if rule.name == "set-constant" {
                guard rule.args.count == 2, constants.contains(rule.args[0]), rule.args[1] == "undefined" else { throw PublicServiceError.invalidResponse }
            } else {
                guard ["json-prune", "json-prune-fetch-response", "json-prune-xhr-response"].contains(rule.name),
                      !rule.args[0].isEmpty, rule.args[0].split(separator: " ", omittingEmptySubsequences: false).allSatisfy({ prune.contains(String($0)) }) else { throw PublicServiceError.invalidResponse }
                if rule.name == "json-prune" {
                    guard rule.args.count == 1 else { throw PublicServiceError.invalidResponse }
                } else {
                    guard rule.args.count == 3, rule.args[1].isEmpty, rule.args[2] == requestMatcher else { throw PublicServiceError.invalidResponse }
                }
            }
        }
        guard result.cosmeticSelectors.allSatisfy({ $0.range(of: "^(ytd|ytm)-(ad-slot|display-ad|in-feed-ad-layout|promoted-video|promoted-sparkles-web|promoted-sparkles-text-search|search-pyv)-renderer$", options: .regularExpression) != nil }) else { throw PublicServiceError.invalidResponse }
        return result
    }
}

enum SignedFilterPackage {
    static func verify(data: Data, signature: String, publicKey: String, minimumVersion: Int = 1) throws -> FilterSnapshot {
        guard data.count <= FilterSnapshot.maxBytes, signature.utf8.count <= 4096,
              let signatureData = Data(base64Encoded: signature.trimmingCharacters(in: .whitespacesAndNewlines)),
              let spki = Data(base64Encoded: publicKey.trimmingCharacters(in: .whitespacesAndNewlines)),
              let keyData = unwrapRSA(spki) else { throw PublicServiceError.invalidResponse }
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic]
        guard let key = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, nil),
              SecKeyIsAlgorithmSupported(key, .verify, .rsaSignatureMessagePKCS1v15SHA256),
              SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA256, data as CFData, signatureData as CFData, nil) else { throw PublicServiceError.invalidResponse }
        let snapshot = try FilterSnapshot.parse(data)
        guard snapshot.version >= minimumVersion else { throw PublicServiceError.invalidResponse }
        return snapshot
    }
    /// Strip the DER SubjectPublicKeyInfo envelope; Security expects the PKCS#1 public key.
    private static func unwrapRSA(_ spki: Data) -> Data? {
        struct DER {
            var bytes: [UInt8]; var offset = 0
            mutating func read(_ tag: UInt8) -> [UInt8]? {
                guard offset + 2 <= bytes.count, bytes[offset] == tag else { return nil }
                offset += 1; let first = Int(bytes[offset]); offset += 1
                var length = first
                if first >= 128 {
                    let count = first & 127
                    guard (1...4).contains(count), offset + count <= bytes.count else { return nil }
                    length = 0
                    for _ in 0..<count { length = (length << 8) | Int(bytes[offset]); offset += 1 }
                }
                guard length >= 0, offset + length <= bytes.count else { return nil }
                defer { offset += length }
                return Array(bytes[offset..<(offset + length)])
            }
        }
        var outer = DER(bytes: Array(spki))
        guard let sequence = outer.read(0x30), outer.offset == spki.count else { return nil }
        var inside = DER(bytes: sequence)
        guard let algorithm = inside.read(0x30), algorithm == [6, 9, 42, 134, 72, 134, 247, 13, 1, 1, 1, 5, 0],
              let bits = inside.read(3), bits.first == 0, bits.count > 1, inside.offset == sequence.count else { return nil }
        return Data(bits.dropFirst())
    }
}

struct AdBlockPreferences: Codable, Equatable {
    var enabled = true
    var ads = true
    var trackers = true
    var customDomains: Set<String> = []
    var exceptions: Set<String> = []
}

enum DomainListParser {
    static func parse(_ text: String) throws -> Set<String> {
        guard text.utf8.count <= 262144 else { throw PublicServiceError.responseTooLarge }
        var result = Set<String>()
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var words = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0].split(whereSeparator: \.isWhitespace).map(String.init)
            if let first = words.first, ["0.0.0.0", "127.0.0.1", "::1"].contains(first) { words.removeFirst() }
            for raw in words {
                var name = raw.lowercased()
                if name.hasSuffix(".") { name.removeLast() }
                if name == "localhost" { continue }
                guard name.count <= 253, name.contains("."), name.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ $0.range(of: "^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", options: .regularExpression) != nil }) else { throw PublicServiceError.invalidResponse }
                result.insert(name)
                guard result.count <= 4096 else { throw PublicServiceError.responseTooLarge }
            }
        }
        return result
    }
    static func matches(_ host: String, domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
}

enum WebKitRuleCompiler {
    static let protectedDomains = ["youtube.com", "youtu.be", "youtube-nocookie.com", "googlevideo.com", "ytimg.com", "accounts.google.com"]
    static func rules(snapshot: FilterSnapshot, preferences: AdBlockPreferences, appDomain: String) throws -> String {
        var rules: [[String: Any]] = []
        // iOS 17-compatible resource types. Main document and child document loads are never blocked.
        let resources = ["image", "style-sheet", "script", "font", "raw", "svg-document", "media"]
        func escaped(_ value: String) -> String { NSRegularExpression.escapedPattern(for: value) }
        func block(host: String, path: String = "", youtubeOnly: Bool = false) {
            var trigger: [String: Any] = ["url-filter": "^https://([a-z0-9-]+\\.)*" + escaped(host) + "/" + escaped(String(path.drop(while: { $0 == "/" }))), "resource-type": resources]
            if youtubeOnly { trigger["if-domain"] = ["*youtube.com", "*youtube-nocookie.com", appDomain] }
            rules.append(["trigger": trigger, "action": ["type": "block"]])
        }
        if preferences.enabled {
            if preferences.ads {
                for rule in snapshot.networkRules { block(host: rule.host, path: rule.pathPrefix, youtubeOnly: true) }
                for domain in ["doubleclick.net", "googlesyndication.com", "adnxs.com"] { block(host: domain) }
            }
            if preferences.trackers {
                for domain in ["google-analytics.com", "analytics.google.com", "connect.facebook.net", "scorecardresearch.com"] { block(host: domain) }
            }
            for domain in preferences.customDomains.sorted() where !protectedDomains.contains(where: { DomainListParser.matches(domain, domain: $0) || DomainListParser.matches($0, domain: domain) }) {
                block(host: domain)
            }
            if preferences.ads {
                for selector in snapshot.cosmeticSelectors {
                    rules.append(["trigger": ["url-filter": ".*", "if-domain": ["*youtube.com", "*youtube-nocookie.com"]], "action": ["type": "css-display-none", "selector": selector]])
                }
            }
            // Domain exceptions override every rule in this list, including cosmetic rules.
            for exception in preferences.exceptions.sorted() {
                rules.append(["trigger": ["url-filter": ".*", "if-domain": ["*" + exception]], "action": ["type": "ignore-previous-rules"]])
                rules.append(["trigger": ["url-filter": "^https://([a-z0-9-]+\\.)*" + escaped(exception) + "/"], "action": ["type": "ignore-previous-rules"]])
            }
            rules.append(["trigger": ["url-filter": ".*", "if-top-url": ["^https://([a-z0-9-]+\\.)*youtube\\.com/(signin|login|logout|account|o/oauth|servicelogin)"]], "action": ["type": "ignore-previous-rules"]])
        }
        // WebKit accepts a non-empty list; the disabled rule can never match a valid HTTPS URL.
        if rules.isEmpty { rules = [["trigger": ["url-filter": "^weiktube-disabled-filter:"], "action": ["type": "block"]]] }
        return String(data: try JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys]), encoding: .utf8)!
    }
}

enum FilterResources {
    static func url(_ name: String, extension ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Filters") ??
        Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources/Filters") ??
        Bundle.main.url(forResource: name, withExtension: ext)
    }
    static func data(_ name: String, extension ext: String) throws -> Data {
        guard let url = url(name, extension: ext) else { throw PublicServiceError.invalidResponse }
        return try Data(contentsOf: url)
    }
    static func text(_ name: String, extension ext: String) throws -> String {
        guard let value = String(data: try data(name, extension: ext), encoding: .utf8) else { throw PublicServiceError.invalidResponse }
        return value
    }
}
