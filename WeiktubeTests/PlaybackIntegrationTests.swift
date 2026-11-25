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

    func testWebKitBridgeOperatesOnDecodedInlineVideo() async throws {
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
        window.isHidden = false
        defer { window.isHidden = true }
        let view = WKWebView(frame: controller.view.bounds, configuration: config)
        controller.view.addSubview(view)
        let encoded = try Data(contentsOf: clip()).base64EncodedString()
        let html = "<meta name='viewport' content='width=device-width'><video playsinline muted preload='auto' width='250' height='140' src='data:video/mp4;base64,\(encoded)'></video>"
        let delegate = LoadedPage()
        view.navigationDelegate = delegate
        view.loadHTMLString(html, baseURL: URL(string: "https://m.youtube.com/watch?v=abcdefghijk"))
        await fulfillment(of: [delegate.finished], timeout: 20)
        let script = """
          const bridge = window.WeiktubeMedia;
          const video = document.querySelector('video');
          const args = {generation: 1, token: 'fixture'};
          bridge.activate({...args, role: 'player', suspended: false, originalControls: true});
          async function until(test) {
            const end = Date.now() + 12000;
            while (!test() && Date.now() < end) await new Promise(r => setTimeout(r, 50));
            if (!test()) throw new Error('Media condition timed out');
          }
          await until(() => video.readyState >= 2);
          await until(() => bridge.command('play', args).ok);
          await until(() => video.currentTime > 0.05);
          const held = bridge.command('hold', {...args, rate: 2}).ok && video.playbackRate === 2;
          bridge.command('release', args);
          const released = video.playbackRate === 1;
          bridge.command('pause', args);
          const seek = await bridge.command('seek', {...args, seconds: 3});
          return held && released && video.paused && seek.ok && Math.abs(video.currentTime - 3) < 0.15;
          """
        let result = try await view.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .defaultClient)
        XCTAssertEqual(result as? Bool, true)
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
private final class LoadedPage: NSObject, WKNavigationDelegate {
    let finished = XCTestExpectation(description: "Local HTML document loaded")
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finished.fulfill() }
}
