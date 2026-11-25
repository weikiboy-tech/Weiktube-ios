// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import Weiktube

final class ReturnDislikeTests: XCTestCase {
    private func count(_ body: String) -> Int64? { ReturnDislikeCodec.decode(Data(body.utf8), videoID: "abcdefghijk") }
    func testRealZeroIsPreservedWhileFailuresNeverBecomeZero() {
        XCTAssertEqual(count(#"{"id":"abcdefghijk","dislikes":0,"deleted":false}"#), 0)
        XCTAssertEqual(count(#"{"id":"abcdefghijk","dislikes":123456}"#), 123456)
        XCTAssertNil(count(#"{"id":"abcdefghijk","dislikes":-1}"#))
        XCTAssertNil(count(#"{"id":"abcdefghijk","dislikes":true}"#))
        XCTAssertNil(count(#"{"id":"abcdefghijk","dislikes":1.5}"#))
        XCTAssertNil(count(#"{"id":"abcdefghijk","dislikes":1000000000001}"#))
        XCTAssertNil(count(#"{"id":"lmnopqrstuv","dislikes":42}"#))
        XCTAssertNil(count(#"{"id":"abcdefghijk","dislikes":42,"deleted":true}"#))
        XCTAssertNil(count("Service unavailable"))
    }
    func testRetryAfterHonorsMinimumAndUpperBound() {
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(PublicServiceTransport.retryDelay("0", now: now), 60)
        XCTAssertEqual(PublicServiceTransport.retryDelay("120", now: now), 120)
        XCTAssertEqual(PublicServiceTransport.retryDelay("999999999999", now: now), 31536000)
        XCTAssertEqual(PublicServiceTransport.retryDelay("bad", now: now), 60)
    }
    func testPublicTransportRejectsCredentialAndDomainConfusion() {
        let transport = PublicServiceTransport(hosts: ["returnyoutubedislikeapi.com"])
        XCTAssertTrue(transport.trusted(URL(string: "https://returnyoutubedislikeapi.com/votes")!))
        for url in ["http://returnyoutubedislikeapi.com/", "https://secret@returnyoutubedislikeapi.com/", "https://returnyoutubedislikeapi.com.evil.example/", "https://returnyoutubedislikeapi.com:8443/"] {
            XCTAssertFalse(transport.trusted(URL(string: url)!))
        }
    }
}
