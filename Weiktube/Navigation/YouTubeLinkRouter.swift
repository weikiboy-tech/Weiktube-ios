// SPDX-License-Identifier: GPL-3.0-only
// Native iOS port of Weiktube public-link behavior. No protected stream extraction.
import Foundation

struct VideoLink: Equatable, Hashable, Sendable {
    let id: String
    /// nil means no explicit timestamp; zero deliberately overrides saved history.
    let startSeconds: Double?
    let playlistID: String?
    let index: Int?

    init(id: String, startSeconds: Double? = nil, playlistID: String? = nil, index: Int? = nil) {
        self.id = id
        self.startSeconds = startSeconds
        self.playlistID = playlistID
        self.index = index
    }

    var url: URL {
        var components = URLComponents(string: "https://m.youtube.com/watch")!
        var items = [URLQueryItem(name: "v", value: id)]
        if let startSeconds, startSeconds.isFinite {
            items.append(.init(name: "t", value: String(Int(max(0, min(86_400, startSeconds))))))
        }
        if let playlistID { items.append(.init(name: "list", value: playlistID)) }
        if let index { items.append(.init(name: "index", value: String(index))) }
        components.queryItems = items
        return components.url!
    }
}

enum MediaRoute: Equatable, Sendable {
    case video(VideoLink)
    case shorts(VideoLink?)
    case playlist(id: String)
    case channel(path: String)
    case search(query: String)
    case home
    case feed(path: String)
    case directMedia(URL)

    var url: URL {
        switch self {
        case .video(let video): return video.url
        case .shorts(let video):
            var components = URLComponents(string: "https://m.youtube.com/shorts/")!
            if let video {
                components.path += video.id
                if let seconds = video.startSeconds, seconds.isFinite {
                    components.queryItems = [.init(name: "t", value: String(Int(max(0, min(86_400, seconds)))))]
                }
            }
            return components.url!
        case .playlist(let id):
            var components = URLComponents(string: "https://m.youtube.com/playlist")!
            components.queryItems = [.init(name: "list", value: id)]
            return components.url!
        case .channel(let path), .feed(let path):
            var components = URLComponents(string: "https://m.youtube.com")!
            components.path = path
            return components.url!
        case .search(let query):
            var components = URLComponents(string: "https://m.youtube.com/results")!
            components.queryItems = [.init(name: "search_query", value: query)]
            return components.url!
        case .home: return URL(string: "https://m.youtube.com/")!
        case .directMedia(let url): return url
        }
    }

    var videoID: String? {
        switch self { case .video(let item): return item.id; case .shorts(let item): return item?.id; default: return nil }
    }
    var startSeconds: Double? {
        switch self { case .video(let item): return item.startSeconds; case .shorts(let item): return item?.startSeconds; default: return nil }
    }
    var isShorts: Bool { if case .shorts = self { return true }; return false }
    var isPlayable: Bool {
        switch self { case .video, .shorts, .directMedia: return true; default: return false }
    }
    /// Public identity intentionally excludes tracking parameters and resume timestamps.
    var identity: String {
        switch self {
        case .video(let video): return "watch:\(video.id)"
        case .shorts(let video): return "shorts:\(video?.id ?? "feed")"
        default: return url.absoluteString
        }
    }
}

enum YouTubeLinkRouter {
    private static let youtubeHosts: Set<String> = ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"]
    private static let embedHosts: Set<String> = ["youtube-nocookie.com", "www.youtube-nocookie.com"]
    private static let feedPaths: Set<String> = ["/feed/you", "/feed/library", "/feed/subscriptions", "/feed/history", "/feed/trending", "/feed/what_to_watch"]
    private static let channelSections: Set<String> = ["videos", "shorts", "streams", "live", "playlists", "community", "about", "featured"]

    static func validVideoID(_ id: String) -> Bool {
        id.utf8.count == 11 && id.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil
    }
    static func route(_ url: URL) -> MediaRoute? { route(url.absoluteString) }

    static func route(_ raw: String) -> MediaRoute? { parse(raw, allowScheme: true) }

    private static func parse(_ raw: String, allowScheme: Bool) -> MediaRoute? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 8192,
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !text.contains("\\"), !text.contains(" "),
              let components = URLComponents(string: text),
              components.user == nil, components.password == nil else { return nil }
        if components.scheme?.lowercased() == "weiktube" {
            guard allowScheme, components.host == "open", components.path.isEmpty || components.path == "/",
                  components.port == nil, components.fragment == nil,
                  let items = components.queryItems, items.count == 1, items[0].name == "url",
                  let nested = items[0].value else { return nil }
            return parse(nested, allowScheme: false)
        }
        guard components.scheme?.lowercased() == "https", components.port == nil || components.port == 443,
              let host = components.host?.lowercased(), !host.isEmpty,
              components.percentEncodedPath.range(of: #"%(?:2f|5c|0[0-9a-f]|1[0-9a-f]|7f)"#, options: [.regularExpression, .caseInsensitive]) == nil,
              !components.path.contains("//"),
              !components.path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == "." || $0 == ".." }) else { return nil }
        let youtube = youtubeHosts.contains(host)
        let short = host == "youtu.be"
        let embed = embedHosts.contains(host)
        guard youtube || short || embed else {
            guard let url = components.url, directMediaAllowed(url) else { return nil }
            return .directMedia(url)
        }
        let path = components.path
        let pieces = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let query = components.queryItems ?? []
        // Ambiguous identity or timestamp keys are rejected, not resolved by last-wins rules.
        let significant = ["v", "list", "index", "t", "start", "time_continue", "search_query"]
        guard significant.allSatisfy({ key in
            let values = query.filter { $0.name == key }
            return values.count <= 1 && values.allSatisfy { $0.value != nil }
        }) else { return nil }
        func value(_ key: String) -> String? { query.first { $0.name == key }?.value }
        let time: Double?
        if let rawTime = value("t") ?? value("start") ?? value("time_continue") {
            guard let parsed = seconds(rawTime) else { return nil }; time = parsed
        } else if let fragment = components.fragment, fragment.hasPrefix("t=") {
            guard let parsed = seconds(String(fragment.dropFirst(2))) else { return nil }; time = parsed
        } else { time = nil }

        let videoID: String?
        if short {
            guard pieces.count == 1 else { return nil }; videoID = pieces[0]
        } else if embed {
            guard pieces.count == 2, pieces[0] == "embed" else { return nil }; videoID = pieces[1]
        } else if path == "/watch" || path == "/watch/" { videoID = value("v") }
        else if pieces.count == 2, ["shorts", "embed", "live", "v"].contains(pieces[0]) { videoID = pieces[1] }
        else { videoID = nil }

        if let videoID {
            guard validVideoID(videoID) else { return nil }
            let list = value("list")
            guard list == nil || validPlaylistID(list!) else { return nil }
            var index: Int?
            if let rawIndex = value("index") {
                guard rawIndex.range(of: #"^[0-9]{1,9}$"#, options: .regularExpression) != nil,
                      let parsed = Int(rawIndex) else { return nil }
                index = parsed
            }
            let video = VideoLink(id: videoID, startSeconds: time, playlistID: list, index: index)
            return pieces.first == "shorts" ? .shorts(video) : .video(video)
        }
        guard youtube else { return nil }
        if path == "/shorts" || path == "/shorts/" { return .shorts(nil) }
        if path == "/playlist", let id = value("list"), validPlaylistID(id) { return .playlist(id: id) }
        if path == "/results", let search = value("search_query"), search.utf8.count <= 2048,
           !search.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) { return .search(query: search) }
        if path.isEmpty || path == "/" { return .home }
        if feedPaths.contains(path) { return path == "/feed/what_to_watch" ? .home : .feed(path: path) }
        if validChannelPath(pieces) { return .channel(path: "/" + pieces.joined(separator: "/")) }
        // Authentication, redirects, attribution wrappers and malformed watch IDs are never followed here.
        return nil
    }

    static func canonicalURL(for route: MediaRoute) -> URL { route.url }

    static func shareURL(for route: MediaRoute) -> URL {
        var components = URLComponents()
        components.scheme = "weiktube"; components.host = "open"
        components.queryItems = [.init(name: "url", value: route.url.absoluteString)]
        return components.url!
    }

    static func extractFirstRoute(from text: String) -> MediaRoute? {
        guard text.utf8.count <= 16_384 else { return nil }
        if let direct = route(text) { return direct }
        guard let expression = try? NSRegularExpression(pattern: #"https://[^\s<>]+"#, options: .caseInsensitive) else { return nil }
        let source = text as NSString
        for match in expression.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let raw = source.substring(with: match.range).trimmingCharacters(in: CharacterSet(charactersIn: ".,;!?)]}\"'"))
            if let result = parse(raw, allowScheme: false) { return result }
        }
        return nil
    }

    static func seconds(_ text: String) -> Double? {
        guard !text.isEmpty, text.utf8.count <= 64 else { return nil }
        if text.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil {
            return boundedDigits(text)
        }
        guard let match = text.range(of: #"^(?:[0-9]+h)?(?:[0-9]+m)?(?:[0-9]+s)?$"#, options: .regularExpression), match == (text.startIndex..<text.endIndex) else { return nil }
        var digits = "", result = 0.0
        for character in text {
            if character.isASCII && character.isNumber { digits.append(character); continue }
            let multiplier: Double
            switch character { case "h": multiplier = 3600; case "m": multiplier = 60; case "s": multiplier = 1; default: return nil }
            guard !digits.isEmpty else { return nil }
            result = min(86_400, result + boundedDigits(digits) * multiplier); digits = ""
        }
        return digits.isEmpty ? result : nil
    }

    private static func boundedDigits(_ digits: String) -> Double {
        digits.reduce(0.0) { min(86_400, $0 * 10 + Double($1.wholeNumberValue ?? 0)) }
    }

    private static func validPlaylistID(_ id: String) -> Bool {
        id.range(of: #"^[A-Za-z0-9_-]{1,128}$"#, options: .regularExpression) != nil
    }

    private static func validChannelPath(_ pieces: [String]) -> Bool {
        let offset: Int
        if let first = pieces.first, first.hasPrefix("@"), first.count > 1 { offset = 1 }
        else if pieces.count >= 2, ["channel", "user", "c"].contains(pieces[0]) { offset = 2 }
        else { return false }
        guard pieces.count == offset || pieces.count == offset + 1 && channelSections.contains(pieces[offset]) else { return false }
        let name = pieces[offset - 1]
        return name.utf8.count <= 256 && !name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) || CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    static func directMediaAllowed(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https", components.user == nil, components.password == nil,
              components.port == nil || components.port == 443, let host = components.host?.lowercased(),
              !host.isEmpty, components.fragment == nil,
              !url.absoluteString.contains("\\"),
              components.percentEncodedPath.range(of: #"%(?:2f|5c|0[0-9a-f]|1[0-9a-f]|7f)"#, options: [.regularExpression, .caseInsensitive]) == nil,
              !components.path.contains("//"),
              !components.path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }),
              ["mp4", "m3u8", "mov", "m4v", "webm"].contains(url.pathExtension.lowercased()),
              !["youtube.com", "youtu.be", "youtube-nocookie.com", "googlevideo.com"].contains(where: { host == $0 || host.hasSuffix("." + $0) }),
              !host.hasSuffix(".local"), !host.hasSuffix(".localhost"), host != "localhost",
              !host.hasPrefix("["), !host.contains(":"), !host.hasSuffix(".") else { return false }
        guard publicHostSyntax(host) else { return false }
        return url.absoluteString.utf8.count <= 8192
    }

    /// Validate syntax without resolving DNS or fetching the user's URL.
    /// IPv4 must use canonical dotted decimal; integer, octal and hexadecimal forms are rejected.
    private static func publicHostSyntax(_ host: String) -> Bool {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, host.utf8.count <= 253,
              labels.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 63 }) else { return false }
        if labels.allSatisfy({ $0.allSatisfy(\.isNumber) }) {
            guard labels.count == 4 else { return false }
            let octets = labels.compactMap { Int($0) }
            guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }),
                  zip(labels, octets).allSatisfy({ String($0.1) == String($0.0) }) else { return false }
            let a = octets[0], b = octets[1], c = octets[2]
            return !(a == 0 || a == 10 || a == 127 || a >= 224 ||
                a == 100 && (64...127).contains(b) || a == 169 && b == 254 ||
                a == 172 && (16...31).contains(b) ||
                a == 192 && (b == 168 || b == 0 && (c == 0 || c == 2)) ||
                a == 198 && ((18...19).contains(b) || b == 51 && c == 100) ||
                a == 203 && b == 0 && c == 113)
        }
        // Numeric last labels can trigger URL-stack alternate-IP interpretation.
        guard let last = labels.last, last.contains(where: { $0.isASCII && $0.isLetter }),
              !last.hasPrefix("0x"), !["local", "localhost", "internal", "invalid", "test"].contains(String(last)) else { return false }
        return labels.allSatisfy { label in
            !label.hasPrefix("-") && !label.hasSuffix("-") &&
            label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }
}
