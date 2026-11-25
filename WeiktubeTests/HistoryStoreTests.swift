// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import Weiktube

final class HistoryStoreTests: XCTestCase {
    private let firstID = "dQw4w9WgXcQ"
    private let secondID = "ABCDEFGHIJK"

    private func temporaryFile() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WeiktubeHistoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("history.json")
    }

    @MainActor
    func testResumeSurvivesRestartButExplicitZeroOverridesIt() async throws {
        let file = try temporaryFile()
        let store = HistoryStore(fileURL: file)
        store.record(videoID: firstID, title: "A real title")
        store.updateProgress(videoID: firstID, position: 42, duration: 240)
        await store.flush()
        let reloaded = HistoryStore(fileURL: file)
        XCTAssertEqual(reloaded.resumePosition(for: firstID), 42)
        XCTAssertEqual(reloaded.resumePosition(for: VideoLink(id: firstID, startSeconds: 0)), 0)
        XCTAssertEqual(reloaded.resumePosition(for: VideoLink(id: firstID, startSeconds: 120)), 120)
        XCTAssertEqual(reloaded.entries.first?.positionLabel, "0:42")
        XCTAssertEqual(reloaded.entries.first?.title, "A real title")
    }

    @MainActor
    func testEmptyAndNonFiniteSamplesCannotEraseUsefulProgress() async throws {
        let store = HistoryStore(fileURL: try temporaryFile())
        store.record(videoID: firstID, title: "Video", position: 60, duration: 300)
        for sample in [(0.0, 0.0), (0.0, 300.0), (Double.nan, 300.0), (Double.infinity, 300.0), (300.0, 300.0)] {
            store.updateProgress(videoID: firstID, position: sample.0, duration: sample.1, force: true)
        }
        XCTAssertEqual(store.resumePosition(for: firstID), 60)
        await store.flush()
    }

    @MainActor
    func testConfirmedCompletionRemovesResumeEvenWhenFinalSampleResetToZero() async throws {
        let store = HistoryStore(fileURL: try temporaryFile())
        store.record(videoID: firstID, position: 42, duration: 100)
        store.updateProgress(videoID: firstID, position: 0, duration: 100, ended: true)
        XCTAssertNil(store.resumePosition(for: firstID))
        XCTAssertEqual(store.entries.count, 1)
        await store.flush()
    }

    @MainActor
    func testLateCallbacksCannotRecreateClearedHistoryOrAnOldPlaybackEpoch() async throws {
        let file = try temporaryFile()
        let store = HistoryStore(fileURL: file)
        store.record(videoID: firstID, title: "Old selection", position: 20, duration: 200)
        let oldRevision = store.revision
        store.clear()
        store.record(videoID: firstID, title: "Late callback", position: 70, duration: 200, expectedRevision: oldRevision)
        store.updateProgress(videoID: firstID, title: "Late metadata", position: 80, duration: 200, expectedRevision: oldRevision)
        XCTAssertTrue(store.entries.isEmpty)
        store.record(videoID: firstID, title: "New selection", position: 10, duration: 200, expectedRevision: store.revision)
        store.updateProgress(videoID: firstID, title: "Old epoch", position: 90, duration: 200, expectedRevision: oldRevision)
        XCTAssertEqual(store.entries.first?.title, "New selection")
        XCTAssertEqual(store.resumePosition(for: firstID), 10)
        await store.flush()
        XCTAssertEqual(HistoryStore(fileURL: file).entries, store.entries)
    }

    @MainActor
    func testProgressAndMetadataDoNotReorderSelections() async throws {
        let store = HistoryStore(fileURL: try temporaryFile())
        store.record(videoID: firstID, title: "First")
        store.record(videoID: secondID, title: "Second")
        store.updateProgress(videoID: firstID, title: "First resolved", position: 20, duration: 200)
        XCTAssertEqual(store.entries.map(\.videoID), [secondID, firstID])
        XCTAssertEqual(store.entries.last?.title, "First resolved")
        store.record(videoID: firstID) // Reopening preserves the resolved title.
        XCTAssertEqual(store.entries.first?.title, "First resolved")
        await store.flush()
    }

    @MainActor
    func testDisablingHistoryBlocksWritesResumeAndPriorEpochAfterReenable() async throws {
        let store = HistoryStore(fileURL: try temporaryFile())
        store.record(videoID: firstID, position: 20, duration: 200)
        let epoch = store.revision
        store.enabled = false
        store.record(videoID: secondID)
        store.updateProgress(videoID: firstID, position: 50, duration: 200)
        XCTAssertNil(store.resumePosition(for: firstID))
        XCTAssertEqual(store.entries.map(\.videoID), [firstID])
        store.enabled = true
        store.updateProgress(videoID: firstID, position: 80, duration: 200, expectedRevision: epoch)
        XCTAssertEqual(store.resumePosition(for: firstID), 20)
        await store.flush()
    }

    @MainActor
    func testHistoryIsBoundedDeduplicatedAndCarouselShowsTwelve() async throws {
        let store = HistoryStore(fileURL: try temporaryFile())
        for index in 0..<110 {
            store.record(videoID: String(format: "%011d", index), title: "Title \(index)")
        }
        XCTAssertEqual(store.entries.count, 100)
        XCTAssertEqual(store.recentEntries.count, 12)
        XCTAssertEqual(store.entries.first?.videoID, "00000000109")
        XCTAssertEqual(store.entries.last?.videoID, "00000000010")
        store.record(videoID: "00000000050")
        XCTAssertEqual(store.entries.count, 100)
        XCTAssertEqual(store.entries.first?.videoID, "00000000050")
        await store.flush()
    }

    @MainActor
    func testDirectMediaUsesValidatedURLIdentityAndShortsDoNotAcquireResume() async throws {
        let store = HistoryStore(fileURL: try temporaryFile())
        let safe = URL(string: "https://cdn.example.com/video.mp4")!
        store.record(route: .directMedia(safe), title: "Public film", position: 12, duration: 120)
        store.record(route: .directMedia(URL(string: "https://r1.googlevideo.com/video.mp4")!))
        store.record(route: .shorts(VideoLink(id: firstID)))
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.url, safe)
        XCTAssertEqual(store.entries.first?.id, safe.absoluteString)
        XCTAssertEqual(store.entries.first?.videoID, "")
        XCTAssertEqual(store.entries.first?.position, 0)
        XCTAssertNil(store.entries.first?.thumbnailURL)
        await store.flush()
    }

    @MainActor
    func testMalformedIndividualEntryDoesNotPoisonGoodHistory() async throws {
        let file = try temporaryFile()
        let good = HistoryEntry(videoID: firstID, title: "Retained", watchedAt: Date(), position: 20, duration: 200, directURL: nil)
        let encoded = try JSONEncoder().encode(good)
        let validObject = try JSONSerialization.jsonObject(with: encoded)
        let document: [String: Any] = ["version": 1, "entries": [["videoID": 123], "not an entry", validObject, validObject]]
        try JSONSerialization.data(withJSONObject: document).write(to: file, options: .atomic)
        let store = HistoryStore(fileURL: file)
        XCTAssertNil(store.storageError)
        XCTAssertEqual(store.entries, [good])
    }

    @MainActor
    func testRemoveAndClearPersistenceWinOverAlreadyQueuedSnapshots() async throws {
        let file = try temporaryFile()
        let store = HistoryStore(fileURL: file)
        store.record(videoID: firstID, position: 20, duration: 200)
        store.record(videoID: secondID)
        store.remove(firstID)
        store.clear()
        await store.flush()
        XCTAssertTrue(HistoryStore(fileURL: file).entries.isEmpty)
    }

    func testTimeFormattingHandlesHoursAndInvalidSamples() {
        XCTAssertEqual(PlaybackTimeFormatter.string(3723), "1:02:03")
        XCTAssertEqual(PlaybackTimeFormatter.string(61.9), "1:01")
        XCTAssertEqual(PlaybackTimeFormatter.string(-1), "0:00")
        XCTAssertEqual(PlaybackTimeFormatter.string(.nan), "0:00")
    }
}
