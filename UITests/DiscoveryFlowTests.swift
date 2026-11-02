#if os(iOS)
import XCTest

/// On-demand discovery checks. Provider downtime is asserted as an explicit retryable state.
final class DiscoveryFlowTests: XCTestCase {
    @MainActor
    func testFestivalOpensRecordedWinnersOrProviderError() throws {
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
        XCTAssertTrue(app.staticTexts["Palme d’Or winners"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Source: Wikidata · Records may be incomplete."].exists)
        let loaded = NSPredicate { _, _ in
            app.buttons["Retry"].exists || app.otherElements["collection-films"].exists
                || app.staticTexts["No films are recorded for this collection yet."].exists
        }
        expectation(for: loaded, evaluatedWith: app)
        waitForExpectations(timeout: 40)
        screenshot("discovery-cannes")

        app.navigationBars.buttons.firstMatch.tap()
        let director = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Christopher Nolan'")).firstMatch
        for _ in 0..<3 {
            if director.exists && director.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(director.waitForExistence(timeout: 5))
        screenshot("discovery-directors")
        let festivals = app.scrollViews["festival-collections"]
        let lastFestival = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'San Sebastián'")).firstMatch
        for _ in 0..<5 {
            festivals.swipeLeft(velocity: .fast)
        }
        XCTAssertTrue(lastFestival.exists)
        screenshot("discovery-more-festivals")
        director.tap()
        XCTAssertTrue(app.staticTexts["Directed films, newest first."].waitForExistence(timeout: 5))
        let films = XCTNSPredicateExpectation(predicate: loaded, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [films], timeout: 40), .completed)
        screenshot("discovery-director-films")
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
