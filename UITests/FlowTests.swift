#if os(iOS)
import XCTest

/// End-to-end checks of browsing flows against live addons. They need the network,
/// Cinemeta, and for playback the local test addon (Tools/test-addon.py) installed, so
/// they only run on request. Screenshots go to `SCREENSHOT_DIR` when it's set:
///
///     TEST_RUNNER_UI_FLOWS=1 TEST_RUNNER_SCREENSHOT_DIR=/tmp/shots xcodebuild test \
///       -scheme MediaApp -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
///       -only-testing:MediaAppUITests/FlowTests
final class FlowTests: XCTestCase {
    private var app: XCUIApplication!

    @MainActor
    override func setUp() async throws {
        guard ProcessInfo.processInfo.environment["UI_FLOWS"] != nil else {
            throw XCTSkip("Set TEST_RUNNER_UI_FLOWS=1 to run.")
        }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launch()
    }

    @MainActor
    func testSearchFindsTitlesAndRemembersTheQuery() {
        app.tabBars.buttons["Search"].firstMatch.tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("batman")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Batman'")).firstMatch
            .waitForExistence(timeout: 15), "No results for batman")
        screenshot("search-results")

        field.typeText("zzqxjvw")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'No Results'")).firstMatch
            .waitForExistence(timeout: 15), "No empty state for a query without matches")
        screenshot("search-empty")

        // Searching from the keyboard remembers the query; clearing the field shows it.
        field.typeText("\n")
        field.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Recent Searches"].waitForExistence(timeout: 5))
        screenshot("search-recent")
    }

    @MainActor
    func testMarkingAnEpisodeWatchedAndUnwatched() {
        openSeries("Lanterns")
        // The row opens scrolled to Up Next, which is always on screen. Marking it changes
        // what's Up Next, so the card is then found by its episode number.
        let upNext = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Up Next'")).firstMatch
        XCTAssertTrue(upNext.waitForExistence(timeout: 15))
        let number = upNext.label.firstMatch(of: #/Episode (\d+)/#)?.1 ?? ""
        let episode = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Episode \(number),")).firstMatch
        episode.press(forDuration: 2.5)
        screenshot("episode-menu")
        let markWatched = app.buttons["Mark as Watched"]
        let markUnwatched = app.buttons["Mark as Unwatched"]
        XCTAssertTrue(markWatched.waitForExistence(timeout: 3) || markUnwatched.exists)
        let wasWatched = markUnwatched.exists
        (wasWatched ? markUnwatched : markWatched).tap()
        screenshot("episode-marked")

        // The menu now offers the opposite action.
        episode.press(forDuration: 2.5)
        XCTAssertTrue((wasWatched ? markWatched : markUnwatched).waitForExistence(timeout: 3))
        (wasWatched ? markWatched : markUnwatched).tap()
    }

    @MainActor
    func testClosingAutoplayReturnsToDetails() {
        openSeries("Lanterns")
        let play = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Play' OR label BEGINSWITH 'Resume'")).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 15))
        play.tap()
        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 20), "Player didn't open")
        close.tap()
        XCTAssertTrue(app.buttons["Season options"].waitForExistence(timeout: 5),
                      "Closing the player didn't return to the details screen")
        screenshot("after-close")
    }

    @MainActor
    func testLandscapeAndPullToRefresh() {
        XCTAssertTrue(app.staticTexts["Popular Movies"].waitForExistence(timeout: 15))
        app.swipeDown()
        XCTAssertTrue(app.staticTexts["Popular Movies"].waitForExistence(timeout: 15), "Rows gone after refresh")

        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        screenshot("landscape-home")
        XCUIDevice.shared.orientation = .portrait
        openSeries("Lanterns")
        XCTAssertTrue(app.buttons["Season options"].waitForExistence(timeout: 15))
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(3)
        screenshot("landscape-details")
        XCUIDevice.shared.orientation = .portrait
    }

    /// The picture should fill the new size after each turn; check the screenshots.
    @MainActor
    func testRotatingDuringPlayback() {
        openSeries("Lanterns")
        let play = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Play' OR label BEGINSWITH 'Resume'")).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 15))
        play.tap()
        let pause = app.buttons["Pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 20), "Playback didn't start")

        // The test clips are 10 seconds long, so both turns happen well before the end.
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(1)
        screenshot("rotated-while-playing")

        // A tap toggles the controls, so only tap when they're hidden.
        if !pause.isHittable { app.tap() }
        XCTAssertTrue(pause.waitForExistence(timeout: 3), "Player closed when rotated")
        pause.tap()
        XCUIDevice.shared.orientation = .portrait
        sleep(2)
        screenshot("rotated-while-paused")
        app.buttons["Close"].tap()
    }

    // MARK: Helpers

    @MainActor
    private func openSeries(_ name: String) {
        app.tabBars.buttons["Home"].firstMatch.tap()
        let poster = app.buttons[name].firstMatch
        for _ in 0..<6 where !poster.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(poster.waitForExistence(timeout: 15), "\(name) isn't on Home")
        poster.tap()
    }

    @MainActor
    private func screenshot(_ name: String) {
        guard let directory = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] else { return }
        let url = URL(fileURLWithPath: directory).appending(path: "\(name).png")
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
    }
}
#endif
