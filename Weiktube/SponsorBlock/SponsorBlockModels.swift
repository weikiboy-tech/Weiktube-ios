// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CoreFoundation
import CryptoKit

enum SponsorMode: String, Codable, CaseIterable, Identifiable {
    case auto, manual, off
    var id: String { rawValue }
    var title: String { switch self { case .auto: return "Automatisch"; case .manual: return "Manuell"; case .off: return "Deaktiviert" } }
}

enum SponsorCategory: String, Codable, CaseIterable, Identifiable {
    case sponsor, selfpromo, interaction, intro, outro, preview
    case musicOfftopic = "music_offtopic"
    case filler
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sponsor: return "Sponsor"
        case .selfpromo: return "Eigenwerbung"
        case .interaction: return "Like-/Abo-Aufruf"
        case .intro: return "Intro"
        case .outro: return "Outro"
        case .preview: return "Vorschau/Rückblick"
        case .musicOfftopic: return "Musikfremder Abschnitt"
        case .filler: return "Füllmaterial"
        }
    }
    var colorHex: UInt32 {
        switch self {
        case .sponsor: return 0x00D400
        case .selfpromo: return 0xFFFF00
        case .interaction: return 0xCC00FF
        case .intro: return 0x00FFFF
        case .outro: return 0x0202ED
        case .preview: return 0x008FD6
        case .musicOfftopic: return 0xFF9900
        case .filler: return 0x7300FF
        }
    }
    var defaultMode: SponsorMode {
        switch self {
        case .sponsor, .selfpromo, .interaction: return .auto
        case .intro, .outro: return .manual
        case .preview, .musicOfftopic, .filler: return .off
        }
    }
}

struct SponsorSettings: Codable, Equatable {
    var enabled = false
    var markers = true
    var notices = true
    var showStatistics = true
    var modes = Dictionary(uniqueKeysWithValues: SponsorCategory.allCases.map { ($0.rawValue, $0.defaultMode) })
    func mode(for category: SponsorCategory) -> SponsorMode { modes[category.rawValue] ?? category.defaultMode }
}

struct SponsorSegment: Codable, Equatable, Identifiable {
    let start: Double
    let end: Double
    let category: SponsorCategory
    let id: String
    let videoDuration: Double
    let votes: Int
    let locked: Bool
    func valid(for duration: Double) -> Bool {
        duration.isFinite && duration > 0 && start.isFinite && end.isFinite && start >= 0 &&
        end > start && end <= duration + 0.05 && (videoDuration == 0 || abs(videoDuration - duration) <= 1)
    }
}

enum SponsorCodec {
    static func validVideoID(_ id: String) -> Bool {
        id.utf8.count == 11 && id.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil
    }
    static func prefix(for id: String) -> String? {
        guard validVideoID(id) else { return nil }
        return SHA256.hash(data: Data(id.utf8)).prefix(2).map { String(format: "%02x", $0) }.joined()
    }
    static func url(for id: String) -> URL? {
        guard let prefix = prefix(for: id) else { return nil }
        var c = URLComponents(string: "https://sponsor.ajay.app/api/skipSegments/\(prefix)")!
        let categories = String(data: try! JSONEncoder().encode(SponsorCategory.allCases.map(\.rawValue)), encoding: .utf8)!
        c.queryItems = [.init(name: "categories", value: categories), .init(name: "actionType", value: "skip"), .init(name: "service", value: "YouTube")]
        return c.url
    }
    /// Decode only exact members of the k-anonymity bucket. Invalid individual records are discarded.
    static func decode(_ data: Data, videoID: String) throws -> [SponsorSegment] {
        guard validVideoID(videoID), data.count <= 2_097_152,
              let bucket = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], bucket.count <= 2048 else { throw PublicServiceError.invalidResponse }
        var result: [SponsorSegment] = []
        var seen = Set<String>()
        for member in bucket where member["videoID"] as? String == videoID {
            guard let segments = member["segments"] as? [[String: Any]], segments.count <= 512 else { throw PublicServiceError.invalidResponse }
            for value in segments {
                guard value["actionType"] as? String == "skip",
                      let category = (value["category"] as? String).flatMap(SponsorCategory.init(rawValue:)),
                      let times = value["segment"] as? [NSNumber], times.count == 2,
                      CFGetTypeID(times[0]) != CFBooleanGetTypeID(), CFGetTypeID(times[1]) != CFBooleanGetTypeID(),
                      let duration = value["videoDuration"] as? NSNumber, CFGetTypeID(duration) != CFBooleanGetTypeID(),
                      let id = value["UUID"] as? String, id.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil else { continue }
                let start = times[0].doubleValue, end = times[1].doubleValue, total = duration.doubleValue
                guard start.isFinite, end.isFinite, total.isFinite, start >= 0, end > start, end <= 604800,
                      total >= 0, total <= 604800, total == 0 || end <= total + 1, seen.insert(id).inserted else { continue }
                result.append(.init(start: start, end: end, category: category, id: id, videoDuration: total,
                                    votes: (value["votes"] as? NSNumber)?.intValue ?? 0,
                                    locked: ((value["locked"] as? NSNumber)?.intValue ?? 0) > 0))
            }
        }
        return Array(result.sorted { ($0.start, $0.end) < ($1.start, $1.end) }.prefix(512))
    }
}

struct SponsorPrompt: Equatable {
    let category: SponsorCategory
    let segmentIDs: [String]
    let end: Double
}

struct SponsorSeekRequest: Equatable, Identifiable {
    let id: UUID
    let videoID: String
    let generation: Int
    let from: Double
    let to: Double
    let category: SponsorCategory
    let segmentIDs: [String]
    let undoOf: UUID?
    let issuedAt: Date
    var target: Double { to }
    var seconds: Double { max(0, to - from) }
}

/// This state machine never controls playback. The owner performs a seek and acknowledges its result.
struct SponsorPlaybackState {
    private(set) var videoID = ""
    private(set) var generation = -1
    var segments: [SponsorSegment] = []
    var settings = SponsorSettings()
    private(set) var manualPrompt: SponsorPrompt?
    private(set) var pending: SponsorSeekRequest?
    private(set) var lastConfirmed: SponsorSeekRequest?
    private(set) var attempted = Set<String>()
    private(set) var suppressed = Set<String>()
    private var position: Double = 0
    private var duration: Double = 0

    mutating func reset(videoID: String = "", generation: Int = -1) {
        self = .init(); self.videoID = videoID; self.generation = generation
    }
    mutating func update(position: Double, duration: Double, videoID: String, generation: Int,
                         isPlaying: Bool, isSeeking: Bool, isLive: Bool, isAdvertisement: Bool, now: Date = Date()) -> SponsorSeekRequest? {
        guard self.videoID == videoID, self.generation == generation else { return nil }
        if let pending, now.timeIntervalSince(pending.issuedAt) > 2 { self.pending = nil }
        guard settings.enabled, position.isFinite, position >= 0, duration.isFinite, duration > 0,
              !isLive, !isAdvertisement, !isSeeking else { manualPrompt = nil; return nil }
        self.position = position; self.duration = duration
        manualPrompt = group(at: position, mode: .manual)
        guard isPlaying, !isSeeking, pending == nil, let group = group(at: position, mode: .auto) else { return nil }
        return request(group, now: now)
    }
    private func group(at position: Double, mode wanted: SponsorMode) -> SponsorPrompt? {
        let eligible = segments.filter { segment in
            guard segment.valid(for: duration) else { return false }
            let configured = settings.mode(for: segment.category)
            let mode = configured == .auto && segment.videoDuration == 0 ? SponsorMode.manual : configured
            return mode == wanted && (wanted != .auto || (!attempted.contains(segment.id) && !suppressed.contains(segment.id)))
        }
        guard let first = eligible.first(where: { position >= $0.start && position < $0.end - 0.04 }) else { return nil }
        var selected = [first], end = first.end
        var changed = true
        while changed {
            changed = false
            for segment in eligible where !selected.contains(where: { $0.id == segment.id }) && segment.start <= end + 0.02 && segment.end > position {
                selected.append(segment); end = max(end, segment.end); changed = true
            }
        }
        return .init(category: first.category, segmentIDs: selected.map(\.id), end: min(end, duration))
    }
    private mutating func request(_ group: SponsorPrompt, now: Date) -> SponsorSeekRequest? {
        guard pending == nil, group.end > position + 0.04 else { return nil }
        let value = SponsorSeekRequest(id: UUID(), videoID: videoID, generation: generation, from: position, to: group.end,
                                       category: group.category, segmentIDs: group.segmentIDs, undoOf: nil, issuedAt: now)
        attempted.formUnion(group.segmentIDs); pending = value; manualPrompt = nil
        return value
    }
    mutating func skipManual(now: Date = Date()) -> SponsorSeekRequest? {
        guard settings.enabled, let group = manualPrompt else { return nil }
        return request(group, now: now)
    }
    mutating func undo(now: Date = Date()) -> SponsorSeekRequest? {
        guard settings.enabled, pending == nil, let previous = lastConfirmed,
              now.timeIntervalSince(previous.issuedAt) < 12 else { return nil }
        suppressed.formUnion(previous.segmentIDs)
        let value = SponsorSeekRequest(id: UUID(), videoID: videoID, generation: generation, from: position, to: previous.from,
                                       category: previous.category, segmentIDs: previous.segmentIDs, undoOf: previous.id, issuedAt: now)
        pending = value; return value
    }
    /// Successful acknowledgment only. A command being sent is never counted as a skip.
    mutating func complete(_ request: SponsorSeekRequest, actualPosition: Double, now: Date = Date()) -> SponsorSeekRequest? {
        guard request == pending, request.videoID == videoID, request.generation == generation else { return nil }
        pending = nil
        guard actualPosition.isFinite, abs(actualPosition - request.to) <= 0.35,
              now.timeIntervalSince(request.issuedAt) <= 2 else { return nil }
        position = actualPosition
        lastConfirmed = request.undoOf == nil ? request : nil
        return request
    }
    /// Retire an outstanding skip when the user starts seeking. This is not a landing
    /// acknowledgment and must not change the last confirmed skip or its statistics.
    mutating func cancelPendingForUserSeek() {
        pending = nil; manualPrompt = nil
    }
    mutating func userSeek(to position: Double) -> UUID? {
        cancelPendingForUserSeek()
        suppressed.formUnion(segments.filter { position >= $0.start && position < $0.end }.map(\.id))
        guard let previous = lastConfirmed, position >= previous.from, position < previous.to else { return nil }
        lastConfirmed = nil; return previous.id
    }
}
