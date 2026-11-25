// SPDX-License-Identifier: GPL-3.0-only
import XCTest
#if SWIFT_PACKAGE
@testable import WeiktubeCore
#else
@testable import Weiktube
#endif

final class ReleaseMetadataTests: XCTestCase {
    func testSemanticVersionOrdersNumericComponentsAndPrereleases() throws {
        let values = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0", "1.2.0", "1.10.0", "2.0.0"]
        let versions = try values.map { try XCTUnwrap(ReleaseVersion($0)) }
        XCTAssertEqual(versions.sorted(), versions)
        for pair in zip(versions, versions.dropFirst()) { XCTAssertLessThan(pair.0, pair.1) }
    }

    func testVersionPrefixAndBuildMetadataDoNotInventAnUpdate() throws {
        let installed = try XCTUnwrap(ReleaseVersion("v1.2.3+local.7"))
        let released = try XCTUnwrap(ReleaseVersion("1.2.3+release.8"))
        XCTAssertEqual(installed, released)
        XCTAssertFalse(installed < released)
        XCTAssertEqual(Set([installed, released]).count, 1)
        XCTAssertEqual(installed.description, "1.2.3+local.7")
    }

    func testMalformedAndAmbiguousVersionStringsAreRejected() {
        for value in ["", "v", "1", "1.2", "1.2.3.4", "01.2.3", "1.02.3", "1.2.03", "-1.2.3", "1.2.3-", "1.2.3+", "1.2.3-alpha..1", "1.2.3-01", "1.2.3+a+b", "1.2.3 rc1", "1.2.3\n", "99999999999999999999999.0.0"] {
            XCTAssertNil(ReleaseVersion(value), value)
        }
    }

    func testOfficialReleaseMetadataRetainsOnlyValidatedPublicURLs() throws {
        let value = try ReleaseMetadata.decode(payload())
        XCTAssertTrue(value.isValid)
        XCTAssertEqual(value.version, ReleaseVersion("1.2.3"))
        XCTAssertEqual(value.name, "Release 1.2.3")
        XCTAssertEqual(value.notes, "Published release notes")
        XCTAssertEqual(value.assets.count, 1)
        XCTAssertEqual(value.assets.first?.name, "Weiktube.zip")
    }

    func testForeignAssetsCredentialsDraftsAndPrereleasesAreRejected() throws {
        let replacements: [[String: Any]] = [
            ["html_url": "https://github.com/attacker/Weiktube-iOS/releases/tag/v1.2.3"],
            ["html_url": "https://user:secret@github.com/weikiboy-tech/Weiktube-iOS/releases/tag/v1.2.3"],
            ["tag_name": "latest"], ["draft": true], ["prerelease": true],
            ["assets": [["name": "Weiktube.zip", "size": 10, "browser_download_url": "https://evil.example/Weiktube.zip"]]],
            ["assets": [["name": "Weiktube.zip", "size": 10, "browser_download_url": "https://github.com/weikiboy-tech/Other/releases/download/v1.2.3/Weiktube.zip"]]]
        ]
        for replacement in replacements { XCTAssertThrowsError(try ReleaseMetadata.decode(payload(replacing: replacement))) }
    }

    func testReleaseURLPolicyRejectsEncodedSeparatorsAndMismatchedTag() {
        let paths = [
            "https://github.com/weikiboy-tech/Weiktube-iOS/releases/tag/v1.2.3?redirect=evil",
            "http://github.com/weikiboy-tech/Weiktube-iOS/releases/tag/v1.2.3",
            "https://github.com/weikiboy-tech/Weiktube-iOS/releases/tag/v1.2.4",
            "https://github.com/weikiboy-tech%2fWeiktube-iOS/releases/tag/v1.2.3"
        ]
        for path in paths { XCTAssertFalse(ReleaseURLPolicy.releasePage(URL(string: path)!, tag: "v1.2.3")) }
        XCTAssertFalse(ReleaseURLPolicy.asset(URL(string: "https://github.com/weikiboy-tech/Weiktube-iOS/releases/download/v1.2.3/a%2fb")!, tag: "v1.2.3", name: "a/b"))
    }

    func testOversizeMetadataFailsBeforeJSONDecoding() {
        XCTAssertThrowsError(try ReleaseMetadata.decode(Data(repeating: 65, count: 524_289))) { error in
            guard case ReleaseMetadataError.responseTooLarge = error else { return XCTFail("Expected bounded response") }
        }
    }

    func testCanonicalRepositoryCaseIsAcceptedWithoutRelaxingTagOrAssetIdentity() throws {
        let value=try ReleaseMetadata.decode(payload(replacing:[
            "html_url":"https://github.com/weikiboy-tech/Weiktube-ios/releases/tag/v1.2.3",
            "assets":[["name":"Weiktube.zip","size":10,"browser_download_url":"https://github.com/Weikiboy-Tech/WEIKTUBE-IOS/releases/download/v1.2.3/Weiktube.zip"]]
        ]))
        XCTAssertTrue(value.isValid)
        XCTAssertFalse(ReleaseURLPolicy.releasePage(URL(string:"https://github.com/weikiboy-tech/Weiktube-ios/releases/tag/V1.2.3")!,tag:"v1.2.3"))
        XCTAssertFalse(ReleaseURLPolicy.asset(URL(string:"https://github.com/weikiboy-tech/Weiktube-ios/releases/download/v1.2.3/weiktube.zip")!,tag:"v1.2.3",name:"Weiktube.zip"))
        XCTAssertFalse(ReleaseURLPolicy.releasePage(URL(string:"https://github.com/weikiboy-tech/Weiktube-ios-extra/releases/tag/v1.2.3")!,tag:"v1.2.3"))
    }

    private func payload(replacing changes: [String: Any] = [:]) throws -> Data {
        var object: [String: Any] = [
            "tag_name": "v1.2.3", "name": "Release 1.2.3", "body": "Published release notes",
            "html_url": "https://github.com/weikiboy-tech/Weiktube-iOS/releases/tag/v1.2.3",
            "published_at": "2026-11-20T10:00:00Z", "draft": false, "prerelease": false,
            "assets": [["name": "Weiktube.zip", "size": 12345,
                        "browser_download_url": "https://github.com/weikiboy-tech/Weiktube-iOS/releases/download/v1.2.3/Weiktube.zip"]]
        ]
        object.merge(changes) { _, changed in changed }
        return try JSONSerialization.data(withJSONObject: object)
    }
}
