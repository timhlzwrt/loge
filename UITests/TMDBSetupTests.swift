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
        let settings = app.tabBars.buttons["Settings"].firstMatch
        (settings.exists ? settings : app.buttons["Settings"].firstMatch).tap()
        let connect = app.buttons["Connect TMDB"].firstMatch
        for _ in 0..<8 {
            if connect.exists && connect.isHittable { break }
            app.swipeUp()
        }
        guard connect.exists else { throw XCTSkip("A token is already configured on this device.") }
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
