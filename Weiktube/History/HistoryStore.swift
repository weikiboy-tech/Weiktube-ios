// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Combine

struct HistoryEntry: Identifiable, Codable, Equatable, Sendable {
    let videoID: String
    var title: String
    var watchedAt: Date
    var position: Double
    var duration: Double
    /// Only explicit, validated public media URLs can populate this field.
    var directURL: URL?
    var id: String { directURL?.absoluteString ?? videoID }
    var url: URL { directURL ?? VideoLink(id: videoID).url }
    var progress: Double { duration > 0 && duration.isFinite && position.isFinite ? min(1, max(0, position / duration)) : 0 }
    var positionLabel: String { PlaybackTimeFormatter.string(position) }
    var thumbnailURL: URL? { YouTubeLinkRouter.validVideoID(videoID) ? URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg") : nil }
}

enum PlaybackTimeFormatter {
    static func string(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(min(seconds, 604_800))
        if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct HistoryDocument: Codable, Sendable {
    var version = 1
    var entries: [HistoryEntry]
    enum CodingKeys: String, CodingKey { case version, entries }
    init(entries: [HistoryEntry]) { self.entries = entries }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        entries = try values.decode([LossyHistoryEntry].self, forKey: .entries).compactMap(\.value)
    }
}

private struct LossyHistoryEntry: Decodable {
    let value: HistoryEntry?
    init(from decoder: Decoder) { value = try? HistoryEntry(from: decoder) }
}

/// Main-actor ordering plus a serial writer prevent a late progress save from undoing a clear.
@MainActor
final class HistoryStore: ObservableObject {
    static let limit = 100
    @Published private(set) var entries: [HistoryEntry] = []
    @Published private(set) var storageError: String?
    @Published private(set) var revision: UInt64 = 0
    @Published var enabled = true {
        didSet { if enabled != oldValue { revision &+= 1 } }
    }
    var recentEntries: [HistoryEntry] { Array(entries.prefix(12)) }
    private let file: AtomicJSONFile<HistoryDocument>?
    private let writer = DispatchQueue(label: "com.weiktube.history.persistence", qos: .utility)
    private var writeSequence: UInt64 = 0
    private let now: () -> Date

    init(fileURL: URL? = nil, enabled: Bool = true, now: @escaping () -> Date = Date.init) {
        self.enabled = enabled; self.now = now
        let target = fileURL ?? (try? PersistencePaths.applicationSupportDirectory().appendingPathComponent("history-v1.json"))
        if let target { file = AtomicJSONFile(url: target) } else { file = nil }
        do {
            guard let file else { throw LocalStorageError.unavailable }
            if let document = try file.read() {
                guard document.version == 1 else { throw LocalStorageError.invalidVersion }
                var seen = Set<String>()
                entries = document.entries.filter { entry in
                    let safe = entry.directURL.map(YouTubeLinkRouter.directMediaAllowed) ?? YouTubeLinkRouter.validVideoID(entry.videoID)
                    return safe && entry.title.count <= 200 && entry.position.isFinite && entry.position >= 0 &&
                        entry.duration.isFinite && entry.duration >= 0 && entry.watchedAt.timeIntervalSince1970.isFinite && seen.insert(entry.id).inserted
                }.prefix(Self.limit).map { entry in
                    var value = entry
                    if value.duration <= value.position { value.position = 0 }
                    return value
                }
            }
        } catch { storageError = "Der lokale Verlauf konnte nicht gelesen werden. \(error.localizedDescription)" }
    }

    /// Call for a deliberate video selection. Subsequent media callbacks must use updateProgress.
    func record(videoID: String, title: String = "", position: Double = 0, duration: Double = 0, expectedRevision: UInt64? = nil) {
        guard enabled, YouTubeLinkRouter.validVideoID(videoID), accepts(expectedRevision) else { return }
        let previous = entries.first { $0.videoID == videoID && $0.directURL == nil }
        var entry = HistoryEntry(videoID: videoID, title: cleanTitle(title, fallback: previous?.title ?? "Video"), watchedAt: now(),
                                 position: previous?.position ?? 0, duration: previous?.duration ?? 0, directURL: nil)
        applyProgress(to: &entry, position: position, duration: duration, ended: false)
        entries.removeAll { $0.id == videoID }
        entries.insert(entry, at: 0)
        entries = Array(entries.prefix(Self.limit))
        persist()
    }

    func record(route: MediaRoute, title: String = "", position: Double = 0, duration: Double = 0, expectedRevision: UInt64? = nil) {
        switch route {
        case .video(let video): record(videoID: video.id, title: title, position: position, duration: duration, expectedRevision: expectedRevision)
        case .directMedia(let url):
            guard enabled, accepts(expectedRevision), YouTubeLinkRouter.directMediaAllowed(url) else { return }
            let previous = entries.first { $0.directURL == url }
            let entry = HistoryEntry(videoID: "", title: cleanTitle(title, fallback: previous?.title ?? "HTTPS-Video"), watchedAt: now(),
                                     position: 0, duration: 0, directURL: url)
            entries.removeAll { $0.directURL == url }; entries.insert(entry, at: 0)
            entries = Array(entries.prefix(Self.limit)); persist()
        default: break // Shorts do not acquire normal-video resume semantics.
        }
    }

    /// No insertion and no reordering: late metadata cannot recreate cleared history.
    func updateProgress(videoID: String, title: String? = nil, position: Double, duration: Double,
                        ended: Bool = false, expectedRevision: UInt64? = nil, force: Bool = false) {
        guard enabled, accepts(expectedRevision), let index = entries.firstIndex(where: { $0.videoID == videoID && $0.directURL == nil }) else { return }
        var entry = entries[index]
        let old = entry
        if let title { entry.title = cleanTitle(title, fallback: entry.title) }
        if force || ended || abs(entry.position - position) >= 5 || entry.duration != duration {
            applyProgress(to: &entry, position: position, duration: duration, ended: ended)
        }
        guard entry != old else { return }
        entries[index] = entry; persist()
    }

    func resumePosition(for videoID: String) -> Double? {
        guard enabled, let value = entries.first(where: { $0.videoID == videoID && $0.directURL == nil }),
              value.position >= 1, value.position < value.duration else { return nil }
        return value.position
    }

    func resumePosition(for link: VideoLink) -> Double? { link.startSeconds ?? resumePosition(for: link.id) }

    func clearPosition(for videoID: String) {
        guard let index = entries.firstIndex(where: { $0.videoID == videoID && $0.directURL == nil }) else { return }
        entries[index].position = 0
        persist()
    }

    func remove(_ id: String) {
        revision &+= 1
        entries.removeAll { $0.id == id }; persist()
    }
    func remove(videoID: String) { remove(videoID) }

    func clear() {
        revision &+= 1
        entries.removeAll()
        persist()
    }

    /// Completes only after all preceding atomic writes. Useful before extension/testing handoff.
    func flush() async {
        await withCheckedContinuation { continuation in writer.async { continuation.resume() } }
    }

    private func accepts(_ expected: UInt64?) -> Bool { expected == nil || expected == revision }

    private func cleanTitle(_ title: String, fallback: String) -> String {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((cleaned.isEmpty ? fallback : cleaned).prefix(200))
    }

    private func applyProgress(to entry: inout HistoryEntry, position: Double, duration: Double, ended: Bool) {
        guard position.isFinite, duration.isFinite, duration > 0, position >= 0 else { return }
        if ended { entry.position = 0; entry.duration = duration; return }
        // Empty/loading samples and exact-end values do not destroy a useful saved position.
        guard position >= 1, position < duration else { return }
        entry.position = position; entry.duration = duration
    }

    private func persist() {
        guard let file else { storageError = LocalStorageError.unavailable.localizedDescription; return }
        writeSequence &+= 1
        let sequence = writeSequence
        let document = HistoryDocument(entries: entries)
        writer.async { [weak self] in
            let result = Result { try file.write(document) }
            Task { @MainActor [weak self] in
                guard let self, self.writeSequence == sequence else { return }
                switch result {
                case .success: self.storageError = nil
                case .failure: self.storageError = "Verlauf konnte nicht gespeichert werden. Bitte freien Speicher und Gerätesperre prüfen."
                }
            }
        }
    }
}
