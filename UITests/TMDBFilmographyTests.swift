#if os(iOS)
import XCTest

final class TMDBFilmographyTests: XCTestCase {
    @MainActor
    func testTitleInformationAndFullActorCredits() throws {
        guard ProcessInfo.processInfo.environment["UI_FLOWS"] != nil,
              let credentialPath = ProcessInfo.processInfo.environment["TMDB_TEST_TOKEN_FILE"] else {
            throw XCTSkip("Requires UI flows and a temporary TMDB credential file.")
        }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments += ["--tmdb-ui-test"]
        app.launchEnvironment["TMDB_TEST_TOKEN_FILE"] = credentialPath
        app.launch()
        defer { app.terminate() }
        let search = app.tabBars.buttons["Search"].firstMatch
        (search.exists ? search : app.buttons["Search"].firstMatch).tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("interstellar")
        let movie = app.buttons["Interstellar"].firstMatch
        XCTAssertTrue(movie.waitForExistence(timeout: 30))
        movie.tap()
        let actor = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Matthew McConaughey'")).firstMatch
        for _ in 0..<8 {
            if actor.exists && actor.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(actor.waitForExistence(timeout: 20))
        screenshot("tmdb-cast")
        let information = app.staticTexts["Original Language"]
        for _ in 0..<7 {
            if information.exists && information.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(information.waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["TMDB Rating"].exists)
        screenshot("tmdb-title-information")
        for _ in 0..<8 {
            if actor.isHittable { break }
            app.swipeDown()
        }
        actor.tap()
        XCTAssertTrue(app.staticTexts["Filmography"].waitForExistence(timeout: 30))
        let all = app.segmentedControls.buttons.matching(NSPredicate(format: "label BEGINSWITH 'All ('")).firstMatch
        XCTAssertTrue(all.exists)
        screenshot("tmdb-actor-filmography")
        let series = app.segmentedControls.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Series ('")).firstMatch
        series.tap()
        XCTAssertTrue(series.isSelected)
        screenshot("tmdb-actor-series")
        let credit = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Series ·'")).firstMatch
        for _ in 0..<4 {
            if credit.exists && credit.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(credit.waitForExistence(timeout: 10))
        credit.tap()
        let resolved = NSPredicate { _, _ in
            app.scrollViews["title-resolved-detail"].exists
                || app.otherElements["title-resolved-detail"].exists
                || app.staticTexts["TMDB has no IMDb ID for this title. Playback and saving are unavailable."].exists
        }
        expectation(for: resolved, evaluatedWith: app)
        waitForExpectations(timeout: 30)
        screenshot("tmdb-credit-opened")
    }

    @MainActor
    func testDiscoveryDirectorOpensTMDBCredits() throws {
        guard ProcessInfo.processInfo.environment["UI_FLOWS"] != nil,
              let credentialPath = ProcessInfo.processInfo.environment["TMDB_TEST_TOKEN_FILE"] else {
            throw XCTSkip("Requires UI flows and a temporary TMDB credential file.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--tmdb-ui-test"]
        app.launchEnvironment["TMDB_TEST_TOKEN_FILE"] = credentialPath
        app.launch()
        defer { app.terminate() }
        let home = app.tabBars.buttons["Home"].firstMatch
        (home.exists ? home : app.buttons["Home"].firstMatch).tap()
        let director = app.scrollViews["popular-directors"].buttons.firstMatch
        for _ in 0..<22 {
            if director.exists && director.isHittable { break }
            app.swipeUp(velocity: .fast)
        }
        XCTAssertTrue(director.waitForExistence(timeout: 10))
        director.tap()
        XCTAssertTrue(app.staticTexts["Filmography"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.segmentedControls.buttons.matching(NSPredicate(format: "label BEGINSWITH 'All ('")).firstMatch.exists)
        screenshot("tmdb-director-filmography")
    }
}
#endif
