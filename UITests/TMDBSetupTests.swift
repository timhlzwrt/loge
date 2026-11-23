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
        // The Settings tab is a button with this name on iPhone and iPad.
        let settings = app.buttons["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Cast and Recommendations'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "No Cast and Recommendations control in Settings")
        guard row.label.contains("Off") else { throw XCTSkip("A token is already configured on this device.") }
        // Off, the control opens the token sheet directly.
        row.tap()
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
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Off"), "Cancelling connected TMDB")
        let about = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'About loge'")).firstMatch
        XCTAssertTrue(about.waitForExistence(timeout: 5))
        about.tap()
        let dataSources = app.buttons["Data Sources"]
        XCTAssertTrue(dataSources.waitForExistence(timeout: 5))
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
