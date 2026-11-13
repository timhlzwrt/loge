#if os(iOS)
import XCTest

/// Details without TMDB against live Cinemeta, on request like `FlowTests`:
///
///     TEST_RUNNER_UI_FLOWS=1 TEST_RUNNER_SCREENSHOT_DIR=/tmp/shots xcodebuild test \
///       -scheme loge -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
///       -only-testing:logeUITests/DetailsFlowTests
final class DetailsFlowTests: XCTestCase {
    private var app: XCUIApplication!

    @MainActor
    override func setUp() async throws {
        guard ProcessInfo.processInfo.environment["UI_FLOWS"] != nil else {
            throw XCTSkip("Set TEST_RUNNER_UI_FLOWS=1 to run.")
        }
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    @MainActor
    func testDetailsWithoutTMDBLeaveOutCastAndCrew() {
        // Needs a simulator with no TMDB token saved. TMDBFilmographyTests covers the pages with one.
        open("Interstellar")
        screenshot("details-movie-top")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Information"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Awards"].exists)
        XCTAssertFalse(app.staticTexts["Cast & Crew"].exists)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Connect TMDB in Settings for cast and crew, reviews and recommendations."]
            .waitForExistence(timeout: 5))
        screenshot("details-movie-information")
    }

    @MainActor
    private func open(_ title: String) {
        // iPhone shows a tab bar; iPad shows the tabs as plain buttons at the top.
        let tab = app.tabBars.buttons["Search"].firstMatch
        (tab.exists ? tab : app.buttons["Search"].firstMatch).tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(title)
        let result = app.buttons[title].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 20), "No search result for \(title)")
        result.tap()
    }
}
#endif
