#if os(iOS)
import XCTest

final class PlaybackRegressionTests: XCTestCase {
    @MainActor
    func testCloseTimelineSkipsAudioAndSourceReplacement() throws {
        guard let url = ProcessInfo.processInfo.environment["PLAYBACK_FIXTURE_URL"] else {
            throw XCTSkip("Set TEST_RUNNER_PLAYBACK_FIXTURE_URL for the isolated playback fixture.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--playback-ui-test"]
        app.launchEnvironment["PLAYBACK_FIXTURE_URL"] = url
        app.launch()
        defer { app.terminate() }
        app.buttons["Play fixture"].tap()
        let intro = app.buttons["Skip Intro"]
        XCTAssertTrue(intro.waitForExistence(timeout: 30))
        let position = app.staticTexts["fixture-position"]
        let initial = Int(position.value as? String ?? "") ?? -1
        let advanced = expectation(for: NSPredicate { _, _ in
            (Int(position.value as? String ?? "") ?? -1) > initial
        }, evaluatedWith: app)
        wait(for: [advanced], timeout: 8)
        let expected = app.staticTexts["fixture-expected-audio"].value as? String
        if let expected, !expected.isEmpty {
            XCTAssertEqual(app.staticTexts["fixture-audio"].value as? String, expected)
        }
        intro.tap()
        XCTAssertTrue(app.buttons["Skip Recap"].waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(Int(position.value as? String ?? "") ?? -1, 19)
        app.buttons["Skip Recap"].tap()
        let recapEnded = expectation(for: NSPredicate { _, _ in
            (Int(position.value as? String ?? "") ?? -1) >= 39
        }, evaluatedWith: app)
        wait(for: [recapEnded], timeout: 5)
        XCTAssertTrue(app.buttons["Skip Credits"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["fixture-ended"].value as? String, "no")
        app.buttons["Skip Credits"].tap()
        let creditsEnded = expectation(for: NSPredicate { _, _ in
            (Int(position.value as? String ?? "") ?? -1) >= 58
                || app.staticTexts["fixture-ended"].value as? String == "yes"
        }, evaluatedWith: app)
        wait(for: [creditsEnded], timeout: 5)
        if !app.buttons["Close"].isHittable { app.tap() }
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Play fixture"].waitForExistence(timeout: 5))
        app.buttons["Play fixture"].tap()
        XCTAssertTrue(app.buttons["Skip Intro"].waitForExistence(timeout: 30))
        app.buttons["Replace fixture source"].tap()
        XCTAssertTrue(app.staticTexts["fixture-source"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["fixture-source"].value as? String, "source=second")
        XCTAssertTrue(app.buttons["Skip Intro"].waitForExistence(timeout: 10))
        if !app.buttons["Close"].isHittable { app.tap() }
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Play fixture"].waitForExistence(timeout: 5))
    }
    @MainActor
    func testPictureInPictureRestoresTheSamePlayback() throws {
        guard let url = ProcessInfo.processInfo.environment["PLAYBACK_FIXTURE_URL"] else {
            throw XCTSkip("Set TEST_RUNNER_PLAYBACK_FIXTURE_URL for the isolated playback fixture.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--playback-ui-test"]
        app.launchEnvironment["PLAYBACK_FIXTURE_URL"] = url
        app.launch()
        defer { app.terminate() }
        app.buttons["Play fixture"].tap()
        XCTAssertTrue(app.buttons["Skip Intro"].waitForExistence(timeout: 30))
        let pip = app.buttons["Picture in Picture"]
        guard pip.waitForExistence(timeout: 10) else { throw XCTSkip("PiP isn't available on this device.") }
        let before = Int(app.staticTexts["fixture-position"].value as? String ?? "") ?? -1
        pip.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let restore = springboard.buttons.matching(NSPredicate(format: "label IN %@",
            ["Restore Full Screen", "Vollbildmodus wiederherstellen"])).firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 10))
        restore.tap()
        XCTAssertTrue(app.staticTexts["fixture-position"].waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(Int(app.staticTexts["fixture-position"].value as? String ?? "") ?? -1, before)
        if !app.buttons["Close"].isHittable { app.tap() }
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Play fixture"].waitForExistence(timeout: 5))
    }

}
#endif
