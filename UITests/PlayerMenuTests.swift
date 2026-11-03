#if os(iOS)
import XCTest

/// Checks that player menus survive the controls' auto-hide. Needs the network and a
/// title in Continue Watching with a remembered source, so it only runs on request:
///
///     TEST_RUNNER_PLAYER_TESTS=1 xcodebuild test -scheme loge \
///       -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
///       -only-testing:logeUITests/PlayerMenuTests
final class PlayerMenuTests: XCTestCase {
    @MainActor
    func testMenuStaysOpenWhilePlaying() throws {
        guard ProcessInfo.processInfo.environment["PLAYER_TESTS"] != nil else {
            throw XCTSkip("Set TEST_RUNNER_PLAYER_TESTS=1 to run.")
        }
        let app = XCUIApplication()
        app.launch()

        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS 'min left'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), "Nothing in Continue Watching")
        card.tap()

        // The controls show while the stream loads, so the menu is reachable straight away.
        let options = app.buttons["Audio"]
        XCTAssertTrue(options.waitForExistence(timeout: 15))
        options.tap()
        XCTAssertTrue(app.buttons["Normal"].waitForExistence(timeout: 5), "Menu didn't open")

        // Long enough for playback to start and the 4-second auto-hide to pass.
        sleep(12)
        XCTAssertTrue(app.buttons["Normal"].exists, "Menu closed while playing")
        app.buttons["1,5×"].firstMatch.exists ? app.buttons["1,5×"].tap() : app.buttons["1.5×"].tap()
        sleep(1)
        XCTAssertFalse(app.buttons["Normal"].exists, "Menu stayed open after choosing")
    }
}
#endif
