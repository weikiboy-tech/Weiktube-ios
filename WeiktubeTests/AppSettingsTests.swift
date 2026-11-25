// SPDX-License-Identifier: GPL-3.0-only
import XCTest
@testable import Weiktube

final class AppSettingsTests: XCTestCase {
    private func isolatedDefaults() throws -> UserDefaults {
        let name = "WeiktubeSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        return defaults
    }

    @MainActor
    func testFreshDefaultsMatchAndroidWithDislikesAndIOSReleaseChecksOptIn() async throws {
        let settings = AppSettings(defaults: try isolatedDefaults())
        XCTAssertEqual(settings.appearance, .system)
        XCTAssertTrue(settings.adBlockEnabled)
        XCTAssertTrue(settings.filterAds)
        XCTAssertTrue(settings.filterTrackers)
        XCTAssertTrue(settings.saveHistory)
        XCTAssertTrue(settings.brightnessGesture)
        XCTAssertTrue(settings.volumeGesture)
        XCTAssertTrue(settings.doubleTapSeek)
        XCTAssertTrue(settings.holdToSpeed)
        XCTAssertEqual(settings.seekSeconds, 10)
        XCTAssertEqual(settings.holdSpeed, 2)
        XCTAssertEqual(settings.wifiQuality, 1080)
        XCTAssertEqual(settings.mobileQuality, 720)
        XCTAssertFalse(settings.returnYouTubeDislike)
        XCTAssertFalse(settings.automaticUpdateChecks)
        XCTAssertTrue(settings.automaticFilterUpdateChecks)
        XCTAssertEqual(settings.customDomains, "")
        XCTAssertEqual(settings.domainExceptions, "")
    }

    @MainActor
    func testEditedValuesPersistAndRestoreDefaults() async throws {
        let defaults = try isolatedDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.appearance = .dark
        settings.saveHistory = false
        settings.returnYouTubeDislike = true
        settings.automaticUpdateChecks = true
        settings.automaticFilterUpdateChecks = false
        settings.seekSeconds = 30
        settings.holdSpeed = 3
        settings.wifiQuality = 2160
        settings.mobileQuality = 0
        settings.customDomains = "ads.example.org\ntracker.example.org"
        let loaded = AppSettings(defaults: defaults)
        XCTAssertEqual(loaded.appearance, .dark)
        XCTAssertFalse(loaded.saveHistory)
        XCTAssertTrue(loaded.returnYouTubeDislike)
        XCTAssertTrue(loaded.automaticUpdateChecks)
        XCTAssertFalse(loaded.automaticFilterUpdateChecks)
        XCTAssertEqual(loaded.seekSeconds, 30)
        XCTAssertEqual(loaded.holdSpeed, 3)
        XCTAssertEqual(loaded.wifiQuality, 2160)
        XCTAssertEqual(loaded.mobileQuality, 0)
        XCTAssertEqual(loaded.customDomains, settings.customDomains)
        loaded.restoreDefaults()
        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.appearance, .system)
        XCTAssertTrue(restored.saveHistory)
        XCTAssertFalse(restored.returnYouTubeDislike)
        XCTAssertFalse(restored.automaticUpdateChecks)
        XCTAssertTrue(restored.automaticFilterUpdateChecks)
        XCTAssertEqual(restored.seekSeconds, 10)
        XCTAssertEqual(restored.customDomains, "")
    }

    @MainActor
    func testOlderPartialSettingsUseDefaultsForNewFields() async throws {
        let defaults = try isolatedDefaults()
        defaults.set(Data(#"{"appearance":"light","saveHistory":false}"#.utf8), forKey: "test")
        let settings = AppSettings(defaults: defaults, key: "test")
        XCTAssertEqual(settings.appearance, .light)
        XCTAssertFalse(settings.saveHistory)
        XCTAssertEqual(settings.seekSeconds, 10)
        XCTAssertEqual(settings.mobileQuality, 720)
        XCTAssertFalse(settings.returnYouTubeDislike)
        XCTAssertFalse(settings.automaticUpdateChecks)
        XCTAssertTrue(settings.automaticFilterUpdateChecks)
        XCTAssertNil(settings.storageError)
    }

    @MainActor
    func testInvalidPersistedChoicesDoNotEscapeSupportedRanges() async throws {
        let defaults = try isolatedDefaults()
        defaults.set(Data(#"{"appearance":"unknown","seekSeconds":999,"holdSpeed":99,"wifiQuality":4320,"mobileQuality":-1,"saveHistory":false}"#.utf8), forKey: "test")
        let settings = AppSettings(defaults: defaults, key: "test")
        XCTAssertEqual(settings.appearance, .system)
        XCTAssertEqual(settings.seekSeconds, 10)
        XCTAssertEqual(settings.holdSpeed, 2)
        XCTAssertEqual(settings.wifiQuality, 1080)
        XCTAssertEqual(settings.mobileQuality, 720)
        XCTAssertFalse(settings.saveHistory)
    }

    @MainActor
    func testCorruptSettingsSurfaceFailureAndPreserveSafeDefaults() async throws {
        let defaults = try isolatedDefaults()
        defaults.set(Data("{broken json".utf8), forKey: "test")
        let settings = AppSettings(defaults: defaults, key: "test")
        XCTAssertNotNil(settings.storageError)
        XCTAssertEqual(settings.appearance, .system)
        XCTAssertFalse(settings.returnYouTubeDislike)
        settings.restoreDefaults()
        XCTAssertNil(settings.storageError)
        XCTAssertNil(AppSettings(defaults: defaults, key: "test").storageError)
    }
}
