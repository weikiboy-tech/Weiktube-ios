// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import Combine

@MainActor
final class DiagnosticsStore: ObservableObject {
    static let shared = DiagnosticsStore()
    enum Event: String, Codable {
        case navigationFailure, webProcessTerminated, playerSelected, playerClosed, seekRejected
        case playbackOwnershipChanged, fullscreenEntered, fullscreenExited, pipEntered, pipExited
        case persistenceFailure, importRejected
        case adRecoveryAttempt, mediaStateChanged
    }
    struct Entry: Identifiable, Codable {
        let id: UUID
        let date: Date
        let event: Event
        let detail: String?
    }
    @Published private(set) var entries: [Entry] = []
    private var lastMediaState = ""
    func record(_ event: Event) {
        entries.append(Entry(id: UUID(), date: Date(), event: event,detail:nil))
        if entries.count > 200 { entries.removeFirst(entries.count - 200) }
    }
    func recordMedia(_ sample:MediaSnapshot) {
        let state="event=\(sample.mediaEvent) ready=\(sample.readyState) network=\(sample.networkState) error=\(sample.mediaErrorCode) playing=\(sample.playing) seeking=\(sample.seeking) ad=\(sample.advertisement) autoplayBlocked=\(sample.autoplayBlocked)"
        guard state != lastMediaState else{return};lastMediaState=state
        entries.append(Entry(id:UUID(),date:Date(),event:.mediaStateChanged,detail:state))
        if entries.count>200 {entries.removeFirst(entries.count-200)}
    }
    func clear() { entries.removeAll() }
    var report: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        return "Weiktube iOS \(version)\nLokal; keine URLs, Video-IDs, Cookies, Token oder Kontodaten.\n" +
        entries.map { "\($0.date.ISO8601Format()) \($0.event.rawValue)\($0.detail.map { " " + $0 } ?? "")" }.joined(separator: "\n")
    }
}
