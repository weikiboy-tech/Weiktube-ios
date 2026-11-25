// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import Weiktube

final class ReleaseCheckerTests:XCTestCase {
    private func defaults() -> UserDefaults {
        let name="ReleaseCheckerTests.\(UUID().uuidString)"
        let value=UserDefaults(suiteName:name)!
        addTeardownBlock {value.removePersistentDomain(forName:name)}
        return value
    }

    @MainActor
    func testDailyAutomaticAttemptLimitIncludesFailureAndManualRetryRemainsExplicit() async {
        var date=Date(timeIntervalSince1970:1_800_000_000)
        var calls=0
        let checker=ReleaseChecker(defaults:defaults(),currentVersion:"1.0.0",now:{date},fetch:{url,limit,_ in
            calls+=1
            XCTAssertEqual(url,ReleaseChecker.endpoint)
            XCTAssertEqual(limit,524_288)
            return PublicServiceResponse(status:404,data:Data(),retryAfter:nil)
        })
        await checker.check(automatically:true)
        await checker.check(automatically:true)
        XCTAssertEqual(calls,1)
        await checker.check()
        XCTAssertEqual(calls,2)
        date=date.addingTimeInterval(24*60*60)
        await checker.check(automatically:true)
        XCTAssertEqual(calls,3)
    }

    @MainActor
    func testPrivateRepositoryOutcomeSurvivesRestartWithoutClaimingNoPriorCheck() async {
        let storage=defaults(),date=Date(timeIntervalSince1970:1_800_000_000)
        let first=ReleaseChecker(defaults:storage,currentVersion:"1.0.0",now:{date},fetch:{_,_,_ in
            PublicServiceResponse(status:404,data:Data(),retryAfter:nil)
        })
        await first.check()
        var calls=0
        let restored=ReleaseChecker(defaults:storage,currentVersion:"1.0.0",now:{date},fetch:{_,_,_ in
            calls+=1;return PublicServiceResponse(status:404,data:Data(),retryAfter:nil)
        })
        XCTAssertEqual(restored.state,.privateOrUnavailable)
        XCTAssertEqual(restored.lastAttempt,date)
        XCTAssertNil(restored.release)
        await restored.check(automatically:true)
        XCTAssertEqual(calls,0)
    }

    @MainActor
    func testInvalidInstalledVersionCannotBeReportedCurrent() async throws {
        let data=try payload()
        let checker=ReleaseChecker(defaults:defaults(),currentVersion:"development",fetch:{_,_,_ in
            PublicServiceResponse(status:200,data:data,retryAfter:nil)
        })
        await checker.check()
        XCTAssertEqual(checker.state,.installedVersionUnknown)
        XCTAssertEqual(checker.release?.tag,"v1.2.3")
    }

    @MainActor
    func testSuccessfulCachedMetadataIsLabelledCachedUntilRechecked() async throws {
        let storage=defaults(),date=Date(timeIntervalSince1970:1_800_000_000),data=try payload()
        let checker=ReleaseChecker(defaults:storage,currentVersion:"1.2.3",now:{date},fetch:{_,_,_ in
            PublicServiceResponse(status:200,data:data,retryAfter:nil)
        })
        await checker.check()
        XCTAssertEqual(checker.state,.current)
        let restored=ReleaseChecker(defaults:storage,currentVersion:"1.2.3",now:{date})
        XCTAssertEqual(restored.state,.cached)
        XCTAssertEqual(restored.lastChecked,date)
        XCTAssertEqual(restored.release?.tag,"v1.2.3")
    }

    @MainActor
    func testMalformedRemoteMetadataNeverPublishesAnUpdate() async {
        let checker=ReleaseChecker(defaults:defaults(),currentVersion:"1.0.0",fetch:{_,_,_ in
            PublicServiceResponse(status:200,data:Data("{}".utf8),retryAfter:nil)
        })
        await checker.check()
        guard case .failed=checker.state else{return XCTFail("Invalid metadata must fail")}
        XCTAssertNil(checker.release)
        XCTAssertNil(checker.lastChecked)
    }

    private func payload() throws -> Data {
        try JSONSerialization.data(withJSONObject:[
            "tag_name":"v1.2.3","name":"Release 1.2.3","body":"Confirmed notes",
            "html_url":"https://github.com/weikiboy-tech/Weiktube-iOS/releases/tag/v1.2.3",
            "published_at":"2026-11-20T10:00:00Z","draft":false,"prerelease":false,"assets":[]
        ])
    }
}
