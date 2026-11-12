#if os(iOS)
import XCTest

/// Details' Cast & Crew and Information against live Cinemeta, on request like `FlowTests`:
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
    func testDirectorPageSaysTheFilmographyNeedsTMDB() {
        // Without TMDB there's no filmography: Cinemeta's search no longer says who worked on what.
        // TMDBFilmographyTests covers the TMDB filmography.
        open("Interstellar")
        screenshot("details-movie-top")
        XCTAssertTrue(app.staticTexts["Cast & Crew"].waitForExistence(timeout: 15))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Information"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Awards"].exists)
        screenshot("details-movie-credits")

        person("Christopher Nolan").tap()
        XCTAssertTrue(app.staticTexts["Filmography needs TMDB"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Connect TMDB in Settings to list Christopher Nolan's films and series."].exists)
        XCTAssertTrue(app.staticTexts["Credited on"].exists)
        XCTAssertTrue(app.buttons["Interstellar"].exists)
        // The name heads the page once, beside the statement, not again in the navigation bar.
        XCTAssertEqual(app.staticTexts.matching(identifier: "Christopher Nolan").count, 1)
        screenshot("person-director")
    }

    @MainActor
    func testActorPageKeepsTheSeriesTheyWereFoundOn() {
        open("Breaking Bad")
        XCTAssertTrue(app.staticTexts["Cast & Crew"].waitForExistence(timeout: 15))
        app.swipeUp()
        screenshot("details-series-credits")

        person("Bryan Cranston").tap()
        XCTAssertTrue(app.staticTexts["Credited on"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Breaking Bad"].exists)
        screenshot("person-actor")
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

    @MainActor
    private func person(_ name: String) -> XCUIElement {
        let button = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "\(name) isn't in Cast & Crew")
        return button
    }
}
#endif
