// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import WebKit
import XCTest
@testable import Weiktube

@MainActor
final class LiveYouTubeTests: XCTestCase {
    func testPublicVideoThroughAppLinkPlayerAndMiniPlayer() async throws {
        #if targetEnvironment(simulator)
        try XCTSkipUnless(ProcessInfo.processInfo.environment["WEIKTUBE_LIVE_VIDEO"] == "1", "Separater Online-Prüflauf")
        try await withAppWindow { app in
            let id = "aqz-KE-bpKQ"
            app.open(VideoLink(id: id, startSeconds: 0).url)
            let player = app.player
            guard await wait(seconds: 45, until: {
                player.snapshot.videoID == id && player.snapshot.playing &&
                    player.snapshot.position > 0.25 && !player.snapshot.advertisement
            }) else {
                let status = player.errorMessage ?? "Kein laufendes YouTube-Inhaltsvideo bestätigt"
                let page = await playbackPageState(in: player.web.webView)
                XCTFail("\(status). Seite=\(page), WebKit ready=\(player.snapshot.ready), network=\(player.snapshot.networkState), error=\(player.snapshot.mediaErrorCode), autoplayBlocked=\(player.snapshot.autoplayBlocked)")
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
        }
        #else
        throw XCTSkip("Dieser Online-Test verwendet einen frischen Simulator.")
        #endif
    }

    func testPublicHTTPSDirectLinkPlaysPausesAndSeeks() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["WEIKTUBE_LIVE_VIDEO"] == "1", "Separater Online-Prüflauf")
        try await withAppWindow { app in
            let url = try XCTUnwrap(URL(string: "https://raw.githubusercontent.com/weikiboy-tech/Weiktube-ios/c4bb3ee73bbfc038f7ceacb398e64ffc56bafcd0/WeiktubeTests/player-fixture.mp4"))
            app.open(url)
            let player = app.player
            guard await wait(seconds: 35, until: {
                player.isNative && player.snapshot.playing && player.snapshot.position > 0.1
            }) else {
                XCTFail(player.errorMessage ?? "Keine Wiedergabe vom öffentlichen HTTPS-Direktlink")
                return
            }
            player.pause()
            let paused = await wait(seconds: 5) { !player.snapshot.playing }
            XCTAssertTrue(paused)
            player.seek(3)
            let sought = await wait(seconds: 6) { abs(player.snapshot.position - 3) < 0.15 && !player.snapshot.playing }
            XCTAssertTrue(sought)
        }
    }

    private func withAppWindow(_ test: (AppModel) async throws -> Void) async throws {
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
        try await test(app)
    }

    private func playbackPageState(in view: WKWebView) async -> String {
        // Return a fixed category. Page text, URLs and account data stay in WebKit.
        let script = """
          const body = document.body?.innerText || '';
          if (location.hostname === 'consent.youtube.com' || location.hostname === 'consent.google.com') return 'consent';
          if (/not a bot|kein roboter|kein bot|unusual traffic/i.test(body)) return 'visitor verification';
          if (/age.restricted|confirm your age|alter bestätigen/i.test(body)) return 'age restricted';
          if (document.querySelector('.ad-showing,.ad-interrupting')) return 'advertisement';
          if (document.querySelector('.ytp-error,.ytp-error-content-wrap,yt-playability-error-supported-renderers')) return 'player error';
          const video = document.querySelector('video');
          if (video) return video.error ? 'video error' : video.paused ? 'video paused' : 'video present';
          return location.pathname === '/watch' ? 'watch page without video' : 'other page without video';
          """
        return (try? await view.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .defaultClient)) as? String ?? "unavailable"
    }

    private func wait(seconds: TimeInterval, until condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(150))
        }
        return condition()
    }
}
