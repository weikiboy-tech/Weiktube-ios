// SPDX-License-Identifier: GPL-3.0-only
import XCTest

final class WeiktubeUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launchOffline() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.home"].waitForExistence(timeout: 10))
        return app
    }

    func testNativeTabsRemainAvailableWithoutNetworkOrOAuth() {
        let app = launchOffline()
        for identifier in ["tab.adblock", "tab.subscriptions", "tab.you", "tab.shorts", "tab.home"] {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.exists, identifier)
            button.tap()
            XCTAssertTrue(button.isSelected, identifier)
            XCTAssertTrue(app.buttons["tab.home"].exists)
        }
    }

    func testMaliciousLinkShowsValidationErrorWithoutOpeningAPlayer() {
        let app = launchOffline()
        app.buttons["Weitere Optionen"].tap()
        app.buttons["Video-Link öffnen"].tap()
        let field = app.descendants(matching: .any).matching(identifier: "link.input").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("javascript:alert(1)")
        app.buttons["link.open"].tap()
        let alert = app.alerts["Weiktube"]
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        XCTAssertTrue(alert.staticTexts["Kein unterstützter Link. Verwende einen YouTube-Link oder ein direktes öffentliches HTTPS-Video."].exists)
        alert.buttons["OK"].tap()
        XCTAssertTrue(app.buttons["tab.home"].exists)
    }

    func testSearchSheetAcceptsTextAndCanBeCancelledOffline() {
        let app = launchOffline()
        app.buttons["YouTube durchsuchen"].tap()
        let field = app.textFields["search.input"]
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText("Weiktube")
        XCTAssertTrue(app.buttons["Suchen"].isEnabled)
        app.buttons["Fertig"].tap()
        XCTAssertTrue(app.buttons["tab.home"].exists)
    }
}
