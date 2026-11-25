// SPDX-License-Identifier: GPL-3.0-only
import XCTest
#if SWIFT_PACKAGE
@testable import WeiktubeCore
#else
@testable import Weiktube
#endif

final class YouTubeLinkRouterTests: XCTestCase {
    private let id = "dQw4w9WgXcQ"

    func testSupportedVideoHostsAndPathsPreserveIdentity() throws {
        let links = [
            "https://youtu.be/\(id)", "https://youtube.com/watch?v=\(id)",
            "https://www.youtube.com/watch?v=\(id)", "https://m.youtube.com/watch?v=\(id)",
            "https://music.youtube.com/watch?v=\(id)", "https://www.youtube.com/live/\(id)",
            "https://www.youtube.com/v/\(id)", "https://www.youtube.com/embed/\(id)",
            "https://youtube-nocookie.com/embed/\(id)", "https://www.youtube-nocookie.com/embed/\(id)"
        ]
        for link in links {
            let route = try XCTUnwrap(YouTubeLinkRouter.route(link), link)
            XCTAssertEqual(route, .video(VideoLink(id: id)), link)
            XCTAssertEqual(route.identity, "watch:\(id)")
            XCTAssertEqual(route.url.absoluteString, "https://m.youtube.com/watch?v=\(id)")
        }
    }

    func testTimestampsExplicitZeroAndPlaylistContext() throws {
        let route = try XCTUnwrap(YouTubeLinkRouter.route("https://youtu.be/\(id)?t=0&start=90&list=PL_public_123&index=4&si=tracking"))
        XCTAssertEqual(route.startSeconds, 0)
        XCTAssertEqual(route, .video(VideoLink(id: id, startSeconds: 0, playlistID: "PL_public_123", index: 4)))
        XCTAssertEqual(route.url.absoluteString, "https://m.youtube.com/watch?v=\(id)&t=0&list=PL_public_123&index=4")
        XCTAssertNil(YouTubeLinkRouter.route("https://youtu.be/\(id)")?.startSeconds)
        XCTAssertEqual(YouTubeLinkRouter.route("https://youtu.be/\(id)?start=90")?.startSeconds, 90)
        XCTAssertEqual(YouTubeLinkRouter.route("https://youtu.be/\(id)?time_continue=123")?.startSeconds, 123)
        XCTAssertEqual(YouTubeLinkRouter.route("https://youtu.be/\(id)#t=1h2m3s")?.startSeconds, 3723)
    }

    func testTimestampOverflowAndMalformedValues() {
        XCTAssertEqual(YouTubeLinkRouter.seconds("9999999999999999999999999999999"), 86_400)
        XCTAssertEqual(YouTubeLinkRouter.seconds("1000h"), 86_400)
        XCTAssertEqual(YouTubeLinkRouter.seconds("0s"), 0)
        for invalid in ["", "-1", "1.5", "1m2h", "1h2", "NaN", "Infinity", "1H", "s", " 5"] {
            XCTAssertNil(YouTubeLinkRouter.seconds(invalid), invalid)
            XCTAssertNil(YouTubeLinkRouter.route("https://youtu.be/\(id)?t=\(invalid)"), invalid)
        }
    }

    func testBrowseRoutesStaySeparateFromNormalPlayback() throws {
        XCTAssertEqual(YouTubeLinkRouter.route("https://youtube.com/shorts/\(id)"), .shorts(VideoLink(id: id)))
        XCTAssertEqual(YouTubeLinkRouter.route("https://youtube.com/shorts/"), .shorts(nil))
        XCTAssertEqual(YouTubeLinkRouter.route("https://youtube.com/playlist?list=PL_public_123"), .playlist(id: "PL_public_123"))
        XCTAssertEqual(YouTubeLinkRouter.route("https://youtube.com/@Creator/videos?feature=shared"), .channel(path: "/@Creator/videos"))
        XCTAssertEqual(YouTubeLinkRouter.route("https://youtube.com/channel/UC_123/shorts"), .channel(path: "/channel/UC_123/shorts"))
        XCTAssertEqual(YouTubeLinkRouter.route("https://youtube.com/results?search_query=hello%20world"), .search(query: "hello world"))
        XCTAssertEqual(YouTubeLinkRouter.route("https://youtube.com/feed/subscriptions"), .feed(path: "/feed/subscriptions"))
        XCTAssertEqual(YouTubeLinkRouter.route("https://youtube.com/"), .home)
        XCTAssertNotEqual(MediaRoute.shorts(VideoLink(id: id)).identity, MediaRoute.video(VideoLink(id: id)).identity)
        XCTAssertFalse(MediaRoute.playlist(id: "PL_public_123").isPlayable)
    }

    func testMalformedAndUnsafeYouTubeEntriesAreRejected() {
        let invalid = [
            "http://youtu.be/\(id)", "javascript:alert(1)", "file:///video.mp4", "https://user:secret@youtube.com/watch?v=\(id)",
            "https://youtube.com.evil.example/watch?v=\(id)", "https://evil.example/youtube.com/watch?v=\(id)",
            "https://youtube.com:8443/watch?v=\(id)", "https://youtube.com/watch?v=short", "https://youtube.com/watch?v=\(id)&v=ABCDEFGHIJK",
            "https://youtube.com/watch?v=\(id)&t=1&t=2", "https://youtube.com/watch?v=\(id)&list=bad%2Flist",
            "https://youtube.com/redirect?q=https://youtu.be/\(id)", "https://youtube.com/attribution_link?u=/watch?v=\(id)",
            "https://youtube.com/%2fwatch?v=\(id)", "https://youtube.com/foo/../watch?v=\(id)",
            "https://youtube.com/%2e%2e/watch?v=\(id)", "https://youtube.com/shorts//\(id)",
            "https://youtube.com/shorts%5c\(id)", "https://youtube.com/shorts%00/\(id)",
            "https://youtube.com\\@evil.example/watch?v=\(id)", "https://youtube.com/wa\ntch?v=\(id)",
            "https://youtube-nocookie.com/watch?v=\(id)", "https://youtu.be/\(id)/extra",
            "https://youtube.com/@Creator/unsupported", "https://youtube.com/signin"
        ]
        for value in invalid { XCTAssertNil(YouTubeLinkRouter.route(value), value) }
    }

    func testWeiktubeWrapperRoundTripAndRecursiveWrapperRejected() throws {
        let route = MediaRoute.video(VideoLink(id: id, startSeconds: 0, playlistID: "PL_123", index: 2))
        let wrapper = YouTubeLinkRouter.shareURL(for: route)
        XCTAssertEqual(YouTubeLinkRouter.route(wrapper), route)
        var recursive = URLComponents(string: "weiktube://open")!
        recursive.queryItems = [.init(name: "url", value: wrapper.absoluteString)]
        XCTAssertNil(YouTubeLinkRouter.route(try XCTUnwrap(recursive.url)))
        XCTAssertNil(YouTubeLinkRouter.route("weiktube://open?url=https%3A%2F%2Fyoutu.be%2F\(id)&url=https%3A%2F%2Fevil.example"))
        XCTAssertNil(YouTubeLinkRouter.route("weiktube://user@open?url=https%3A%2F%2Fyoutu.be%2F\(id)"))
    }

    func testShareTextExtractsOnlyAnAllowedPublicRoute() {
        XCTAssertEqual(YouTubeLinkRouter.extractFirstRoute(from: "Look at this (https://youtu.be/\(id)?t=25)."), .video(VideoLink(id: id, startSeconds: 25)))
        XCTAssertNil(YouTubeLinkRouter.extractFirstRoute(from: "https://evil.example/redirect?url=https://youtu.be/\(id)"))
        XCTAssertNil(YouTubeLinkRouter.extractFirstRoute(from: String(repeating: "x", count: 16_385)))
    }

    func testDirectPublicMediaAcceptsHTTPSFilesWithoutProtectedStreamExtraction() throws {
        for value in ["https://cdn.example.com/movie.mp4", "https://video.example.org/live/master.m3u8?token=public-token", "https://media.example.org/VIDEO.MP4"] {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertEqual(YouTubeLinkRouter.route(url), .directMedia(url))
            XCTAssertTrue(YouTubeLinkRouter.directMediaAllowed(url))
        }
    }

    func testDirectMediaRejectsPrivateAddressesCredentialsAndProtectedHosts() throws {
        let invalid = [
            "https://googlevideo.com/video.mp4", "https://r1---sn.example.googlevideo.com/video.mp4",
            "https://youtube.com/video.mp4", "http://cdn.example.com/video.mp4", "https://user:secret@cdn.example.com/video.mp4",
            "https://cdn.example.com:8080/video.mp4", "https://cdn.example.com/video.mp4#fragment", "https://cdn.example.com/page.html",
            "https://localhost/video.mp4", "https://device.local/video.mp4", "https://192.168.1.2/video.mp4",
            "https://10.0.0.1/video.mp4", "https://127.0.0.1/video.mp4", "https://172.16.0.1/video.mp4",
            "https://169.254.169.254/video.mp4", "https://100.64.0.1/video.mp4", "https://[::1]/video.mp4",
            "https://2130706433/video.mp4", "https://0177.0.0.1/video.mp4", "https://0x7f.0.0.1/video.mp4",
            "https://127.1/video.mp4", "https://cdn.example.com/%2e%2e/video.mp4", "https://cdn.example.com/a%2fb.mp4",
            "https://cdn..example.com/video.mp4", "https://cdn.example.com./video.mp4"
        ]
        for value in invalid {
            XCTAssertNil(YouTubeLinkRouter.route(value), value)
            if let url = URL(string: value) { XCTAssertFalse(YouTubeLinkRouter.directMediaAllowed(url), value) }
        }
    }
}
