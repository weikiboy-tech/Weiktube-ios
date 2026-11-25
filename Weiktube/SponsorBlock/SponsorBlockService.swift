// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Combine

actor SponsorBlockClient {
    struct Result: Codable { let segments: [SponsorSegment]; let available: Bool }
    private let transport = PublicServiceTransport(hosts: ["sponsor.ajay.app"])
    private var cache = PublicServiceCache<Result>(name: "sponsorblock", limit: 64)
    private let defaults: UserDefaults
    private var nextRequest = Date.distantPast
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func get(_ videoID: String) async -> Result {
        guard let url = SponsorCodec.url(for: videoID) else { return .init(segments: [], available: false) }
        let now = Date()
        if let value = cache.value(for: videoID, now: now) { return value }
        guard defaults.double(forKey: "sponsor.backoffUntil") <= now.timeIntervalSince1970 else { return .init(segments: [], available: false) }
        let reservation = max(nextRequest, now)
        nextRequest = reservation.addingTimeInterval(1.1)
        do {
            let delay = reservation.timeIntervalSinceNow
            if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            try Task.checkCancellation()
            guard defaults.double(forKey: "sponsor.backoffUntil") <= Date().timeIntervalSince1970 else { return .init(segments: [], available: false) }
            let response = try await transport.get(url, limit: 2_097_152, userAgent: "Weiktube-iOS/SponsorBlock-readonly")
            try Task.checkCancellation()
            var segments: [SponsorSegment]?
            if response.status == 200 { segments = try? SponsorCodec.decode(response.data, videoID: videoID) }
            if response.status == 404 { segments = [] }
            if response.status == 429 || response.status >= 500 {
                let failures = min(6, defaults.integer(forKey: "sponsor.failures") + 1)
                let delay = response.status == 429 ? PublicServiceTransport.retryDelay(response.retryAfter, now: now) : min(3600, 60 * pow(2, Double(failures - 1)))
                defaults.set(failures, forKey: "sponsor.failures")
                defaults.set(Date().addingTimeInterval(delay).timeIntervalSince1970, forKey: "sponsor.backoffUntil")
            } else if segments != nil { defaults.set(0, forKey: "sponsor.failures") }
            let value = Result(segments: segments ?? [], available: segments != nil)
            cache.insert(value, for: videoID, ttl: segments == nil ? 300 : (segments!.isEmpty ? 1800 : 21600), now: Date())
            return value
        } catch is CancellationError {
            return .init(segments: [], available: false)
        } catch {
            if Task.isCancelled { return .init(segments: [], available: false) }
            let failure = Result(segments: [], available: false)
            cache.insert(failure, for: videoID, ttl: 300, now: Date())
            let failures = min(6, defaults.integer(forKey: "sponsor.failures") + 1)
            defaults.set(failures, forKey: "sponsor.failures")
            defaults.set(Date().addingTimeInterval(min(3600, 60 * pow(2, Double(failures - 1)))).timeIntervalSince1970, forKey: "sponsor.backoffUntil")
            return failure
        }
    }
    func clearCache() { cache.clear() } // Deliberately retains rate-limit/backoff state.
}

struct SponsorStatistics: Codable, Equatable {
    var count = 0
    var seconds: Double = 0
    var categories: [String: Int] = [:]
}

@MainActor
final class SponsorBlockService: ObservableObject {
    @Published var settings: SponsorSettings {
        didSet {
            if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: "sponsor.settings") }
            playback.settings = settings
            if !settings.enabled { cancelActive(); status = "Ausgeschaltet" }
        }
    }
    @Published private(set) var segments: [SponsorSegment] = []
    @Published private(set) var manualPrompt: SponsorPrompt?
    @Published private(set) var notice: SponsorSeekRequest?
    @Published private(set) var status = "Ausgeschaltet"
    @Published private(set) var statistics: SponsorStatistics
    var enabled: Bool {
        get { settings.enabled }
        set { settings.enabled = newValue }
    }
    private let defaults: UserDefaults
    private let client: SponsorBlockClient
    private var playback = SponsorPlaybackState()
    private var loadTask: Task<SponsorBlockClient.Result, Never>?
    private var revision = UUID()
    private var counted: [UUID: (SponsorCategory, Double)] = [:]
    private var countedOrder: [UUID] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults; self.client = SponsorBlockClient(defaults: defaults)
        settings = defaults.data(forKey: "sponsor.settings").flatMap { try? JSONDecoder().decode(SponsorSettings.self, from: $0) } ?? .init()
        statistics = defaults.data(forKey: "sponsor.statistics").flatMap { try? JSONDecoder().decode(SponsorStatistics.self, from: $0) } ?? .init()
        if !statistics.seconds.isFinite || statistics.seconds < 0 || statistics.count < 0 { statistics = .init() }
        status = settings.enabled ? "Normales YouTube-Video öffnen" : "Ausgeschaltet"
    }
    func load(videoID: String, generation: Int) async {
        guard enabled, SponsorCodec.validVideoID(videoID) else { cancelActive(); return }
        if playback.videoID == videoID && playback.generation == generation { return }
        cancelActive()
        playback.reset(videoID: videoID, generation: generation); playback.settings = settings
        let requestRevision = revision
        status = "Segmente werden geladen"
        let task = Task { await client.get(videoID) }; loadTask = task
        let response = await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
        guard !Task.isCancelled, requestRevision == revision, enabled,
              playback.videoID == videoID, playback.generation == generation else { return }
        loadTask = nil; segments = response.segments; playback.segments = response.segments
        status = !response.available ? "SponsorBlock nicht verfügbar – normale Wiedergabe" : response.segments.isEmpty ? "Keine überspringbaren Abschnitte bekannt" : "\(response.segments.count) Community-Abschnitte geladen"
    }
    func update(position: Double, duration: Double, videoID: String, generation: Int,
                isPlaying: Bool = true, isSeeking: Bool = false, isLive: Bool = false, isAdvertisement: Bool = false) -> SponsorSeekRequest? {
        playback.settings = settings
        let result = playback.update(position: position, duration: duration, videoID: videoID, generation: generation,
                                     isPlaying: isPlaying, isSeeking: isSeeking, isLive: isLive, isAdvertisement: isAdvertisement)
        if manualPrompt != playback.manualPrompt { manualPrompt = playback.manualPrompt }
        if let notice, Date().timeIntervalSince(notice.issuedAt) > 8 { self.notice = nil }
        return result
    }
    func completeSeek(request: SponsorSeekRequest, actualPosition: Double) {
        guard enabled, let confirmed = playback.complete(request, actualPosition: actualPosition) else { return }
        if let previous = confirmed.undoOf { reverseCount(previous); notice = nil; return }
        guard counted[confirmed.id] == nil else { return }
        let seconds = confirmed.to - confirmed.from
        guard seconds.isFinite, seconds > 0, seconds <= 604800 else { return }
        counted[confirmed.id] = (confirmed.category, seconds); countedOrder.append(confirmed.id)
        while countedOrder.count > 512 { counted.removeValue(forKey: countedOrder.removeFirst()) }
        statistics.count += 1; statistics.seconds += seconds
        statistics.categories[confirmed.category.rawValue, default: 0] += 1
        saveStatistics(); notice = settings.notices ? confirmed : nil
    }
    func skipManual() -> SponsorSeekRequest? { playback.skipManual() }
    func undo() -> SponsorSeekRequest? { playback.undo() }
    /// User intent cancels pending automation; only userSeek(to:) with an actual
    /// confirmed landing can roll back an already counted skip.
    func cancelPendingForUserSeek() {
        playback.cancelPendingForUserSeek()
        manualPrompt = nil; notice = nil
    }
    func userSeek(to position: Double) {
        if let id = playback.userSeek(to: position) { reverseCount(id) }
        manualPrompt = nil; notice = nil
    }
    func reset() { cancelActive(); status = enabled ? "Normales YouTube-Video öffnen" : "Ausgeschaltet" }
    func resetStatistics() {
        counted.removeAll(); countedOrder.removeAll(); statistics = .init()
        // In-flight seeks from before reset must not be counted after reset.
        playback.cancelPendingForUserSeek(); notice = nil; saveStatistics()
    }
    func clearCache() async {
        cancelActive(); await client.clearCache(); status = "Cache geleert"
    }
    private func cancelActive() {
        revision = UUID(); loadTask?.cancel(); loadTask = nil
        playback.reset(); segments = []; manualPrompt = nil; notice = nil
    }
    private func reverseCount(_ id: UUID) {
        guard let (category, seconds) = counted.removeValue(forKey: id) else { return }
        statistics.count = max(0, statistics.count - 1); statistics.seconds = max(0, statistics.seconds - seconds)
        statistics.categories[category.rawValue] = max(0, statistics.categories[category.rawValue, default: 0] - 1)
        saveStatistics()
    }
    private func saveStatistics() {
        if let data = try? JSONEncoder().encode(statistics) { defaults.set(data, forKey: "sponsor.statistics") }
    }
}
