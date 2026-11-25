// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CoreFoundation
import Combine

enum ReturnDislikeCodec {
    static func decode(_ data: Data, videoID: String) -> Int64? {
        guard SponsorCodec.validVideoID(videoID), data.count <= 65536,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["id"] as? String == videoID, (object["deleted"] as? Bool) != true,
              let count = object["dislikes"] as? NSNumber, CFGetTypeID(count) != CFBooleanGetTypeID() else { return nil }
        let value = count.doubleValue
        guard value.isFinite, value >= 0, value <= 1e12, value.rounded(.towardZero) == value else { return nil }
        return Int64(value)
    }
}

actor ReturnDislikeClient {
    private struct Value: Codable { let count: Int64? }
    private let defaults: UserDefaults
    private let transport = PublicServiceTransport(hosts: ["returnyoutubedislikeapi.com"])
    private var cache = PublicServiceCache<Value>(name: "return-dislike", limit: 200)
    private var nextRequest = Date.distantPast
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func get(_ videoID: String) async -> Int64? {
        guard SponsorCodec.validVideoID(videoID) else { return nil }
        let now = Date()
        if let value = cache.value(for: videoID, now: now) { return value.count }
        let day = Int(now.timeIntervalSince1970 / 86400)
        let count = defaults.integer(forKey: "ryd.day") == day ? defaults.integer(forKey: "ryd.requests") : 0
        guard count < 9500, defaults.double(forKey: "ryd.backoffUntil") <= now.timeIntervalSince1970 else { return nil }
        let reservation = max(nextRequest, now); nextRequest = reservation.addingTimeInterval(1.1)
        defaults.set(day, forKey: "ryd.day"); defaults.set(count + 1, forKey: "ryd.requests")
        do {
            let delay = reservation.timeIntervalSinceNow
            if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            try Task.checkCancellation()
            guard defaults.double(forKey: "ryd.backoffUntil") <= Date().timeIntervalSince1970 else { return nil }
            var c = URLComponents(string: "https://returnyoutubedislikeapi.com/votes")!
            c.queryItems = [.init(name: "videoId", value: videoID)]
            let response = try await transport.get(c.url!, limit: 65536, userAgent: "Weiktube-iOS/RYD-readonly")
            try Task.checkCancellation()
            if response.status == 429 {
                defaults.set(Date().addingTimeInterval(PublicServiceTransport.retryDelay(response.retryAfter, now: Date())).timeIntervalSince1970, forKey: "ryd.backoffUntil")
            }
            let value = response.status == 200 ? ReturnDislikeCodec.decode(response.data, videoID: videoID) : nil
            cache.insert(.init(count: value), for: videoID, ttl: value == nil ? 300 : 3600, now: Date())
            return value
        } catch {
            if !Task.isCancelled { cache.insert(.init(count: nil), for: videoID, ttl: 300, now: Date()) }
            return nil
        }
    }
    func clearCache() { cache.clear() }
}

@MainActor
final class ReturnDislikeService: ObservableObject {
    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: "player.dislikeEstimates")
            if !enabled { reset(); status = "Ausgeschaltet" }
        }
    }
    @Published private(set) var count: Int64?
    @Published private(set) var status = "Ausgeschaltet"
    @Published private(set) var videoID: String?
    private let defaults: UserDefaults
    private let client: ReturnDislikeClient
    private var task: Task<Int64?, Never>?
    private var generation = -1
    private var revision = UUID()
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults; client = ReturnDislikeClient(defaults: defaults)
        enabled = defaults.bool(forKey: "player.dislikeEstimates")
        if enabled { status = "Normales YouTube-Video öffnen" }
    }
    func load(videoID: String, generation: Int) async {
        guard enabled, SponsorCodec.validVideoID(videoID) else { reset(); return }
        if self.videoID == videoID && self.generation == generation { return }
        reset(); self.videoID = videoID; self.generation = generation
        let current = revision; status = "Schätzung wird geladen"
        let request = Task { await client.get(videoID) }; task = request
        let result = await withTaskCancellationHandler(operation: { await request.value }, onCancel: { request.cancel() })
        guard !Task.isCancelled, enabled, current == revision, self.videoID == videoID, self.generation == generation else { return }
        count = result; task = nil
        status = result == nil ? "Keine Schätzung verfügbar" : "Geschätzte Dislikes · Return YouTube Dislike"
    }
    func reset() { revision = UUID(); task?.cancel(); task = nil; count = nil; videoID = nil; generation = -1 }
    func clearCache() async { reset(); await client.clearCache(); status = "Cache geleert" }
}
