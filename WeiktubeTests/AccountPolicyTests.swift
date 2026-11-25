// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import Weiktube

final class AccountPolicyTests: XCTestCase {
    func testAWriteIntentCannotSurviveAccountReplacement() throws {
        var session = AccountSessionRevision()
        let oldIntent = session.value
        try session.check(oldIntent)
        session.advance()
        XCTAssertThrowsError(try session.check(oldIntent)) { error in
            XCTAssertEqual(error as? AccountError, .sessionChanged)
        }
        XCTAssertNoThrow(try session.check(session.value))
    }

    func testPKCES256MatchesRFC7636Vector() {
        XCTAssertEqual(OAuthPKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
                       "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testPKCEIsRandomAndUsesURLSafeCharacters() throws {
        let first = try OAuthPKCE()
        let second = try OAuthPKCE()
        XCTAssertNotEqual(first.verifier, second.verifier)
        XCTAssertNotEqual(first.state, second.state)
        XCTAssertEqual(first.verifier.count, 43)
        XCTAssertNotNil(first.verifier.range(of: #"^[A-Za-z0-9_-]{43}$"#, options: .regularExpression))
        XCTAssertEqual(first.challenge, OAuthPKCE.challenge(for: first.verifier))
    }

    func testOAuthConfigurationMustMatchRegisteredIOSClientScheme() throws {
        let client = "123-example.apps.googleusercontent.com"
        let scheme = "com.googleusercontent.apps.123-example"
        let valid = try GoogleOAuthConfiguration(clientID: client, redirectURI: "\(scheme):/oauthredirect", registeredSchemes: [scheme])
        XCTAssertEqual(valid.callbackScheme, scheme)
        XCTAssertThrowsError(try GoogleOAuthConfiguration(clientID: client, redirectURI: "wrong:/oauthredirect", registeredSchemes: ["wrong"]))
        XCTAssertThrowsError(try GoogleOAuthConfiguration(clientID: client, redirectURI: "\(scheme):/oauthredirect", registeredSchemes: []))
        XCTAssertThrowsError(try GoogleOAuthConfiguration(clientID: "", redirectURI: "", registeredSchemes: []))
        XCTAssertThrowsError(try GoogleOAuthConfiguration(clientID: client, redirectURI: "https://example.org/callback", registeredSchemes: [scheme]))
    }

    func testCallbackRejectsStateMismatchAndAmbiguousParameters() throws {
        let redirect = URL(string: "com.googleusercontent.apps.example:/oauthredirect")!
        let valid = URL(string: "com.googleusercontent.apps.example:/oauthredirect?state=expected&code=one")!
        XCTAssertEqual(try OAuthPKCE.authorizationCode(callback: valid, redirect: redirect, expectedState: "expected"), "one")
        for callback in [
            "com.googleusercontent.apps.example:/oauthredirect?state=wrong&code=one",
            "com.googleusercontent.apps.example:/oauthredirect?state=expected&state=expected&code=one",
            "com.googleusercontent.apps.example:/oauthredirect?state=expected&code=one&code=two",
            "com.googleusercontent.apps.example://attacker/oauthredirect?state=expected&code=one",
            "com.googleusercontent.apps.example:/another?state=expected&code=one",
            "com.googleusercontent.apps.example:/oauthredirect?state=expected&code=one#extra"
        ] {
            XCTAssertThrowsError(try OAuthPKCE.authorizationCode(callback: URL(string: callback)!, redirect: redirect, expectedState: "expected"), callback)
        }
    }

    func testAuthorizationFailureNeverYieldsACode() {
        let redirect = URL(string: "com.googleusercontent.apps.example:/oauthredirect")!
        let callback = URL(string: "com.googleusercontent.apps.example:/oauthredirect?state=expected&error=access_denied")!
        XCTAssertThrowsError(try OAuthPKCE.authorizationCode(callback: callback, redirect: redirect, expectedState: "expected"))
    }

    func testOnlyAnInitialUnauthorizedGETMayBeReplayed() {
        XCTAssertTrue(YouTubeActionPolicy.mayRetry(method: "GET", status: 401, attempts: 0))
        XCTAssertFalse(YouTubeActionPolicy.mayRetry(method: "GET", status: 401, attempts: 1))
        for method in ["POST", "DELETE", "PUT", "PATCH"] {
            XCTAssertFalse(YouTubeActionPolicy.mayRetry(method: method, status: 401, attempts: 0))
            XCTAssertFalse(YouTubeActionPolicy.mayRetry(method: method, status: 503, attempts: 0))
        }
        XCTAssertFalse(YouTubeActionPolicy.mayRetry(method: "GET", status: 429, attempts: 0))
    }

    func testCommentPayloadEscapesDataAndContainsActualVideoChannel() throws {
        let text = "A \"quote\", a newline\n<script>literal</script>"
        let data = try YouTubeActionPayloads.comment(channelID: "UC_example", videoID: "abcdefghijk", text: text)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let snippet = try XCTUnwrap(object["snippet"] as? [String: Any])
        XCTAssertEqual(snippet["channelId"] as? String, "UC_example")
        XCTAssertEqual(snippet["videoId"] as? String, "abcdefghijk")
        let top = try XCTUnwrap(snippet["topLevelComment"] as? [String: Any])
        let body = try XCTUnwrap(top["snippet"] as? [String: Any])
        XCTAssertEqual(body["textOriginal"] as? String, text)
        XCTAssertNil(object["access_token"])
    }

    func testReplyContainsParentRatherThanVideoOrChannel() throws {
        let data = try YouTubeActionPayloads.reply(parentID: "Ug.parent-123", text: " Reply ")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: [String: String]])
        XCTAssertEqual(json["snippet"], ["parentId": "Ug.parent-123", "textOriginal": "Reply"])
    }

    func testInvalidInputAndUnavailableSystemPlaylistsAreRejected() {
        XCTAssertThrowsError(try YouTubeActionPolicy.videoID("abcdefghij"))
        XCTAssertThrowsError(try YouTubeActionPolicy.videoID("abcd<script"))
        XCTAssertThrowsError(try YouTubeActionPolicy.resourceID("bad\nidentifier"))
        XCTAssertThrowsError(try YouTubeActionPolicy.comment(" \n "))
        XCTAssertThrowsError(try YouTubeActionPolicy.comment(String(repeating: "a", count: 5001)))
        XCTAssertThrowsError(try YouTubeActionPayloads.playlistItem(playlistID: "WL", videoID: "abcdefghijk"))
        XCTAssertThrowsError(try YouTubeActionPayloads.playlistItem(playlistID: "HL", videoID: "abcdefghijk"))
    }

    func testPlaylistAndSubscriptionPayloadKindsAreCorrect() throws {
        let playlist = try XCTUnwrap(JSONSerialization.jsonObject(with: YouTubeActionPayloads.playlistItem(playlistID: "PL_example", videoID: "abcdefghijk")) as? [String: Any])
        let snippet = try XCTUnwrap(playlist["snippet"] as? [String: Any])
        let resource = try XCTUnwrap(snippet["resourceId"] as? [String: String])
        XCTAssertEqual(snippet["playlistId"] as? String, "PL_example")
        XCTAssertEqual(resource, ["kind": "youtube#video", "videoId": "abcdefghijk"])
        let subscription = try XCTUnwrap(JSONSerialization.jsonObject(with: YouTubeActionPayloads.subscription(channelID: "UC_example")) as? [String: [String: [String: String]]])
        XCTAssertEqual(subscription["snippet"]?["resourceId"], ["kind": "youtube#channel", "channelId": "UC_example"])
    }

    func testReadonlyConsentNeverEnablesWrites() {
        XCTAssertTrue(AccountScopes.canRead([AccountScopes.read]))
        XCTAssertFalse(Set([AccountScopes.read]).contains(AccountScopes.write))
        XCTAssertFalse(AccountScopes.canRead([]))
    }

    func testFormEncodingDoesNotTurnPlusIntoSpace() {
        let body = YouTubeHTTPTransport.formBody(["code": "a+b&c=d"])
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertEqual(text, "code=a%2Bb%26c%3Dd")
    }

    func testPageTokenBoundsAndEmptyNormalization() throws {
        XCTAssertNil(try YouTubeActionPolicy.pageToken(""))
        XCTAssertThrowsError(try YouTubeActionPolicy.pageToken(String(repeating: "x", count: 4097)))
        XCTAssertThrowsError(try YouTubeActionPolicy.pageToken("x\n"))
    }

    func testRatingUsesVideoIdWireFieldAndCannotLeakOtherVideoRating() throws {
        let json = Data(#"{"items":[{"videoId":"abcdefghijk","rating":"like"}]}"#.utf8)
        let response = try JSONDecoder().decode(YouTubeRatingResponse.self, from: json)
        XCTAssertEqual(try response.rating(for: "abcdefghijk"), .like)
        XCTAssertThrowsError(try response.rating(for: "lmnopqrstuv"))
    }

    func testPlaylistVideoUsesUploaderRatherThanPlaylistOwner() throws {
        let json = Data(#"{"id":"playlist-entry","snippet":{"title":"Video","channelId":"UC_playlist_owner","channelTitle":"Playlist owner","videoOwnerChannelId":"UC_uploader","videoOwnerChannelTitle":"Uploader","resourceId":{"videoId":"abcdefghijk"}}}"#.utf8)
        let item = try JSONDecoder().decode(YouTubeWireItem.self, from: json)
        let video = try XCTUnwrap(YouTubeModelParser.video(item, isPlaylistItem: true))
        XCTAssertEqual(video.channelID, "UC_uploader")
        XCTAssertEqual(video.channelTitle, "Uploader")
        XCTAssertEqual(video.id, "abcdefghijk")
    }
}
