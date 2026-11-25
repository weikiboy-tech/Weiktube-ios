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
        case adRecoveryAttempt, mediaStateChanged, pauseRequested, sceneActive, sceneInactive, sceneBackground, surfaceAttached, surfaceDetached
    }
    struct Entry: Identifiable, Codable {
        let id: UUID
        let date: Date
        let event: Event
        let detail: String?
    }
    @Published private(set) var entries: [Entry] = []
    private var lastMediaState = ""
    enum PauseReason: String { case control, shorts, background, videoActions, adRecovery }
    func recordPause(_ reason: PauseReason) {
        append(.pauseRequested, detail: reason.rawValue)
    }
    func record(_ event: Event) { append(event, detail: nil) }

    private func append(_ event: Event, detail: String?) {
        entries.append(Entry(id: UUID(), date: Date(), event: event, detail: detail))
        if entries.count > 200 { entries.removeFirst(entries.count - 200) }
    }
    func recordMedia(_ sample:MediaSnapshot) {
        let state="event=\(sample.mediaEvent) ready=\(sample.readyState) network=\(sample.networkState) error=\(sample.mediaErrorCode) playing=\(sample.playing) muted=\(sample.muted) seeking=\(sample.seeking) ad=\(sample.advertisement) autoplayBlocked=\(sample.autoplayBlocked)"
        guard state != lastMediaState else{return};lastMediaState=state
        append(.mediaStateChanged, detail: state)
    }
    func clear() { entries.removeAll(); lastMediaState = "" }
    var report: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        return "Weiktube iOS \(version)\nLokal; keine URLs, Video-IDs, Cookies, Token oder Kontodaten.\n" +
        entries.map { "\($0.date.ISO8601Format()) \($0.event.rawValue)\($0.detail.map { " " + $0 } ?? "")" }.joined(separator: "\n")
    }
}
