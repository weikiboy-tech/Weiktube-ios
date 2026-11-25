// SPDX-License-Identifier: GPL-3.0-only
import XCTest
#if SWIFT_PACKAGE
@testable import WeiktubeCore
#else
@testable import Weiktube
#endif

final class SharedLinkInboxTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WeiktubeInboxTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    func testExtensionDeliveryIsCanonicalAndDeduplicatedAcrossInstances() async throws {
        let directory = try temporaryDirectory()
        let extensionInbox = SharedLinkInbox(containerURL: directory)
        let appInbox = SharedLinkInbox(containerURL: directory)
        let first = try await extensionInbox.enqueue("https://youtu.be/dQw4w9WgXcQ?t=0&si=tracking")
        let duplicate = try await appInbox.enqueue("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=0")
        XCTAssertEqual(first.id, duplicate.id)
        let pending = try await appInbox.pending()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.url.absoluteString, "https://m.youtube.com/watch?v=dQw4w9WgXcQ&t=0")
        let reloaded = try await SharedLinkInbox(containerURL: directory).pending()
        XCTAssertEqual(reloaded, pending)
    }

    func testAcknowledgingKnownItemsDoesNotLoseAnInterveningExtensionDelivery() async throws {
        let directory = try temporaryDirectory()
        let app = SharedLinkInbox(containerURL: directory)
        let share = SharedLinkInbox(containerURL: directory)
        let first = try await share.enqueue("https://youtu.be/dQw4w9WgXcQ")
        let observed = try await app.pending()
        XCTAssertEqual(observed.map(\.id), [first.id])
        let second = try await share.enqueue("https://youtu.be/ABCDEFGHIJK")
        try await app.acknowledge(Set(observed.map(\.id)))
        let remaining = try await app.pending()
        XCTAssertEqual(remaining.map(\.id), [second.id])
        let drained = try await app.drain()
        XCTAssertEqual(drained, [second.url])
        let empty = try await share.pending()
        XCTAssertTrue(empty.isEmpty)
    }

    func testUnacknowledgedLinkSurvivesAppRestart() async throws {
        let directory = try temporaryDirectory()
        let original = SharedLinkInbox(containerURL: directory)
        let saved = try await original.enqueue("https://www.youtube.com/shorts/dQw4w9WgXcQ")
        _ = try await original.pending() // Reading alone is not a destructive consume.
        let restarted = SharedLinkInbox(containerURL: directory)
        let pending = try await restarted.pending()
        XCTAssertEqual(pending, [saved])
        try await restarted.acknowledge([saved.id])
        let remaining = try await original.pending()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testConcurrentAppAndExtensionWritersDoNotLoseEitherDelivery() async throws {
        let directory = try temporaryDirectory()
        let app = SharedLinkInbox(containerURL: directory)
        let share = SharedLinkInbox(containerURL: directory)
        async let first = app.enqueue("https://youtu.be/dQw4w9WgXcQ")
        async let second = share.enqueue("https://youtu.be/ABCDEFGHIJK")
        let saved = try await [first, second]
        let pending = try await app.pending()
        XCTAssertEqual(Set(pending.map(\.id)), Set(saved.map(\.id)))
    }

    func testQueueBoundAndExpiry() async throws {
        let directory = try temporaryDirectory()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let inbox = SharedLinkInbox(containerURL: directory, now: { date })
        for index in 0..<25 { try await inbox.enqueue("https://cdn.example.com/\(index).mp4") }
        let items = try await inbox.pending()
        XCTAssertEqual(items.count, 20)
        XCTAssertEqual(items.first?.url.lastPathComponent, "5.mp4")
        let expired = SharedLinkInbox(containerURL: directory, now: { date.addingTimeInterval(8 * 24 * 60 * 60) })
        let remaining = try await expired.pending()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testUnsafeInputCannotEnterTheQueue() async throws {
        let inbox = SharedLinkInbox(containerURL: try temporaryDirectory())
        for text in ["javascript:alert(1)", "https://user:secret@youtube.com/watch?v=dQw4w9WgXcQ", "https://r1.googlevideo.com/stream.mp4", "https://127.0.0.1/stream.mp4"] {
            do { _ = try await inbox.enqueue(text); XCTFail("Accepted unsafe input: \(text)") }
            catch LocalStorageError.invalidSharedLink { }
        }
        let pending = try await inbox.pending()
        XCTAssertTrue(pending.isEmpty)
    }

    func testMalformedDiskDataIsReportedAndNotSilentlyOverwritten() async throws {
        let directory = try temporaryDirectory()
        let inbox = SharedLinkInbox(containerURL: directory)
        _ = try await inbox.enqueue("https://youtu.be/dQw4w9WgXcQ")
        let file = directory.appendingPathComponent("SharedLinks/inbox-v1.json")
        let invalid = Data("{interrupted json".utf8)
        try invalid.write(to: file, options: .atomic)
        do { _ = try await inbox.pending(); XCTFail("Corrupt data must report a recoverable failure") }
        catch { }
        XCTAssertEqual(try Data(contentsOf: file), invalid)
    }
}
