#if os(iOS)
import XCTest

final class TMDBSetupTests: XCTestCase {
    @MainActor
    func testSetupRejectsMalformedTokenAndCancelsWithoutConnecting() throws {
        guard ProcessInfo.processInfo.environment["UI_FLOWS"] != nil else {
            throw XCTSkip("Set TEST_RUNNER_UI_FLOWS=1 to run.")
        }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()
        // iPad has a Settings tab, iPhone a gear on Home; both are buttons with this name.
        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'TMDB'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "No TMDB row in Settings")
        guard row.label.contains("Off") else { throw XCTSkip("A token is already configured on this device.") }
        row.tap()
        let connect = app.buttons["Connect TMDB"].firstMatch
        XCTAssertTrue(connect.waitForExistence(timeout: 5), "TMDB page has no Connect button")
        connect.tap()
        let token = app.secureTextFields["API Read Access Token"]
        XCTAssertTrue(token.waitForExistence(timeout: 5))
        screenshot("tmdb-setup")
        token.tap()
        token.typeText("invalid token")
        app.navigationBars.buttons["Connect TMDB"].tap()
        let error = app.staticTexts["TMDB didn't accept this token. Copy the API Read Access Token from your API settings and try again."]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        screenshot("tmdb-invalid-token")
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        let dataSources = app.buttons["Data Sources"]
        for _ in 0..<8 {
            if dataSources.exists && dataSources.isHittable { break }
            app.swipeUp()
        }
        dataSources.tap()
        let credits = app.staticTexts["This product uses the TMDB API but is not endorsed or certified by TMDB."]
        for _ in 0..<8 {
            if credits.exists && credits.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(credits.exists)
        screenshot("tmdb-credits")
    }
}
#endif
