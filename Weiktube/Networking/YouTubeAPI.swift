// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Authenticated YouTube Data API. Read recovery is bounded; POST/DELETE are never replayed.
@MainActor
final class YouTubeAPI {
    private let authorization: GoogleOAuthService
    private let transport = YouTubeHTTPTransport.shared
    private let decoder = JSONDecoder()
    private let permittedResources: Set<String> = ["channels", "subscriptions", "playlists", "playlistItems", "videos", "videos/getRating", "videos/rate", "commentThreads", "comments"]

    init(authorization: GoogleOAuthService) { self.authorization = authorization }

    private func request(_ resource: String, parameters: [String: String], method: String = "GET", body: Data? = nil, expected: UInt64) async throws -> Data {
        guard permittedResources.contains(resource), ["GET", "POST", "DELETE"].contains(method) else { throw AccountError.invalidResponse }
        try authorization.check(expected)
        if method != "GET" { try authorization.requireWrite(expected: expected) }
        var url = URLComponents(string: "https://www.googleapis.com/youtube/v3/\(resource)")!
        url.queryItems = parameters.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        let token = try await authorization.accessToken(expected: expected)
        try authorization.check(expected)
        func makeRequest(_ value: String) -> URLRequest {
            var request = URLRequest(url: url.url!)
            request.httpMethod = method
            request.setValue("Bearer \(value)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let body {
                request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
                request.httpBody = body
            }
            return request
        }
        var result = try await transport.send(makeRequest(token))
        try authorization.check(expected)
        if YouTubeActionPolicy.mayRetry(method: method, status: result.1.statusCode, attempts: 0) {
            let refreshed = try await authorization.accessToken(expected: expected, forceRefreshFor: token)
            try authorization.check(expected)
            result = try await transport.send(makeRequest(refreshed))
            try authorization.check(expected)
        }
        guard (200..<300).contains(result.1.statusCode) else {
            struct Failure: Decodable {
                struct Detail: Decodable {
                    struct Reason: Decodable { let reason: String? }
                    let errors: [Reason]?
                }
                let error: Detail
            }
            let reason = (try? decoder.decode(Failure.self, from: result.0))?.error.errors?.first?.reason ?? ""
            throw AccountError.api(result.1.statusCode, reason)
        }
        return result.0
    }

    private func page(_ resource: String, parameters: [String: String], token: String? = nil, expected: UInt64) async throws -> YouTubeWirePage {
        var query = parameters
        if let token = try YouTubeActionPolicy.pageToken(token) { query["pageToken"] = token }
        let data = try await request(resource, parameters: query, expected: expected)
        let page = try decoder.decode(YouTubeWirePage.self, from: data)
        let next = try YouTubeActionPolicy.pageToken(page.nextPageToken)
        guard next == nil || next != token else { throw AccountError.invalidResponse }
        return YouTubeWirePage(items: page.items, nextPageToken: next)
    }

    func ownChannels(expected: UInt64) async throws -> [YouTubeChannel] {
        let response = try await page("channels", parameters: ["part": "snippet,contentDetails", "mine": "true", "maxResults": "50"], expected: expected)
        return response.items.compactMap(YouTubeModelParser.channel)
    }

    func subscriptions(token: String? = nil, expected: UInt64) async throws -> YouTubePage<YouTubeSubscription> {
        let response = try await page("subscriptions", parameters: ["part": "snippet", "mine": "true", "order": "alphabetical", "maxResults": "50"], token: token, expected: expected)
        return YouTubePage(items: response.items.compactMap(YouTubeModelParser.subscription), nextPageToken: response.nextPageToken)
    }

    func playlists(token: String? = nil, expected: UInt64) async throws -> YouTubePage<YouTubePlaylist> {
        let response = try await page("playlists", parameters: ["part": "snippet,contentDetails", "mine": "true", "maxResults": "50"], token: token, expected: expected)
        return YouTubePage(items: response.items.compactMap(YouTubeModelParser.playlist), nextPageToken: response.nextPageToken)
    }

    func playlistItems(playlistID: String, token: String? = nil, expected: UInt64) async throws -> YouTubePage<YouTubePlaylistEntry> {
        let id = try YouTubeActionPolicy.playlistID(playlistID)
        let response = try await page("playlistItems", parameters: ["part": "snippet,contentDetails", "playlistId": id, "maxResults": "50"], token: token, expected: expected)
        let entries = response.items.compactMap { item -> YouTubePlaylistEntry? in
            guard let video = YouTubeModelParser.video(item, isPlaylistItem: true),
                  (try? YouTubeActionPolicy.resourceID(item.id)) != nil else { return nil }
            return YouTubePlaylistEntry(id: item.id, video: video)
        }
        return YouTubePage(items: entries, nextPageToken: response.nextPageToken)
    }

    func video(_ id: String, expected: UInt64) async throws -> YouTubeVideo {
        let value = try YouTubeActionPolicy.videoID(id)
        let response = try await page("videos", parameters: ["part": "snippet", "id": value], expected: expected)
        guard let item = response.items.first(where: { $0.id == value }), let video = YouTubeModelParser.video(item) else {
            throw AccountError.invalidValue("Das Video ist nicht verfügbar.")
        }
        return video
    }

    func rating(videoID: String, expected: UInt64) async throws -> YouTubeRating {
        let id = try YouTubeActionPolicy.videoID(videoID)
        let data = try await request("videos/getRating", parameters: ["id": id], expected: expected)
        return try decoder.decode(YouTubeRatingResponse.self, from: data).rating(for: id)
    }

    func rate(videoID: String, rating: YouTubeRating, expected: UInt64) async throws {
        guard rating != .unspecified else { throw AccountError.invalidValue("Ungültige Bewertung.") }
        _ = try await request("videos/rate", parameters: ["id": YouTubeActionPolicy.videoID(videoID), "rating": rating.rawValue], method: "POST", expected: expected)
    }

    func subscriptionID(channelID: String, expected: UInt64) async throws -> String? {
        let response = try await page("subscriptions", parameters: ["part": "id", "mine": "true", "forChannelId": YouTubeActionPolicy.channelID(channelID), "maxResults": "1"], expected: expected)
        return try response.items.first.map { try YouTubeActionPolicy.resourceID($0.id) }
    }

    func setSubscribed(_ wanted: Bool, channelID: String, expected: UInt64) async throws -> String? {
        // Resolve against this exact grant before deleting; never reuse another account's subscription ID.
        let existing = try await subscriptionID(channelID: channelID, expected: expected)
        try authorization.requireWrite(expected: expected)
        if wanted && existing == nil {
            let data = try await request("subscriptions", parameters: ["part": "snippet"], method: "POST", body: YouTubeActionPayloads.subscription(channelID: channelID), expected: expected)
            return try YouTubeActionPolicy.resourceID(decoder.decode(YouTubeWireItem.self, from: data).id)
        }
        if !wanted, let existing {
            _ = try await request("subscriptions", parameters: ["id": existing], method: "DELETE", expected: expected)
            return nil
        }
        return existing
    }

    func comments(videoID: String, token: String? = nil, expected: UInt64) async throws -> YouTubePage<YouTubeComment> {
        let response = try await page("commentThreads", parameters: ["part": "snippet", "videoId": YouTubeActionPolicy.videoID(videoID), "maxResults": "20", "textFormat": "plainText", "order": "relevance"], token: token, expected: expected)
        return YouTubePage(items: response.items.compactMap(YouTubeModelParser.topLevelComment), nextPageToken: response.nextPageToken)
    }

    func replies(parentID: String, token: String? = nil, expected: UInt64) async throws -> YouTubePage<YouTubeComment> {
        let response = try await page("comments", parameters: ["part": "snippet", "parentId": YouTubeActionPolicy.resourceID(parentID), "maxResults": "50", "textFormat": "plainText"], token: token, expected: expected)
        return YouTubePage(items: response.items.compactMap(YouTubeModelParser.reply), nextPageToken: response.nextPageToken)
    }

    func postComment(videoID: String, channelID: String, text: String, parentID: String?, expected: UInt64) async throws -> YouTubeComment {
        let payload: Data
        let resource: String
        if let parentID {
            resource = "comments"
            payload = try YouTubeActionPayloads.reply(parentID: parentID, text: text)
        } else {
            resource = "commentThreads"
            payload = try YouTubeActionPayloads.comment(channelID: channelID, videoID: videoID, text: text)
        }
        let data = try await request(resource, parameters: ["part": "snippet"], method: "POST", body: payload, expected: expected)
        let response = try decoder.decode(YouTubeWireItem.self, from: data)
        guard let comment = parentID == nil ? YouTubeModelParser.topLevelComment(response) : YouTubeModelParser.reply(response) else { throw AccountError.invalidResponse }
        return comment
    }

    /// Returns false when the resource already exists; never manufactures a successful server write.
    func saveToPlaylist(videoID: String, playlistID: String, expected: UInt64) async throws -> Bool {
        let id = try YouTubeActionPolicy.videoID(videoID)
        let playlist = try YouTubeActionPolicy.playlistID(playlistID)
        let existing = try await page("playlistItems", parameters: ["part": "id", "playlistId": playlist, "videoId": id, "maxResults": "1"], expected: expected)
        guard existing.items.isEmpty else { return false }
        let data = try await request("playlistItems", parameters: ["part": "snippet"], method: "POST", body: YouTubeActionPayloads.playlistItem(playlistID: playlist, videoID: id), expected: expected)
        _ = try YouTubeActionPolicy.resourceID(decoder.decode(YouTubeWireItem.self, from: data).id)
        return true
    }

    func recentUploads(channelIDs: [String], expected: UInt64) async throws -> (videos: [YouTubeVideo], unavailable: Int) {
        guard !channelIDs.isEmpty else { return ([], 0) }
        guard channelIDs.count <= 12 else { throw AccountError.invalidValue("Zu viele Kanäle in einem Feed-Abschnitt.") }
        let identifiers = try channelIDs.map(YouTubeActionPolicy.channelID)
        let channelResponse = try await page("channels", parameters: ["part": "contentDetails", "id": identifiers.joined(separator: ","), "maxResults": "50"], expected: expected)
        let known = Set(identifiers)
        let uploadLists = channelResponse.items.filter { known.contains($0.id) }.compactMap { $0.contentDetails?.relatedPlaylists?.uploads }
        var unavailable = identifiers.count - uploadLists.count
        var videoIDs: [String] = []
        for offset in stride(from: 0, to: uploadLists.count, by: 4) {
            let batch = Array(uploadLists[offset..<min(offset + 4, uploadLists.count)])
            let results = try await withThrowingTaskGroup(of: ([String], Bool).self) { group in
                for playlist in batch {
                    group.addTask { [self] in
                        do { return (try await self.uploadVideoIDs(playlistID: playlist, expected: expected), false) }
                        catch AccountError.api(let code, let reason) where code == 404 || ["playlistNotFound", "playlistForbidden", "playlistOperationUnsupported"].contains(reason) { return ([], true) }
                    }
                }
                var values: [([String], Bool)] = []
                for try await value in group { values.append(value) }
                return values
            }
            videoIDs.append(contentsOf: results.flatMap { $0.0 })
            unavailable += results.filter { $0.1 }.count
        }
        let unique = Array(Set(videoIDs))
        guard !unique.isEmpty else { return ([], max(0, unavailable)) }
        let response = try await page("videos", parameters: ["part": "snippet", "id": unique.joined(separator: ",")], expected: expected)
        let videos = response.items.compactMap { YouTubeModelParser.video($0) }.filter { unique.contains($0.id) && known.contains($0.channelID) }
        return (videos.sorted { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }, max(0, unavailable))
    }

    private func uploadVideoIDs(playlistID: String, expected: UInt64) async throws -> [String] {
        let response = try await page("playlistItems", parameters: ["part": "contentDetails", "playlistId": YouTubeActionPolicy.playlistID(playlistID), "maxResults": "3"], expected: expected)
        return response.items.compactMap { $0.contentDetails?.videoId }.filter { (try? YouTubeActionPolicy.videoID($0)) != nil }
    }
}
