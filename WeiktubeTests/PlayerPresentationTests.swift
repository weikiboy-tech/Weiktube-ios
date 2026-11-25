// SPDX-License-Identifier: GPL-3.0-only
import XCTest
#if SWIFT_PACKAGE
@testable import WeiktubeCore
#else
@testable import Weiktube
#endif

final class PlayerPresentationTests: XCTestCase {
    func testOneSourceSurvivesExpandedMiniAndFullscreenTransitions() {
        var state = PlayerPresentationState()
        state.reduce(.open(sourceID: "watch:one"))
        XCTAssertEqual(state.mode, .expanded)
        state.reduce(.minimize)
        XCTAssertEqual(state.mode, .mini)
        state.reduce(.orientationChanged(.landscapeLeft))
        XCTAssertEqual(state.mode, .mini)
        state.reduce(.expand)
        XCTAssertEqual(state.mode, .fullscreen)
        XCTAssertEqual(state.sourceID, "watch:one")
        state.reduce(.close)
        XCTAssertNil(state.sourceID)
        XCTAssertFalse(state.isVisible)
    }

    func testManualFullscreenExitRemainsLatchedUntilPostureChanges() {
        var state = PlayerPresentationState()
        state.reduce(.open(sourceID: "one"))
        state.reduce(.orientationChanged(.landscapeLeft))
        state.reduce(.exitFullscreen)
        XCTAssertEqual(state.mode, .expanded)
        XCTAssertTrue(state.manualFullscreenExitLatched)
        state.reduce(.orientationChanged(.landscapeLeft))
        state.reduce(.orientationChanged(.landscapeRight))
        XCTAssertEqual(state.mode, .expanded)
        XCTAssertTrue(state.manualFullscreenExitLatched)
        state.reduce(.orientationChanged(.portrait))
        XCTAssertFalse(state.manualFullscreenExitLatched)
        state.reduce(.orientationChanged(.landscapeRight))
        XCTAssertEqual(state.mode, .fullscreen)
    }

    func testInvertedAndUnknownSensorValuesDoNotChangePresentationOrLatch() {
        var state = PlayerPresentationState()
        state.reduce(.open(sourceID: "one"))
        state.reduce(.orientationChanged(.landscapeLeft))
        state.reduce(.exitFullscreen)
        let previous = state
        state.reduce(.orientationChanged(.inverted))
        state.reduce(.orientationChanged(.unknown))
        XCTAssertEqual(state, previous)
    }

    func testManualFullscreenInPortraitWaitsForRealPostureChange() {
        var state = PlayerPresentationState()
        state.reduce(.open(sourceID: "one"))
        state.reduce(.toggleFullscreen)
        state.reduce(.orientationChanged(.portrait))
        XCTAssertEqual(state.mode, .fullscreen)
        state.reduce(.orientationChanged(.landscapeLeft))
        state.reduce(.orientationChanged(.portrait))
        XCTAssertEqual(state.mode, .expanded)
    }

    func testConfirmedPictureInPictureRestoresMiniWithoutExpanding() {
        var state = PlayerPresentationState()
        state.reduce(.open(sourceID: "one"))
        state.reduce(.minimize)
        state.reduce(.didEnterPictureInPicture)
        XCTAssertEqual(state.mode, .pictureInPicture)
        state.reduce(.orientationChanged(.landscapeLeft))
        state.reduce(.expand)
        XCTAssertEqual(state.mode, .pictureInPicture)
        state.reduce(.didExitPictureInPicture(restoreInterface: true))
        XCTAssertEqual(state.mode, .mini)
        XCTAssertEqual(state.sourceID, "one")
    }

    func testPictureInPicturePreservesManualFullscreenAndExitLatch() {
        var state = PlayerPresentationState()
        state.reduce(.open(sourceID: "one"))
        state.reduce(.toggleFullscreen)
        state.reduce(.didEnterPictureInPicture)
        state.reduce(.didExitPictureInPicture(restoreInterface: true))
        XCTAssertEqual(state.mode, .fullscreen)
        state.reduce(.exitFullscreen)
        state.reduce(.didEnterPictureInPicture)
        state.reduce(.didExitPictureInPicture(restoreInterface: true))
        XCTAssertEqual(state.mode, .expanded)
        XCTAssertTrue(state.manualFullscreenExitLatched)
    }

    func testPictureInPictureDismissalDoesNotInventPlaybackAndLateEventsCannotReopen() {
        var state = PlayerPresentationState()
        state.reduce(.open(sourceID: "one"))
        state.reduce(.didEnterPictureInPicture)
        state.reduce(.didExitPictureInPicture(restoreInterface: false))
        XCTAssertEqual(state.mode, .mini)
        state.reduce(.close)
        state.reduce(.didEnterPictureInPicture)
        state.reduce(.didExitPictureInPicture(restoreInterface: true))
        state.reduce(.expand)
        XCTAssertEqual(state.mode, .closed)
    }

    func testDifferentSelectionResetsPreviousSourcesExitLatch() {
        var state = PlayerPresentationState()
        state.reduce(.orientationChanged(.landscapeLeft))
        state.reduce(.open(sourceID: "one"))
        state.reduce(.exitFullscreen)
        state.reduce(.open(sourceID: "one"))
        XCTAssertEqual(state.mode, .expanded)
        state.reduce(.open(sourceID: "two"))
        XCTAssertEqual(state.mode, .fullscreen)
        XCTAssertFalse(state.manualFullscreenExitLatched)
    }

    func testZoomClampingHandlesNonFiniteInput() {
        XCTAssertEqual(PlayerGestureLimits.clampedZoom(0.5), 1)
        XCTAssertEqual(PlayerGestureLimits.clampedZoom(2.5), 2.5)
        XCTAssertEqual(PlayerGestureLimits.clampedZoom(12), 8)
        XCTAssertEqual(PlayerGestureLimits.clampedZoom(.nan), 1)
        XCTAssertEqual(PlayerGestureLimits.clampedZoom(.infinity), 1)
    }
}
