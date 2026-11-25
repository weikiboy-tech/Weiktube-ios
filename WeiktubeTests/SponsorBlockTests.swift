// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import Weiktube

final class SponsorBlockTests: XCTestCase {
    private let id = "abcdefghijk"
    private func segment(_ id: String, start: Double = 10, end: Double = 20, duration: Double = 100, category: SponsorCategory = .sponsor) -> SponsorSegment {
        .init(start: start, end: end, category: category, id: id, videoDuration: duration, votes: 1, locked: false)
    }
    private func state(_ segments: [SponsorSegment]) -> SponsorPlaybackState {
        var state = SponsorPlaybackState(); state.reset(videoID: id, generation: 7)
        state.settings.enabled = true; state.segments = segments; return state
    }
    private func update(_ state: inout SponsorPlaybackState, position: Double = 12, now: Date = Date()) -> SponsorSeekRequest? {
        state.update(position: position, duration: 100, videoID: id, generation: 7,
                     isPlaying: true, isSeeking: false, isLive: false, isAdvertisement: false, now: now)
    }
    func testHashPrefixQueryDoesNotExposeTheVideoID() {
        let url = SponsorCodec.url(for: id)!
        XCTAssertFalse(url.absoluteString.contains(id))
        XCTAssertEqual(url.lastPathComponent.count, 4)
        XCTAssertEqual(SponsorCodec.prefix(for: "ifI_fwg55k8"), "5f6b")
        XCTAssertNil(SponsorCodec.url(for: "../secrets"))
    }
    func testBucketFiltersIdentityMalformedSegmentsAndDuplicates() throws {
        let input = #"[{"videoID":"wrongwrongw","segments":[]},{"videoID":"abcdefghijk","segments":[{"actionType":"skip","category":"sponsor","segment":[10,20],"videoDuration":100,"UUID":"a"},{"actionType":"skip","category":"sponsor","segment":[10,20],"videoDuration":100,"UUID":"a"},{"actionType":"skip","category":"intro","segment":[true,20],"videoDuration":100,"UUID":"bad"},{"actionType":"skip","category":"sponsor","segment":[-1,20],"videoDuration":100,"UUID":"bad2"},{"actionType":"skip","category":"sponsor","segment":[10,200],"videoDuration":100,"UUID":"bad3"},{"actionType":"mute","category":"sponsor","segment":[10,20],"videoDuration":100,"UUID":"bad4"}]}]"#
        let values = try SponsorCodec.decode(Data(input.utf8), videoID: id)
        XCTAssertEqual(values.count, 1); XCTAssertEqual(values.first?.id, "a")
    }
    func testOverlappingSegmentsProduceOneAcknowledgedSeek() throws {
        var value = state([segment("a"), segment("b", start: 18, end: 30)])
        let now = Date()
        let seek = try XCTUnwrap(update(&value, now: now))
        XCTAssertEqual(seek.target, 30); XCTAssertEqual(Set(seek.segmentIDs), ["a", "b"])
        XCTAssertNil(update(&value, now: now.addingTimeInterval(0.1)), "No duplicate command while a seek is pending")
        XCTAssertNotNil(value.complete(seek, actualPosition: 30, now: now.addingTimeInterval(0.2)))
        XCTAssertNil(value.complete(seek, actualPosition: 30, now: now.addingTimeInterval(0.3)), "Acknowledgment is consumed once")
        XCTAssertNil(update(&value, now: now.addingTimeInterval(0.4)), "No repeat seek if playback callbacks are delayed")
    }
    func testUndoSuppressesAutomaticReentry() throws {
        var value = state([segment("a")]); let now = Date()
        let seek = try XCTUnwrap(update(&value, now: now))
        _ = value.complete(seek, actualPosition: 20, now: now.addingTimeInterval(0.1))
        let undo = try XCTUnwrap(value.undo(now: now.addingTimeInterval(0.2)))
        XCTAssertEqual(undo.target, 12); XCTAssertEqual(undo.undoOf, seek.id)
        XCTAssertNotNil(value.complete(undo, actualPosition: 12, now: now.addingTimeInterval(0.3)))
        XCTAssertNil(update(&value, now: now.addingTimeInterval(0.4)))
    }
    func testUnverifiedDurationBecomesManualAndMismatchNeverSkips() {
        var unknown = state([segment("a", duration: 0)])
        XCTAssertNil(update(&unknown)); XCTAssertNotNil(unknown.manualPrompt)
        XCTAssertNotNil(unknown.skipManual())
        var mismatch = state([segment("a", duration: 200)])
        XCTAssertNil(update(&mismatch)); XCTAssertNil(mismatch.manualPrompt)
    }
    func testOldVideoCompletionTimeoutAndUserSeekCannotCount() throws {
        var value = state([segment("a")]); let now = Date()
        let old = try XCTUnwrap(update(&value, now: now))
        value.reset(videoID: "lmnopqrstuv", generation: 8)
        XCTAssertNil(value.complete(old, actualPosition: 20, now: now.addingTimeInterval(0.1)))
        value = state([segment("a")])
        let expired = try XCTUnwrap(update(&value, now: now))
        XCTAssertNil(value.complete(expired, actualPosition: 20, now: now.addingTimeInterval(3)))
        value = state([segment("a")]); _ = value.userSeek(to: 12)
        XCTAssertNil(update(&value, now: now))
        value = state([segment("a")])
        let pending = try XCTUnwrap(update(&value, now: now))
        value.cancelPendingForUserSeek()
        XCTAssertNil(value.complete(pending, actualPosition: 20, now: now.addingTimeInterval(0.1)), "User intent retires an unfinished automatic seek")
        value = state([segment("a")])
        let confirmed = try XCTUnwrap(update(&value, now: now))
        _ = value.complete(confirmed, actualPosition: 20, now: now.addingTimeInterval(0.1))
        value.cancelPendingForUserSeek()
        XCTAssertEqual(value.lastConfirmed?.id, confirmed.id, "Starting or failing a manual seek cannot roll back confirmed statistics")
        XCTAssertNil(value.userSeek(to: 20), "Landing outside the skipped interval leaves its count unchanged")
        XCTAssertEqual(value.userSeek(to: 12), confirmed.id, "Only a confirmed landing inside the skipped interval rolls back the count")
        XCTAssertNil(value.userSeek(to: 12), "The same confirmed skip can be reversed only once")
    }
    func testPausedLiveAndAdvertisementCannotTriggerAutomaticSkip() {
        for (playing, live, ad) in [(false, false, false), (true, true, false), (true, false, true)] {
            var value = state([segment("a")])
            XCTAssertNil(value.update(position: 12, duration: 100, videoID: id, generation: 7, isPlaying: playing, isSeeking: false, isLive: live, isAdvertisement: ad))
        }
    }
}
