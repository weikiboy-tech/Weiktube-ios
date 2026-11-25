// SPDX-License-Identifier: GPL-3.0-only
import Foundation

struct YouTubePage<Item: Sendable>: Sendable {
    let items: [Item]
    let nextPageToken: String?
}

struct YouTubeChannel: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let description: String
    let thumbnailURL: URL?
    let uploadsPlaylistID: String?
}

struct YouTubeSubscription: Identifiable, Hashable, Sendable {
    let id: String
    let channelID: String
    let title: String
    let thumbnailURL: URL?
}

struct YouTubePlaylist: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let description: String
    let thumbnailURL: URL?
    let itemCount: Int
}

struct YouTubeVideo: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let channelID: String
    let channelTitle: String
    let thumbnailURL: URL?
    let publishedAt: Date?
}

struct YouTubePlaylistEntry: Identifiable, Sendable {
    let id: String
    let video: YouTubeVideo
}

struct YouTubeComment: Identifiable, Hashable, Sendable {
    let id: String
    let author: String
    let text: String
    let likeCount: Int
    let replyCount: Int
    let parentID: String?
}

enum YouTubeRating: String, Codable, CaseIterable, Sendable {
    case like, dislike, none, unspecified
}

struct YouTubeRatingResponse: Decodable {
    struct Item: Decodable {
        let videoId: String
        let rating: YouTubeRating
    }
    let items: [Item]

    func rating(for videoID: String) throws -> YouTubeRating {
        guard let value = items.first(where: { $0.videoId == videoID }) else { throw AccountError.invalidResponse }
        return value.rating
    }
}

// Typed wire responses remain separate from UI models. Missing resources are not fabricated.
struct YouTubeWirePage: Decodable {
    let items: [YouTubeWireItem]
    let nextPageToken: String?
}

struct YouTubeWireItem: Decodable {
    let id: String
    let snippet: YouTubeWireSnippet?
    let contentDetails: YouTubeWireContentDetails?
    let rating: YouTubeRating?
}

struct YouTubeWireContentDetails: Decodable {
    struct Related: Decodable { let uploads: String? }
    let relatedPlaylists: Related?
    let videoId: String?
    let videoPublishedAt: String?
    let itemCount: Int?
}

struct YouTubeWireSnippet: Decodable {
    struct Resource: Decodable { let channelId: String?; let videoId: String? }
    let title: String?
    let description: String?
    let channelId: String?
    let channelTitle: String?
    let videoOwnerChannelId: String?
    let videoOwnerChannelTitle: String?
    let publishedAt: String?
    let thumbnails: [String: YouTubeWireThumbnail]?
    let resourceId: Resource?
    let topLevelComment: YouTubeWireComment?
    let totalReplyCount: Int?
    let authorDisplayName: String?
    let textOriginal: String?
    let textDisplay: String?
    let likeCount: Int?
    let parentId: String?
}

struct YouTubeWireThumbnail: Decodable { let url: String? }
struct YouTubeWireComment: Decodable {
    let id: String
    let snippet: YouTubeWireCommentSnippet
}
struct YouTubeWireCommentSnippet: Decodable {
    let authorDisplayName: String?
    let textOriginal: String?
    let textDisplay: String?
    let likeCount: Int?
    let parentId: String?
}

enum YouTubeModelParser {
    static func thumbnail(_ values: [String: YouTubeWireThumbnail]?) -> URL? {
        for key in ["medium", "high", "default"] {
            if let value = values?[key]?.url, let url = URL(string: value), url.scheme == "https",
               url.user == nil, url.password == nil { return url }
        }
        return nil
    }

    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: value)
    }

    static func channel(_ item: YouTubeWireItem) -> YouTubeChannel? {
        guard let snippet = item.snippet, (try? YouTubeActionPolicy.channelID(item.id)) != nil else { return nil }
        return YouTubeChannel(id: item.id, title: String((snippet.title ?? "YouTube-Kanal").prefix(300)),
                              description: String((snippet.description ?? "").prefix(500)),
                              thumbnailURL: thumbnail(snippet.thumbnails), uploadsPlaylistID: item.contentDetails?.relatedPlaylists?.uploads)
    }

    static func subscription(_ item: YouTubeWireItem) -> YouTubeSubscription? {
        guard let snippet = item.snippet, let channel = snippet.resourceId?.channelId,
              (try? YouTubeActionPolicy.channelID(channel)) != nil,
              (try? YouTubeActionPolicy.resourceID(item.id)) != nil else { return nil }
        return YouTubeSubscription(id: item.id, channelID: channel,
                                   title: String((snippet.title ?? "YouTube-Kanal").prefix(300)), thumbnailURL: thumbnail(snippet.thumbnails))
    }

    static func playlist(_ item: YouTubeWireItem) -> YouTubePlaylist? {
        guard let snippet = item.snippet, (try? YouTubeActionPolicy.playlistID(item.id)) != nil else { return nil }
        return YouTubePlaylist(id: item.id, title: String((snippet.title ?? "Playlist").prefix(300)),
                               description: String((snippet.description ?? "").prefix(500)), thumbnailURL: thumbnail(snippet.thumbnails),
                               itemCount: max(0, item.contentDetails?.itemCount ?? 0))
    }

    static func video(_ item: YouTubeWireItem, isPlaylistItem: Bool = false) -> YouTubeVideo? {
        guard let snippet = item.snippet else { return nil }
        let id = isPlaylistItem ? (item.contentDetails?.videoId ?? snippet.resourceId?.videoId ?? "") : item.id
        guard (try? YouTubeActionPolicy.videoID(id)) != nil else { return nil }
        let channelID = isPlaylistItem ? (snippet.videoOwnerChannelId ?? snippet.channelId ?? "") : (snippet.channelId ?? "")
        let channelTitle = isPlaylistItem ? (snippet.videoOwnerChannelTitle ?? snippet.channelTitle ?? "") : (snippet.channelTitle ?? "")
        guard (try? YouTubeActionPolicy.channelID(channelID)) != nil else { return nil }
        return YouTubeVideo(id: id, title: String((snippet.title ?? "YouTube-Video").prefix(300)),
                            channelID: channelID, channelTitle: channelTitle,
                            thumbnailURL: thumbnail(snippet.thumbnails),
                            publishedAt: date(item.contentDetails?.videoPublishedAt ?? snippet.publishedAt))
    }

    static func topLevelComment(_ item: YouTubeWireItem) -> YouTubeComment? {
        guard let comment = item.snippet?.topLevelComment,
              (try? YouTubeActionPolicy.resourceID(comment.id)) != nil else { return nil }
        return YouTubeComment(id: comment.id, author: comment.snippet.authorDisplayName ?? "YouTube-Nutzer",
                              text: comment.snippet.textOriginal ?? comment.snippet.textDisplay ?? "",
                              likeCount: max(0, comment.snippet.likeCount ?? 0), replyCount: max(0, item.snippet?.totalReplyCount ?? 0), parentID: nil)
    }

    static func reply(_ item: YouTubeWireItem) -> YouTubeComment? {
        guard let snippet = item.snippet, (try? YouTubeActionPolicy.resourceID(item.id)) != nil else { return nil }
        return YouTubeComment(id: item.id, author: snippet.authorDisplayName ?? "YouTube-Nutzer",
                              text: snippet.textOriginal ?? snippet.textDisplay ?? "",
                              likeCount: max(0, snippet.likeCount ?? 0), replyCount: 0, parentID: snippet.parentId)
    }
}
