#if os(iOS)
import XCTest

/// On-demand discovery checks. Provider downtime is asserted as an explicit retryable state.
final class DiscoveryFlowTests: XCTestCase {
    @MainActor
    func testFestivalOpensLatestEditionAndRecordedWinners() throws {
        guard ProcessInfo.processInfo.environment["UI_FLOWS"] != nil else {
            throw XCTSkip("Set TEST_RUNNER_UI_FLOWS=1 to run.")
        }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()
        let home = app.tabBars.buttons["Home"].firstMatch
        (home.exists ? home : app.buttons["Home"].firstMatch).tap()
        let cannes = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Cannes'")).firstMatch
        for _ in 0..<16 {
            if cannes.exists && cannes.isHittable { break }
            app.swipeUp(velocity: .fast)
        }
        XCTAssertTrue(cannes.waitForExistence(timeout: 10))
        XCTAssertTrue(cannes.isHittable)
        screenshot("discovery-festivals")
        cannes.tap()
        XCTAssertTrue(app.staticTexts["2026 winners"].waitForExistence(timeout: 10))
        screenshot("discovery-cannes-latest")
        let watchLater = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Watch Later'")).firstMatch
        let latestFilm = app.otherElements["festival-films"].buttons.firstMatch
        XCTAssertTrue(latestFilm.waitForExistence(timeout: 10))
        latestFilm.tap()
        XCTAssertTrue(watchLater.waitForExistence(timeout: 20), "A latest winner didn't open its details")
        screenshot("discovery-cannes-latest-film")
        app.navigationBars.buttons.firstMatch.tap()
        let previous = app.buttons["Previous recorded winners"]
        for _ in 0..<12 {
            if previous.exists && previous.isHittable { break }
            app.swipeUp(velocity: .fast)
        }
        XCTAssertTrue(previous.isHittable)
        previous.tap()
        XCTAssertTrue(app.staticTexts["Palme d’Or winners"].waitForExistence(timeout: 10))
        let loaded = NSPredicate { _, _ in
            app.buttons["Retry"].exists || app.otherElements["collection-films"].exists
                || app.staticTexts["No films are recorded for this collection yet."].exists
        }
        expectation(for: loaded, evaluatedWith: app)
        waitForExpectations(timeout: 40)
        screenshot("discovery-cannes")
        let winner = app.otherElements["collection-films"].buttons.firstMatch
        if winner.exists {
            // These links were dead when the festival page was pushed as a view.
            winner.tap()
            XCTAssertTrue(watchLater.waitForExistence(timeout: 15), "A winner didn't open its details")
            screenshot("discovery-cannes-winner")
            app.navigationBars.buttons.firstMatch.tap()
        }

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
