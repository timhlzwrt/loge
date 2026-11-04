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
    func testEpisodePausePersistsAndResumesAfterRelaunch() throws {
        guard let url = ProcessInfo.processInfo.environment["PLAYBACK_FIXTURE_URL"] else {
            throw XCTSkip("Set TEST_RUNNER_PLAYBACK_FIXTURE_URL for the isolated playback fixture.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--playback-ui-test"]
        app.launchEnvironment["PLAYBACK_FIXTURE_URL"] = url
        app.launchEnvironment["PLAYBACK_FIXTURE_PROGRESS_ID"] = "progress-fixture-\(UUID().uuidString)"
        app.launch()
        defer {
            app.terminate()
            app.launch()
            app.buttons["Remove fixture progress"].tap()
            app.terminate()
        }
        app.buttons["Play fixture"].tap()
        let position = app.staticTexts["fixture-position"]
        XCTAssertTrue(position.waitForExistence(timeout: 30))
        let opened = expectation(for: NSPredicate { _, _ in
            (Int(position.value as? String ?? "") ?? -1) >= 1
        }, evaluatedWith: app)
        wait(for: [opened], timeout: 15)
        let seek = app.buttons["Seek fixture to 35 seconds"]
        XCTAssertTrue(seek.waitForExistence(timeout: 5))
        seek.tap()
        let advanced = expectation(for: NSPredicate { _, _ in
            (Int(position.value as? String ?? "") ?? -1) >= 37
        }, evaluatedWith: app)
        wait(for: [advanced], timeout: 15)
        if !app.buttons["Pause"].isHittable { app.tap() }
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
        let paused = try XCTUnwrap(Int(position.value as? String ?? ""))
        let saved = app.staticTexts["fixture-saved-position"].firstMatch
        let persisted = expectation(for: NSPredicate { _, _ in
            (Int(saved.value as? String ?? "") ?? -1) == paused
        }, evaluatedWith: app)
        wait(for: [persisted], timeout: 5)
        app.terminate()
        app.launch()
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        XCTAssertEqual(Int(saved.value as? String ?? ""), paused)
        app.buttons["Play fixture"].tap()
        XCTAssertTrue(position.waitForExistence(timeout: 30))
        let resumed = expectation(for: NSPredicate { _, _ in
            (Int(position.value as? String ?? "") ?? -1) >= paused - 5
        }, evaluatedWith: app)
        wait(for: [resumed], timeout: 10)
        XCTAssertLessThan(Int(position.value as? String ?? "") ?? Int.max, paused + 5)
        if !app.buttons["Close"].isHittable { app.tap() }
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Play fixture"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRemoteEpisodeResumeUsesRealDurationDespiteEarlyLocalProgress() throws {
        guard let url = ProcessInfo.processInfo.environment["PLAYBACK_FIXTURE_URL"] else {
            throw XCTSkip("Set TEST_RUNNER_PLAYBACK_FIXTURE_URL for the isolated playback fixture.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--playback-ui-test"]
        app.launchEnvironment["PLAYBACK_FIXTURE_URL"] = url
        app.launchEnvironment["PLAYBACK_FIXTURE_PROGRESS_ID"] = "remote-progress-fixture-\(UUID().uuidString)"
        app.launch()
        defer {
            app.terminate()
            app.launch()
            app.buttons["Remove fixture progress"].tap()
            app.terminate()
        }
        // 50% of an estimated 45-minute episode must become 25s in the 60s fixture,
        // including the five-second rewind, even if a local save replaces the estimate.
        app.buttons["Play remote fixture"].tap()
        let position = app.staticTexts["fixture-position"]
        XCTAssertTrue(position.waitForExistence(timeout: 30))
        let resumed = expectation(for: NSPredicate { _, _ in
            let seconds = Int(position.value as? String ?? "") ?? -1
            return seconds >= 25 && seconds < 30
        }, evaluatedWith: app)
        wait(for: [resumed], timeout: 15)
        if !app.buttons["Pause"].isHittable { app.tap() }
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
        let paused = try XCTUnwrap(Int(position.value as? String ?? ""))
        XCTAssertGreaterThanOrEqual(paused, 25)
        XCTAssertLessThan(paused, 35)
        XCTAssertEqual(app.staticTexts["fixture-ended"].value as? String, "no")
        let saved = app.staticTexts["fixture-saved-position"].firstMatch
        let persisted = expectation(for: NSPredicate { _, _ in
            (Int(saved.value as? String ?? "") ?? -1) == paused
        }, evaluatedWith: app)
        wait(for: [persisted], timeout: 5)
        app.buttons["Replace fixture source"].tap()
        let replacement = expectation(for: NSPredicate { _, _ in
            (app.staticTexts["fixture-source"].value as? String) == "source=second"
                && (Int(position.value as? String ?? "") ?? -1) >= paused - 1
        }, evaluatedWith: app)
        wait(for: [replacement], timeout: 15)
        XCTAssertLessThan(Int(position.value as? String ?? "") ?? Int.max, paused + 5)
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

    @MainActor
    func testBackgroundRestoresPausedVideoAndPlayback() throws {
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
        let position = app.staticTexts["fixture-position"]
        XCTAssertTrue(position.waitForExistence(timeout: 30))
        let started = expectation(for: NSPredicate { _, _ in
            (Int(position.value as? String ?? "") ?? -1) >= 3
        }, evaluatedWith: app)
        wait(for: [started], timeout: 15)
        if !app.buttons["Pause"].isHittable { app.tap() }
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
        let before = Int(position.value as? String ?? "") ?? -1
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(position.waitForExistence(timeout: 10))
        if !app.buttons["Play"].isHittable { app.tap() }
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
        let restored = expectation(for: NSPredicate { _, _ in
            let current = Int(position.value as? String ?? "") ?? -1
            return current >= before - 1 && current <= before + 1
        }, evaluatedWith: app)
        wait(for: [restored], timeout: 10)
        let pausedScreenshot = XCTAttachment(screenshot: app.screenshot())
        pausedScreenshot.name = "Paused video after background recovery"
        pausedScreenshot.lifetime = .keepAlways
        add(pausedScreenshot)
        app.buttons["Play"].tap()
        let advanced = expectation(for: NSPredicate { _, _ in
            (Int(position.value as? String ?? "") ?? -1) > before + 1
        }, evaluatedWith: app)
        wait(for: [advanced], timeout: 10)
        let playingScreenshot = XCTAttachment(screenshot: app.screenshot())
        playingScreenshot.name = "Playing video after background recovery"
        playingScreenshot.lifetime = .keepAlways
        add(playingScreenshot)
        if !app.buttons["Close"].isHittable { app.tap() }
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Play fixture"].waitForExistence(timeout: 5))
    }

}
#endif
