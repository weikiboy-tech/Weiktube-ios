// SPDX-License-Identifier: GPL-3.0-only
import AVFoundation
import WebKit
import XCTest
@testable import Weiktube

@MainActor
final class PlaybackIntegrationTests: XCTestCase {
    private func clip() throws -> URL {
        try XCTUnwrap(Bundle(for: Self.self).url(forResource: "player-fixture", withExtension: "mp4"))
    }

    private func eventually(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(15)
        while !predicate(), Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(predicate())
    }

    func testNativeHoldReleaseAndSeekDuringActualPlayback() async throws {
        let engine = NativePlayback()
        defer { engine.shutdown() }
        let item = AVPlayerItem(url: try clip())
        engine.player.replaceCurrentItem(with: item)
        try await eventually { item.status == .readyToPlay }
        XCTAssertFalse(engine.hold(rate: 2))
        XCTAssertTrue(engine.setRate(1.5))
        engine.play()
        try await eventually { engine.player.currentTime().seconds > 0.1 }
        XCTAssertTrue(engine.hold(rate: 2))
        XCTAssertEqual(engine.player.rate, 2)
        engine.release()
        XCTAssertEqual(engine.player.rate, 1.5)
        engine.pause()
        let position = await engine.seek(to: 3)
        XCTAssertEqual(try XCTUnwrap(position), 3, accuracy: 0.1)
        XCTAssertEqual(engine.player.rate, 0)
    }

    func testOpenLinkMinimizeChangeTabExpandAndSeekOnTheSamePlayingItem() async throws {
        let localClip = try clip()
        let link = try XCTUnwrap(URL(string: "https://media.example.org/player-fixture.mp4"))
        let engine = NativePlayback { requestedURL in
            XCTAssertEqual(requestedURL, link)
            return AVPlayerItem(url: localClip)
        }
        let app = AppModel(nativePlayback: engine)
        defer {
            app.player.close()
            engine.shutdown()
            app.player.web.shutdown()
            app.home.shutdown()
            app.shorts.shutdown()
        }
        app.open(link)
        try await eventually { app.player.snapshot.playing && app.player.snapshot.position > 0 }
        let item = try XCTUnwrap(engine.player.currentItem)
        app.player.minimize()
        app.select(.adblock)
        XCTAssertTrue(app.player.isMini)
        XCTAssertEqual(app.selectedTab, .adblock)
        let position = engine.player.currentTime().seconds
        try await eventually { engine.player.currentTime().seconds > position + 0.1 }
        app.player.expand()
        XCTAssertTrue(engine.player.currentItem === item)
        app.player.pause()
        app.player.seek(2)
        try await eventually { !app.player.snapshot.playing && abs(app.player.snapshot.position - 2) < 0.15 }
        app.player.close()
        XCTAssertFalse(app.player.hasPlayer)
        XCTAssertNil(engine.player.currentItem)
    }

    func testWebKitBridgeOperatesOnDecodedInlineVideo() async throws {
        let script = """
          const bridge = window.WeiktubeMedia;
          const video = document.querySelector('video');
          const args = {generation: 1, token: 'fixture'};
          bridge.activate({...args, role: 'player', suspended: false, originalControls: true});
          async function until(label, test) {
            const end = Date.now() + 12000;
            while (!test() && Date.now() < end) await new Promise(r => setTimeout(r, 50));
            if (!test()) throw new Error(label + ': ready=' + video.readyState + ', paused=' + video.paused + ', time=' + video.currentTime + ', visible=' + document.visibilityState);
          }
          await until('select playable element', () => bridge.command('play', args).ok);
          await until('clock advancing', () => video.currentTime > 0.05 && video.readyState >= 2);
          const held = bridge.command('hold', {...args, rate: 2}).ok && video.playbackRate === 2;
          bridge.command('release', args);
          const released = video.playbackRate === 1;
          bridge.command('pause', args);
          const seek = await bridge.command('seek', {...args, seconds: 3});
          return held && released && video.paused && seek.ok && Math.abs(video.currentTime - 3) < 0.15;
          """
        try await evaluateClip(script: script)
    }

    func testShortsSwitchPausesPreviousVideoPreservesMuteAndSeeksCurrentVideo() async throws {
        let script = """
          const bridge = window.WeiktubeMedia, [first, next] = document.querySelectorAll('video');
          const args = {generation: 3, token: 'shorts-test'};
          const until = async (label, check) => {
            const end = Date.now() + 15000;
            while (!check()) {
              if (Date.now() >= end) throw new Error(label);
              await new Promise(resolve => setTimeout(resolve, 50));
            }
          };
          bridge.activate({...args, role:'shorts', suspended:false, userMuted:false, originalControls:true});
          await until('first Short did not start', () => !first.paused && first.currentTime > 0);
          if (first.muted || !next.paused) return false;
          bridge.command('mute', {...args, value:true});
          first.hidden = true;
          history.replaceState(null, '', '/shorts/lmnopqrstuv');
          next.scrollIntoView();
          window.dispatchEvent(new Event('yt-navigate-finish'));
          await until('next Short did not start', () => !next.paused && next.currentTime > 0);
          if (!first.paused || !next.muted) return false;
          bridge.command('pause', args);
          const seek = await bridge.command('seek', {...args, seconds:3});
          return seek.ok && next.paused && Math.abs(next.currentTime - 3) < 0.15 && first.paused;
          """
        try await evaluateClip(script: script, twoShorts: true)
    }

    private func evaluateClip(script: String, twoShorts: Bool = false, file: StaticString = #filePath, line: UInt = #line) async throws {
        let bridge = try String(contentsOf: XCTUnwrap(Bundle.main.url(forResource: "MediaBridge", withExtension: "js")), encoding: .utf8)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.addUserScript(WKUserScript(source: bridge, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        defer { window.isHidden = true }
        let view = WKWebView(frame: controller.view.bounds, configuration: config)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view.addSubview(view)
        let encoded = try Data(contentsOf: clip()).base64EncodedString()
        let oneVideo = "<meta name='viewport' content='width=device-width'><video playsinline muted preload='auto' width='250' height='140' src='data:video/mp4;base64,\(encoded)'></video>"
        let html = twoShorts ? oneVideo + "<div style='height:150vh'></div>" + oneVideo : oneVideo
        let route = twoShorts ? "shorts/abcdefghijk" : "watch?v=abcdefghijk"
        let delegate = LoadedPage()
        view.navigationDelegate = delegate
        view.loadHTMLString(html, baseURL: URL(string: "https://m.youtube.com/\(route)"))
        await fulfillment(of: [delegate.finished], timeout: 20)
        defer { withExtendedLifetime(delegate) {} }
        let diagnosticScript = """
          try {
            const passed = await (async () => { \(script) })();
            return passed ? 'passed' : 'unexpected playback state';
          } catch (error) { return String(error); }
          """
        let result = try await view.callAsyncJavaScript(diagnosticScript, arguments: [:], in: nil, contentWorld: .defaultClient)
        XCTAssertEqual(result as? String, "passed", file: file, line: line)
    }
}

@MainActor
private final class LoadedPage: NSObject, WKNavigationDelegate {
    let finished = XCTestExpectation(description: "Local HTML document loaded")
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finished.fulfill() }
}
