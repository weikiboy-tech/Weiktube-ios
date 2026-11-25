// SPDX-License-Identifier: GPL-3.0-only
import XCTest
import WebKit
@testable import Weiktube

final class AdBlockTests: XCTestCase {
    private func snapshot() throws -> FilterSnapshot { try FilterSnapshot.parse(FilterResources.data("rules", extension: "json")) }
    private func modified(_ action: (inout [String: Any]) -> Void) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: FilterResources.data("rules", extension: "json")) as! [String: Any]
        action(&object); return try JSONSerialization.data(withJSONObject: object)
    }
    func testBundledRSAFilterVerifiesAndTamperingRollbackFail() throws {
        let data = try FilterResources.data("rules", extension: "json")
        let signature = try FilterResources.text("rules", extension: "sig")
        let key = try FilterResources.text("update-public-key", extension: "txt")
        XCTAssertEqual(try SignedFilterPackage.verify(data: data, signature: signature, publicKey: key).version, 1)
        XCTAssertThrowsError(try SignedFilterPackage.verify(data: data + Data(" ".utf8), signature: signature, publicKey: key))
        XCTAssertThrowsError(try SignedFilterPackage.verify(data: data, signature: signature, publicKey: key, minimumVersion: 2))
    }
    func testSchemaRejectsExecutableAndCredentialDomainPayloads() throws {
        XCTAssertThrowsError(try FilterSnapshot.parse(modified { $0["javascript"] = "arbitrary code" }))
        XCTAssertThrowsError(try FilterSnapshot.parse(modified {
            var rules = $0["networkRules"] as! [[String: Any]]; rules[0]["host"] = "accounts.google.com"; $0["networkRules"] = rules
        }))
        XCTAssertThrowsError(try FilterSnapshot.parse(modified { $0["cosmeticSelectors"] = ["body", "video"] }))
        XCTAssertThrowsError(try FilterSnapshot.parse(modified {
            var rules = $0["scriptlets"] as! [[String: Any]]; rules[0]["args"] = ["document.cookie", "undefined"]; $0["scriptlets"] = rules
        }))
        XCTAssertThrowsError(try FilterSnapshot.parse(modified {
            var rules = $0["scriptlets"] as! [[String: Any]]; rules[6]["args"] = ["adSlots", "", "url:/.*/"]; $0["scriptlets"] = rules
        }))
    }
    func testDomainParserAcceptsHostsRowsAndRejectsInjectedRules() throws {
        XCTAssertEqual(try DomainListParser.parse("0.0.0.0 ads.example.org # note\nanalytics.example.org.\n127.0.0.1 localhost"), ["ads.example.org", "analytics.example.org"])
        for value in ["||ads.example.org^", "https://ads.example.org/", "ads.example.org;alert(1)", "a..example.org"] {
            XCTAssertThrowsError(try DomainListParser.parse(value))
        }
        XCTAssertFalse(DomainListParser.matches("notyoutube.com", domain: "youtube.com"))
        XCTAssertFalse(DomainListParser.matches("youtube.com.evil.org", domain: "youtube.com"))
        XCTAssertTrue(DomainListParser.matches("www.youtube.com", domain: "youtube.com"))
    }
    @MainActor
    func testRulesCompileOnTheActualWebKitEngine() async throws {
        let json = try WebKitRuleCompiler.rules(snapshot: snapshot(), preferences: .init(), appDomain: "com.weiktube.ios")
        let result: WKContentRuleList = try await withCheckedThrowingContinuation { continuation in
            WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "weiktube-unit-fixture", encodedContentRuleList: json) { list, error in
                if let list { continuation.resume(returning: list) }
                else { continuation.resume(throwing: error ?? PublicServiceError.invalidResponse) }
            }
        }
        XCTAssertEqual(result.identifier, "weiktube-unit-fixture")
    }
}
