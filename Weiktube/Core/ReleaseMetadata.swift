// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// SemVer precedence; build metadata is deliberately excluded from equality and ordering.
struct ReleaseVersion: Hashable, Comparable, CustomStringConvertible, Sendable {
    let major: UInt64
    let minor: UInt64
    let patch: UInt64
    let prerelease: [String]
    let buildMetadata: [String]

    init?(_ raw: String) {
        guard !raw.isEmpty, raw.utf8.count <= 128 else { return nil }
        let value = raw.hasPrefix("v") || raw.hasPrefix("V") ? String(raw.dropFirst()) : raw
        guard !value.isEmpty else { return nil }
        let metadataParts = value.split(separator: "+", omittingEmptySubsequences: false)
        guard metadataParts.count <= 2, metadataParts.count != 2 || !metadataParts[1].isEmpty else { return nil }
        let versionParts = metadataParts[0].split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard versionParts.count != 2 || !versionParts[1].isEmpty else { return nil }
        let numbers = versionParts[0].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard numbers.count == 3,
              numbers.allSatisfy({ Self.digits($0) && ($0 == "0" || !$0.hasPrefix("0")) }),
              let major = UInt64(numbers[0]), let minor = UInt64(numbers[1]), let patch = UInt64(numbers[2]) else { return nil }
        let prerelease = versionParts.count == 2 ? versionParts[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init) : []
        let metadata = metadataParts.count == 2 ? metadataParts[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init) : []
        guard prerelease.allSatisfy(Self.identifier), metadata.allSatisfy(Self.identifier),
              prerelease.allSatisfy({ !Self.digits($0) || $0 == "0" || !$0.hasPrefix("0") }) else { return nil }
        self.major = major; self.minor = minor; self.patch = patch
        self.prerelease = prerelease; self.buildMetadata = metadata
    }

    var description: String {
        "\(major).\(minor).\(patch)" + (prerelease.isEmpty ? "" : "-" + prerelease.joined(separator: ".")) +
        (buildMetadata.isEmpty ? "" : "+" + buildMetadata.joined(separator: "."))
    }

    static func == (left: Self, right: Self) -> Bool {
        left.major == right.major && left.minor == right.minor && left.patch == right.patch && left.prerelease == right.prerelease
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(major); hasher.combine(minor); hasher.combine(patch); hasher.combine(prerelease)
    }

    static func < (left: Self, right: Self) -> Bool {
        if left.major != right.major { return left.major < right.major }
        if left.minor != right.minor { return left.minor < right.minor }
        if left.patch != right.patch { return left.patch < right.patch }
        if left.prerelease.isEmpty { return false }
        if right.prerelease.isEmpty { return true }
        for (a, b) in zip(left.prerelease, right.prerelease) where a != b {
            let aNumeric = digits(a), bNumeric = digits(b)
            if aNumeric && bNumeric { return a.count == b.count ? a < b : a.count < b.count }
            if aNumeric != bNumeric { return aNumeric }
            return a < b
        }
        return left.prerelease.count < right.prerelease.count
    }

    private static func digits(_ value: String) -> Bool { !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) } }
    private static func identifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }
    }
}

struct ReleaseAssetMetadata: Codable, Equatable, Sendable {
    let name: String
    let url: URL
    let size: Int64
}

enum ReleaseMetadataError: Error, LocalizedError {
    case invalidResponse, unsupportedRelease, responseTooLarge
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Die Release-Metadaten enthalten ungültige Versionsangaben oder fremde Links."
        case .unsupportedRelease: return "GitHub hat kein veröffentlichtes stabiles iOS-Release geliefert."
        case .responseTooLarge: return "Die Release-Metadaten überschreiten die erlaubte Größe."
        }
    }
}

struct ReleaseMetadata: Codable, Equatable, Sendable {
    let tag: String
    let name: String
    let notes: String
    let htmlURL: URL
    let publishedAt: Date
    let assets: [ReleaseAssetMetadata]
    var version: ReleaseVersion? { ReleaseVersion(tag) }

    var isValid: Bool {
        guard let version, version.prerelease.isEmpty, name.utf8.count <= 512, notes.utf8.count <= 262_144,
              publishedAt.timeIntervalSince1970.isFinite, assets.count <= 100,
              ReleaseURLPolicy.releasePage(htmlURL, tag: tag) else { return false }
        return assets.allSatisfy { asset in
            asset.size >= 0 && ReleaseURLPolicy.asset(asset.url, tag: tag, name: asset.name)
        }
    }

    static func decode(_ data: Data) throws -> ReleaseMetadata {
        guard data.count <= 524_288 else { throw ReleaseMetadataError.responseTooLarge }
        let payload = try JSONDecoder().decode(GitHubReleasePayload.self, from: data)
        guard !payload.draft, !payload.prerelease else { throw ReleaseMetadataError.unsupportedRelease }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var published = payload.published_at.flatMap(formatter.date(from:))
        if published == nil {
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            published = payload.published_at.flatMap(formatter.date(from:))
        }
        guard let url = URL(string: payload.html_url), let published else { throw ReleaseMetadataError.invalidResponse }
        let assets = try payload.assets.map { asset -> ReleaseAssetMetadata in
            guard let url = URL(string: asset.browser_download_url) else { throw ReleaseMetadataError.invalidResponse }
            return ReleaseAssetMetadata(name: asset.name, url: url, size: asset.size)
        }
        let result = ReleaseMetadata(tag: payload.tag_name, name: payload.name?.isEmpty == false ? payload.name! : payload.tag_name,
                                     notes: payload.body ?? "", htmlURL: url, publishedAt: published, assets: assets)
        guard result.isValid else { throw ReleaseMetadataError.invalidResponse }
        return result
    }
}

private struct GitHubReleasePayload: Decodable {
    struct Asset: Decodable { let name: String; let browser_download_url: String; let size: Int64 }
    let tag_name: String
    let name: String?
    let body: String?
    let html_url: String
    let published_at: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
}

enum ReleaseURLPolicy {
    private static let repositoryPath = "/weikiboy-tech/Weiktube-iOS"

    static func releasePage(_ url: URL, tag: String) -> Bool {
        guard ReleaseVersion(tag) != nil, let components = safeComponents(url) else { return false }
        return repositoryRelativePath(components.path) == "/releases/tag/" + tag
    }

    static func asset(_ url: URL, tag: String, name: String) -> Bool {
        guard ReleaseVersion(tag) != nil, !name.isEmpty, name.utf8.count <= 256,
              name != ".", name != "..", !name.contains("/"), !name.contains("\\"),
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let components = safeComponents(url) else { return false }
        return repositoryRelativePath(components.path) == "/releases/download/" + tag + "/" + name
    }

    /// GitHub owner/repository names are case-insensitive; release tags and asset names are not.
    private static func repositoryRelativePath(_ path:String) -> String? {
        guard path.count>repositoryPath.count,
              path.prefix(repositoryPath.count).lowercased()==repositoryPath.lowercased(),
              path.dropFirst(repositoryPath.count).first=="/" else{return nil}
        return String(path.dropFirst(repositoryPath.count))
    }

    private static func safeComponents(_ url: URL) -> URLComponents? {
        guard url.absoluteString.utf8.count <= 4096,
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false),
              value.scheme == "https", value.host?.lowercased() == "github.com",
              value.user == nil, value.password == nil, value.query == nil, value.fragment == nil,
              value.port == nil || value.port == 443,
              value.percentEncodedPath.range(of: #"%(?:2f|5c|0[0-9a-f]|1[0-9a-f]|7f)"#, options: [.regularExpression, .caseInsensitive]) == nil,
              !value.path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else { return nil }
        return value
    }
}
