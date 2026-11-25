// SPDX-License-Identifier: GPL-3.0-only
import XCTest
#if SWIFT_PACKAGE
@testable import WeiktubeCore
#else
@testable import Weiktube
#endif

final class PlaybackRestorationTests: XCTestCase {
    private func temporaryFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WeiktubeRestoreTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("session.json")
    }

    @MainActor
    func testRestartRestoresValidatedIdentityAndPositionSeparatelyFromOriginalTimestamp() async throws {
        let file = try temporaryFile()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let store = PlaybackRestorationStore(fileURL: file, now: { date })
        let route = MediaRoute.video(VideoLink(id: "dQw4w9WgXcQ", startSeconds: 5, playlistID: "PL_123", index: 3))
        try store.store(route: route, position: 72, historyEnabled: true)
        let restored = try PlaybackRestorationStore(fileURL: file, now: { date }).load(historyEnabled: true)
        XCTAssertEqual(restored?.route, .video(VideoLink(id: "dQw4w9WgXcQ", playlistID: "PL_123", index: 3)))
        XCTAssertEqual(restored?.position, 72)
        XCTAssertEqual(restored?.savedAt, date)
    }

    @MainActor
    func testDisabledHistoryAndExplicitCloseDeleteRestoration() async throws {
        let file = try temporaryFile()
        let store = PlaybackRestorationStore(fileURL: file)
        let route = MediaRoute.video(VideoLink(id: "dQw4w9WgXcQ"))
        try store.store(route: route, position: 12, historyEnabled: true)
        XCTAssertNil(try store.load(historyEnabled: false))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        try store.store(route: route, position: 12, historyEnabled: true)
        try store.clear()
        XCTAssertNil(try store.load(historyEnabled: true))
        try store.store(route: route, position: 12, historyEnabled: false)
        XCTAssertNil(try store.load(historyEnabled: true))
    }

    @MainActor
    func testOnlyExplicitSafePlayerRoutesAndFinitePositionsCanPersist() async throws {
        let store = PlaybackRestorationStore(fileURL: try temporaryFile())
        for route in [MediaRoute.home, .shorts(VideoLink(id: "dQw4w9WgXcQ")), .directMedia(URL(string: "https://r1.googlevideo.com/video.mp4")!)] {
            XCTAssertThrowsError(try store.store(route: route, position: 0, historyEnabled: true))
        }
        let route = MediaRoute.directMedia(URL(string: "https://cdn.example.com/video.mp4")!)
        for value in [Double.nan, .infinity, -1, 86_401] {
            XCTAssertThrowsError(try store.store(route: route, position: value, historyEnabled: true))
        }
        try store.store(route: route, position: 30, historyEnabled: true)
        XCTAssertEqual(try store.load(historyEnabled: true)?.route, route)
    }

    @MainActor
    func testStaleAndFutureSnapshotsCannotReopenOldPlayback() async throws {
        let file = try temporaryFile()
        let saved = Date(timeIntervalSince1970: 1_800_000_000)
        let route = MediaRoute.video(VideoLink(id: "dQw4w9WgXcQ"))
        let original = PlaybackRestorationStore(fileURL: file, now: { saved })
        try original.store(route: route, position: 12, historyEnabled: true)
        let expired = PlaybackRestorationStore(fileURL: file, now: { saved.addingTimeInterval(8 * 24 * 60 * 60) })
        XCTAssertNil(try expired.load(historyEnabled: true))
        try original.store(route: route, position: 12, historyEnabled: true, force: true)
        let earlierClock = PlaybackRestorationStore(fileURL: file, now: { saved.addingTimeInterval(-120) })
        XCTAssertNil(try earlierClock.load(historyEnabled: true))
    }

    @MainActor
    func testPeriodicWritesAreThrottledAndForcedPauseSaveKeepsLatestSample() async throws {
        let file = try temporaryFile()
        var date = Date(timeIntervalSince1970: 1_800_000_000)
        let store = PlaybackRestorationStore(fileURL: file, now: { date })
        let route = MediaRoute.video(VideoLink(id: "dQw4w9WgXcQ"))
        try store.store(route: route, position: 10, historyEnabled: true)
        date = date.addingTimeInterval(1)
        try store.store(route: route, position: 11, historyEnabled: true)
        XCTAssertEqual(try store.load(historyEnabled: true)?.position, 10)
        try store.store(route: route, position: 11, historyEnabled: true, force: true)
        XCTAssertEqual(try store.load(historyEnabled: true)?.position, 11)
    }
}
