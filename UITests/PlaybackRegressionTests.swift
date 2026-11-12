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
        // Paused, a skip to the very end used to leave mpv short of it, so Up Next never counted down.
        if !app.buttons["Pause"].isHittable { app.tap() }
        app.buttons["Pause"].tap()
        app.buttons["Skip Credits"].tap()
        let creditsEnded = expectation(for: NSPredicate { _, _ in
            app.staticTexts["fixture-ended"].value as? String == "yes"
        }, evaluatedWith: app)
        wait(for: [creditsEnded], timeout: 5)
        XCTAssertFalse(app.buttons["Skip Credits"].exists, "The offer stayed after skipping")
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

    /// A position from a longer source lies past the end of a shorter one, where mpv opens it.
    @MainActor
    func testSwitchingToAShorterSourceDoesNotFinishTheEpisode() throws {
        guard let url = ProcessInfo.processInfo.environment["PLAYBACK_FIXTURE_URL"],
              let shorter = ProcessInfo.processInfo.environment["PLAYBACK_FIXTURE_SHORT_URL"] else {
            throw XCTSkip("Set TEST_RUNNER_PLAYBACK_FIXTURE_URL and TEST_RUNNER_PLAYBACK_FIXTURE_SHORT_URL (a clip under 30 s).")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--playback-ui-test"]
        app.launchEnvironment["PLAYBACK_FIXTURE_URL"] = url
        app.launchEnvironment["PLAYBACK_FIXTURE_SHORT_URL"] = shorter
        app.launchEnvironment["PLAYBACK_FIXTURE_PROGRESS_ID"] = "short-source-fixture-\(UUID().uuidString)"
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
        app.buttons["Seek fixture to 35 seconds"].tap()
        let advanced = expectation(for: NSPredicate { _, _ in
            (Int(position.value as? String ?? "") ?? -1) >= 36
        }, evaluatedWith: app)
        wait(for: [advanced], timeout: 15)
        app.buttons["Replace with shorter source"].tap()
        // Playing again from near the shorter file's end, not stopped on its last frame.
        let playing = expectation(for: NSPredicate { _, _ in
            app.staticTexts["fixture-ended"].value as? String == "no"
                && (Int(position.value as? String ?? "") ?? Int.max) < 8
        }, evaluatedWith: app)
        wait(for: [playing], timeout: 15)
        let saved = Int(app.staticTexts["fixture-saved-position"].firstMatch.value as? String ?? "") ?? -1
        XCTAssertGreaterThanOrEqual(saved, 35, "The longer source's position is kept, not replaced by the shorter one's end")
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
        XCTAssertGreaterThan(pictureBrightness(), 20, "No picture after returning")
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

    /// Choices made while paused, so the controls' auto-hide can't close the menus under the test.
    @MainActor
    func testAudioAndSubtitleChangesKeepThePositionAndPlaying() throws {
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
        wait(for: [expectation(for: NSPredicate { _, _ in
            (Int(position.value as? String ?? "") ?? -1) >= 2
        }, evaluatedWith: app)], timeout: 15)
        if !app.buttons["Pause"].isHittable { app.tap() }
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
        let paused = try XCTUnwrap(Int(position.value as? String ?? ""))

        app.buttons["Audio"].tap()
        let german = app.buttons.matching(NSPredicate(format: "label CONTAINS 'German' OR label CONTAINS 'Deutsch'")).firstMatch
        XCTAssertTrue(german.waitForExistence(timeout: 5))
        german.tap()
        wait(for: [expectation(for: NSPredicate(format: "value == 'de'"),
                               evaluatedWith: app.staticTexts["fixture-audio"])], timeout: 10)

        app.buttons["Subtitles"].tap()
        let subtitle = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Stream'")).firstMatch
        XCTAssertTrue(subtitle.waitForExistence(timeout: 5))
        subtitle.tap()
        let subtitleSelected = NSPredicate { _, _ in
            ["en", "eng"].contains(app.staticTexts["fixture-subtitle"].value as? String ?? "")
        }
        wait(for: [expectation(for: subtitleSelected, evaluatedWith: app)], timeout: 10)
        XCTAssertFalse(app.alerts.firstMatch.exists)

        let afterChanges = Int(position.value as? String ?? "") ?? -1
        XCTAssertLessThanOrEqual(abs(afterChanges - paused), 1, "Changing tracks moved the position")
        app.buttons["Play"].tap()
        wait(for: [expectation(for: NSPredicate { _, _ in
            (Int(position.value as? String ?? "") ?? -1) >= paused + 3
        }, evaluatedWith: app)], timeout: 10)
        XCTAssertEqual(app.staticTexts["fixture-audio"].value as? String, "de")
        if !app.buttons["Close"].isHittable { app.tap() }
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Play fixture"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testBackgroundWhilePlayingRestoresPictureTimelineAndSync() throws {
        try checkRecovery(named: "background") {
            XCUIDevice.shared.press(.home)
        }
    }

    /// The simulator's lock button. It proves the app's path through a lock, not what a
    /// real screen turning off does to AVFoundation's renderer.
    @MainActor
    func testSimulatorLockWhilePlayingRestoresPictureTimelineAndSync() throws {
        let lock = NSSelectorFromString("pressLockButton")
        guard XCUIDevice.shared.responds(to: lock) else { throw XCTSkip("This simulator has no lock button.") }
        try checkRecovery(named: "lock") {
            XCUIDevice.shared.perform(lock)
        }
    }

    @MainActor
    private func checkRecovery(named name: String, leave: () -> Void) throws {
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
        wait(for: [expectation(for: NSPredicate { _, _ in
            (Int(position.value as? String ?? "") ?? -1) >= 3
        }, evaluatedWith: app)], timeout: 15)
        XCTAssertGreaterThan(pictureBrightness(), 20, "No picture before leaving")
        screenshot("\(name)-before")

        leave()
        // A floating window keeps the app reported as in the foreground, so this can only wait.
        _ = app.wait(for: .runningBackground, timeout: 5)
        sleep(3)
        screenshot("\(name)-away")
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        // The window that opens by itself on going Home closes again on coming back.
        XCTAssertTrue(position.waitForExistence(timeout: 10), "The player screen didn't come back")
        screenshot("\(name)-returned")
        if !app.buttons["Close"].isHittable { app.tap() }

        // Without Picture in Picture, as on iPhone simulators, leaving pauses playback.
        if app.buttons["Play"].waitForExistence(timeout: 3) {
            let restored = expectation(for: NSPredicate { [self] _, _ in pictureBrightness() > 20 }, evaluatedWith: app)
            wait(for: [restored], timeout: 5)
            screenshot("\(name)-paused")
            app.buttons["Play"].tap()
        }
        let resumedFrom = Int(position.value as? String ?? "") ?? -1
        wait(for: [expectation(for: NSPredicate { _, _ in
            (Int(position.value as? String ?? "") ?? -1) >= resumedFrom + 3
        }, evaluatedWith: app)], timeout: 10)
        XCTAssertGreaterThan(pictureBrightness(), 20, "No picture after returning")
        screenshot("\(name)-playing")
        let offset = try XCTUnwrap(Double(app.staticTexts["fixture-av-sync"].value as? String ?? ""), "mpv reported no A/V offset")
        XCTAssertLessThan(offset, 0.1, "Sound and picture drifted apart")

        if !app.buttons["Pause"].isHittable { app.tap() }
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5), "Controls stopped responding")
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Play fixture"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testFailureExplainsItselfAndTriesAgain() throws {
        guard let url = ProcessInfo.processInfo.environment["PLAYBACK_FIXTURE_URL"] else {
            throw XCTSkip("Set TEST_RUNNER_PLAYBACK_FIXTURE_URL for the isolated playback fixture.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--playback-ui-test"]
        app.launchEnvironment["PLAYBACK_FIXTURE_URL"] = url + "?fail-once=\(UUID().uuidString)"
        app.launch()
        defer { app.terminate() }
        app.buttons["Play fixture"].tap()
        XCTAssertTrue(app.staticTexts["Couldn't play this source"].waitForExistence(timeout: 30))
        screenshot("failure")
        XCTAssertFalse(app.staticTexts["Loading failed."].exists)
        app.buttons["Try Again"].tap()
        let position = app.staticTexts["fixture-position"]
        wait(for: [expectation(for: NSPredicate { _, _ in
            (Int(position.value as? String ?? "") ?? -1) >= 1
        }, evaluatedWith: app)], timeout: 15)
        XCTAssertFalse(app.staticTexts["Couldn't play this source"].exists)
    }

    /// A link that never starts sending gives up after 20 seconds with an explanation, rather than spinning.
    @MainActor
    func testOpeningTimeoutExplainsItself() throws {
        guard let url = ProcessInfo.processInfo.environment["PLAYBACK_FIXTURE_URL"] else {
            throw XCTSkip("Set TEST_RUNNER_PLAYBACK_FIXTURE_URL for the isolated playback fixture.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--playback-ui-test"]
        app.launchEnvironment["PLAYBACK_FIXTURE_URL"] = url + "?hang=\(UUID().uuidString)"
        app.launch()
        defer { app.terminate() }
        app.buttons["Play fixture"].tap()
        XCTAssertTrue(app.staticTexts["Couldn't play this source"].waitForExistence(timeout: 35))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'The server hasn’t started' OR label BEGINSWITH \"The server hasn't started\"")).firstMatch.exists)
        screenshot("open-timeout")
        XCTAssertTrue(app.buttons["Try Again"].exists)
    }

    /// The buttons sit beside the title above the timeline in iPhone landscape, and every menu's actions can be reached.
    @MainActor
    func testPhoneLandscapeControlsAndMenus() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("iPhone layout.") }
        guard let url = ProcessInfo.processInfo.environment["PLAYBACK_FIXTURE_URL"] else {
            throw XCTSkip("Set TEST_RUNNER_PLAYBACK_FIXTURE_URL for the isolated playback fixture.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--playback-ui-test"]
        app.launchEnvironment["PLAYBACK_FIXTURE_URL"] = url
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        app.buttons["Play fixture"].tap()
        let position = app.staticTexts["fixture-position"]
        XCTAssertTrue(position.waitForExistence(timeout: 30))
        wait(for: [expectation(for: NSPredicate { _, _ in
            (Int(position.value as? String ?? "") ?? -1) >= 2
        }, evaluatedWith: app)], timeout: 15)
        if !app.buttons["Pause"].isHittable { app.tap() }
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
        screenshot("phone-landscape-controls")

        app.buttons["Audio"].tap()
        let timing = app.buttons["Audio Timing…"]
        XCTAssertTrue(timing.waitForExistence(timeout: 5))
        screenshot("phone-landscape-audio-menu")
        XCTAssertTrue(timing.isHittable, "Audio Timing is below the visible rows")
        timing.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
        screenshot("phone-landscape-timing-panel")
        app.buttons["Done"].tap()

        let timeline = app.sliders["Playback position"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(app.buttons["Audio"].frame.maxY, timeline.frame.minY, "Buttons aren't above the timeline")

        XCTAssertTrue(app.buttons["Zoom to Fill"].isHittable)
        app.buttons["Zoom to Fill"].tap()
        XCTAssertTrue(app.buttons["Fit to Screen"].waitForExistence(timeout: 3))
        screenshot("phone-landscape-zoomed")
        app.buttons["Fit to Screen"].tap()

        app.buttons["More"].tap()
        let info = app.buttons["Playback Info…"]
        XCTAssertTrue(info.waitForExistence(timeout: 5))
        screenshot("phone-landscape-more-menu")
        XCTAssertTrue(info.isHittable, "Playback Info is below the visible rows")
        info.tap()
        XCTAssertTrue(app.staticTexts["Playback Info"].waitForExistence(timeout: 5))
        screenshot("phone-landscape-playback-info")
    }

    /// Average brightness (0–255) left of centre, clear of the controls: near black when
    /// the video layer has stopped drawing.
    @MainActor
    private func pictureBrightness() -> Double {
        guard let image = XCUIScreen.main.screenshot().image.cgImage else { return 0 }
        let area = CGRect(x: Double(image.width) * 0.1, y: Double(image.height) * 0.45,
                          width: Double(image.width) * 0.2, height: Double(image.height) * 0.1)
        guard let crop = image.cropping(to: area),
              let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 1,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return 0 }
        context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return context.data.map { Double($0.load(as: UInt8.self)) } ?? 0
    }
}
#endif
