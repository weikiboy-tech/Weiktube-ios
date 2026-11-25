// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import XCTest
@testable import Weiktube

@MainActor
final class LiveYouTubeTests: XCTestCase {
    func testPublicVideoThroughAppLinkPlayerAndMiniPlayer() async throws {
        #if targetEnvironment(simulator)
        try XCTSkipUnless(ProcessInfo.processInfo.environment["WEIKTUBE_LIVE_VIDEO"] == "1", "Separater Online-Prüflauf")
        let app = AppModel()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: RootView(app: app))
        window.makeKeyAndVisible()
        defer {
            app.player.close()
            window.isHidden = true
            window.rootViewController = nil
            app.player.native.shutdown()
            app.player.web.shutdown()
            app.home.shutdown()
            app.shorts.shutdown()
        }
        let id = "aqz-KE-bpKQ"
        app.open(VideoLink(id: id, startSeconds: 0).url)
        let player = app.player
        guard await wait(seconds: 45, until: {
            player.snapshot.videoID == id && player.snapshot.playing &&
                player.snapshot.position > 0.25 && !player.snapshot.advertisement
        }) else {
            let status = player.errorMessage ?? "Kein laufendes YouTube-Inhaltsvideo bestätigt"
            XCTFail("\(status). WebKit ready=\(player.snapshot.ready), network=\(player.snapshot.networkState), error=\(player.snapshot.mediaErrorCode), autoplayBlocked=\(player.snapshot.autoplayBlocked)")
            return
        }
        let identity = player.snapshot.elementID
        app.select(.you)
        XCTAssertTrue(player.isMini)
        let position = player.snapshot.position
        let continued = await wait(seconds: 8) { player.snapshot.position > position + 0.3 }
        XCTAssertTrue(continued, "Wiedergabe im Miniplayer")
        player.expand()
        XCTAssertEqual(player.snapshot.elementID, identity)
        player.pause()
        let paused = await wait(seconds: 5) { !player.snapshot.playing }
        XCTAssertTrue(paused)
        player.seek(15)
        let sought = await wait(seconds: 6) { abs(player.snapshot.position - 15) < 0.5 && !player.snapshot.playing }
        XCTAssertTrue(sought, "Spulen im pausierten YouTube-Video")
        #else
        throw XCTSkip("Dieser Online-Test verwendet einen frischen Simulator.")
        #endif
    }

    private func wait(seconds: TimeInterval, until condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(150))
        }
        return condition()
    }
}
