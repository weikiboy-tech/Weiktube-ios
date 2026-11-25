// SPDX-License-Identifier: GPL-3.0-only
import Foundation

struct PlaybackRestorationSnapshot: Equatable, Sendable {
    let route: MediaRoute
    let position: Double
    let savedAt: Date
}

private struct PlaybackRestorationDocument: Codable {
    var version = 1
    let url: URL
    let position: Double
    let savedAt: Date
}

enum PlaybackRestorationError: Error, LocalizedError {
    case invalidRoute, invalidPosition
    var errorDescription: String? {
        switch self {
        case .invalidRoute: return "Diese Wiedergabe kann nicht sicher wiederhergestellt werden."
        case .invalidPosition: return "Die Wiedergabeposition ist ungültig."
        }
    }
}

/// Only an explicitly selected player session may be written by the caller.
/// Restoring is presentation-only: this store never opens a URL or starts playback.
@MainActor
final class PlaybackRestorationStore {
    static let maximumAge: TimeInterval = 7 * 24 * 60 * 60
    private let file: AtomicJSONFile<PlaybackRestorationDocument>?
    private let now: () -> Date
    private var lastSavedIdentity: String?
    private var lastSavedAt: Date?

    init(fileURL: URL? = nil, now: @escaping () -> Date = Date.init) {
        let target = fileURL ?? (try? PersistencePaths.applicationSupportDirectory().appendingPathComponent("playback-restoration-v1.json"))
        self.file = target.map { AtomicJSONFile(url: $0, maximumBytes: 16_384) }
        self.now = now
    }

    func load(historyEnabled: Bool) throws -> PlaybackRestorationSnapshot? {
        guard historyEnabled else { try clear(); return nil }
        guard let file else { throw LocalStorageError.unavailable }
        guard let document = try file.read() else { return nil }
        guard document.version == 1 else { throw LocalStorageError.invalidVersion }
        let time = now()
        guard document.savedAt.timeIntervalSince1970.isFinite,
              time.timeIntervalSince(document.savedAt) <= Self.maximumAge,
              document.savedAt.timeIntervalSince(time) <= 60,
              document.position.isFinite, (0...86_400).contains(document.position),
              let route = Self.validatedRoute(document.url) else {
            try clear()
            return nil
        }
        lastSavedIdentity = route.identity
        lastSavedAt = document.savedAt
        return PlaybackRestorationSnapshot(route: route, position: document.position, savedAt: document.savedAt)
    }

    /// Tiny atomic snapshots are serialized on the same actor as selection/close.
    /// Call force on pause/background if the latest sample must be flushed immediately.
    func store(route: MediaRoute, position: Double, historyEnabled: Bool, force: Bool = false) throws {
        guard historyEnabled else { try clear(); return }
        guard let file else { throw LocalStorageError.unavailable }
        guard let safe = Self.validatedRoute(route.url), !route.isShorts else { throw PlaybackRestorationError.invalidRoute }
        guard position.isFinite, (0...86_400).contains(position) else { throw PlaybackRestorationError.invalidPosition }
        let time = now()
        guard time.timeIntervalSince1970.isFinite else { throw PlaybackRestorationError.invalidPosition }
        if !force, lastSavedIdentity == safe.identity, let saved = lastSavedAt,
           (0..<5).contains(time.timeIntervalSince(saved)) { return }
        try file.write(PlaybackRestorationDocument(url: safe.url, position: position, savedAt: time))
        lastSavedIdentity = safe.identity
        lastSavedAt = time
    }

    /// Call on explicit close, history deletion, or disabling history.
    func clear() throws {
        guard let file else { throw LocalStorageError.unavailable }
        if FileManager.default.fileExists(atPath: file.url.path) { try FileManager.default.removeItem(at: file.url) }
        lastSavedIdentity = nil
        lastSavedAt = nil
    }

    private static func validatedRoute(_ url: URL) -> MediaRoute? {
        guard let route = YouTubeLinkRouter.route(url) else { return nil }
        switch route {
        case .video(let video):
            // Saved position is authoritative; original t= must not override the saved session.
            return .video(VideoLink(id: video.id, playlistID: video.playlistID, index: video.index))
        case .directMedia: return route
        default: return nil
        }
    }
}
