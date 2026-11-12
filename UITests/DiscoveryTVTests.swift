#if os(tvOS)
import XCTest

final class DiscoveryTVTests: XCTestCase {
    /// The player has no on-screen buttons for the remote to land on, so what each press does
    /// is the behaviour to protect. Needs `Tools/test-addon.py`'s fixture, as on iOS.
    @MainActor
    func testPlayerRemoteReachesSkipPanelAndClose() throws {
        guard let url = ProcessInfo.processInfo.environment["PLAYBACK_FIXTURE_URL"] else {
            throw XCTSkip("Set TEST_RUNNER_PLAYBACK_FIXTURE_URL for the isolated playback fixture.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--playback-ui-test"]
        app.launchEnvironment["PLAYBACK_FIXTURE_URL"] = url
        app.launch()
        defer { app.terminate() }
        let remote = XCUIRemote.shared
        XCTAssertTrue(app.buttons["Play fixture"].waitForExistence(timeout: 10))
        remote.press(.select)
        let skip = app.buttons["Skip Intro"]
        XCTAssertTrue(skip.waitForExistence(timeout: 30))

        // An offer takes focus as it appears, so Select skips rather than pauses.
        waitForFocus(on: skip)
        screenshot("tv-skip-offer-focused")
        remote.press(.select)
        let recap = app.buttons["Skip Recap"]
        XCTAssertTrue(recap.waitForExistence(timeout: 5), "Skip didn't seek")
        XCTAssertGreaterThanOrEqual(Int(app.staticTexts["fixture-position"].value as? String ?? "") ?? -1, 19)

        // Focus stays on the next offer. Down from there reaches the panel either at once or by
        // way of the picture, depending on whether focus moves before the press is delivered.
        waitForFocus(on: recap)
        remote.press(.down)
        let tab = app.buttons["Subtitles"]
        if !tab.waitForExistence(timeout: 1) { remote.press(.down) }
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        waitForFocus(on: tab)
        remote.press(.down)
        let off = app.buttons["Off"]
        waitForFocus(on: off)
        remote.press(.down)
        let track = app.buttons["English · Stream"]
        waitForFocus(on: track)
        screenshot("tv-player-unselected-track-focused")

        remote.press(.menu)
        XCTAssertFalse(tab.waitForExistence(timeout: 2), "Menu didn't close the panel")
        // The page under the player stays in the accessibility tree, so check the player's own text.
        let position = app.staticTexts["fixture-position"]
        XCTAssertTrue(position.exists, "Menu closed the player with the panel open")
        remote.press(.menu)
        wait(for: [expectation(for: NSPredicate { _, _ in !position.exists }, evaluatedWith: position)], timeout: 5)
    }

    @MainActor
    private func launchPlayer(environment: [String: String] = [:]) throws -> XCUIApplication {
        guard let url = ProcessInfo.processInfo.environment["PLAYBACK_FIXTURE_URL"] else {
            throw XCTSkip("Set TEST_RUNNER_PLAYBACK_FIXTURE_URL for the isolated playback fixture.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--playback-ui-test"]
        app.launchEnvironment["PLAYBACK_FIXTURE_URL"] = url
        app.launchEnvironment.merge(environment) { _, new in new }
        app.launch()
        XCTAssertTrue(app.buttons["Play fixture"].waitForExistence(timeout: 10))
        XCUIRemote.shared.press(.select)
        return app
    }

    /// Up to the end of the file through the fixture's three skip offers.
    @MainActor
    private func skipToEnd(_ app: XCUIApplication) {
        for label in ["Skip Intro", "Skip Recap", "Skip Credits"] {
            let skip = app.buttons[label]
            XCTAssertTrue(skip.waitForExistence(timeout: 30), "\(label) didn't appear")
            waitForFocus(on: skip)
            XCUIRemote.shared.press(.select)
        }
    }

    @MainActor
    func testRemoteCancelsTheUpNextCountdown() throws {
        let app = try launchPlayer(environment: ["PLAYBACK_FIXTURE_NEXT": "1"])
        defer { app.terminate() }
        skipToEnd(app)
        let play = app.buttons["Play Now"], cancel = app.buttons["Cancel"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        screenshot("tv-up-next")
        waitForFocus(on: play)
        XCUIRemote.shared.press(.right)
        waitForFocus(on: cancel)
        screenshot("tv-up-next-cancel-focused")
        XCUIRemote.shared.press(.select)
        XCTAssertFalse(play.waitForExistence(timeout: 2), "Cancel didn't close the offer")
        // Nothing starts once the countdown would have run out, and the remote still works.
        sleep(11)
        XCTAssertNotEqual(app.staticTexts["fixture-source"].value as? String, "source=next")
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(app.buttons["Subtitles"].waitForExistence(timeout: 5), "Focus was lost after cancelling")
    }

    /// A film with nothing after it ends on a card whose Start Over takes Select; Menu closes.
    @MainActor
    func testEndCardStartsOverAndMenuCloses() throws {
        let app = try launchPlayer()
        defer { app.terminate() }
        skipToEnd(app)
        let startOver = app.buttons["Start Over"]
        XCTAssertTrue(startOver.waitForExistence(timeout: 10))
        waitForFocus(on: startOver)
        screenshot("tv-end-card")
        XCUIRemote.shared.press(.select)
        let ended = app.staticTexts["fixture-ended"]
        wait(for: [expectation(for: NSPredicate(format: "value == 'no'"), evaluatedWith: ended)], timeout: 10)
        XCTAssertLessThan(Int(app.staticTexts["fixture-position"].value as? String ?? "") ?? Int.max, 15)
        skipToEnd(app)
        XCTAssertTrue(startOver.waitForExistence(timeout: 10))
        waitForFocus(on: startOver)
        XCUIRemote.shared.press(.menu)
        let position = app.staticTexts["fixture-position"]
        wait(for: [expectation(for: NSPredicate { _, _ in !position.exists }, evaluatedWith: position)], timeout: 5)
    }

    /// A next-episode lookup that lands after the end replaces the end card, and focus follows.
    @MainActor
    func testLateUpNextReplacesTheEndCard() throws {
        let app = try launchPlayer(environment: ["PLAYBACK_FIXTURE_NEXT": "late"])
        defer { app.terminate() }
        skipToEnd(app)
        let startOver = app.buttons["Start Over"]
        XCTAssertTrue(startOver.waitForExistence(timeout: 10))
        waitForFocus(on: startOver)
        let play = app.buttons["Play Now"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        waitForFocus(on: play)
        screenshot("tv-late-up-next")
        XCUIRemote.shared.press(.select)
        let source = app.staticTexts["fixture-source"]
        wait(for: [expectation(for: NSPredicate(format: "value == 'source=next'"), evaluatedWith: source)], timeout: 10)
    }

    /// Both offers show during the credits; down goes from Skip Credits to Up Next below it.
    @MainActor
    func testDownReachesUpNextFromSkipCredits() throws {
        let app = try launchPlayer(environment: ["PLAYBACK_FIXTURE_NEXT": "1"])
        defer { app.terminate() }
        for label in ["Skip Intro", "Skip Recap"] {
            let skip = app.buttons[label]
            XCTAssertTrue(skip.waitForExistence(timeout: 30), "\(label) didn't appear")
            waitForFocus(on: skip)
            XCUIRemote.shared.press(.select)
        }
        let credits = app.buttons["Skip Credits"], play = app.buttons["Play Now"]
        XCTAssertTrue(credits.waitForExistence(timeout: 30))
        XCTAssertTrue(play.waitForExistence(timeout: 30))
        waitForFocus(on: credits)
        XCUIRemote.shared.press(.down)
        waitForFocus(on: play)
        screenshot("tv-up-next-from-skip-credits")
        // Cancelled, the card is gone, and up from the picture must leave focus somewhere usable.
        XCUIRemote.shared.press(.right)
        waitForFocus(on: app.buttons["Cancel"])
        XCUIRemote.shared.press(.select)
        XCTAssertFalse(play.waitForExistence(timeout: 2), "Cancel didn't close the offer")
        XCUIRemote.shared.press(.up)
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(app.buttons["Subtitles"].waitForExistence(timeout: 5), "Focus was lost after cancelling and pressing up")
    }

    @MainActor
    func testRemotePlaysTheNextEpisodeFromUpNext() throws {
        let app = try launchPlayer(environment: ["PLAYBACK_FIXTURE_NEXT": "1"])
        defer { app.terminate() }
        // While the episode is still playing Up Next waits for an up press, without taking Select.
        let skip = app.buttons["Skip Intro"]
        XCTAssertTrue(skip.waitForExistence(timeout: 30))
        skipToEnd(app)
        let play = app.buttons["Play Now"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        waitForFocus(on: play)
        XCUIRemote.shared.press(.select)
        let source = app.staticTexts["fixture-source"]
        wait(for: [expectation(for: NSPredicate(format: "value == 'source=next'"), evaluatedWith: source)], timeout: 10)
    }

    @MainActor
    func testPanelFitsItsTracksAndListsSources() throws {
        let app = try launchPlayer(environment: ["PLAYBACK_FIXTURE_PROGRESS_ID": "panel-fixture-\(UUID().uuidString)"])
        defer { app.terminate() }
        let remote = XCUIRemote.shared
        let position = app.staticTexts["fixture-position"]
        XCTAssertTrue(position.waitForExistence(timeout: 30))
        screenshot("tv-controls")
        // Off the picture and onto the panel, whichever the skip offer's focus does first.
        remote.press(.down)
        let tab = app.buttons["Subtitles"]
        if !tab.waitForExistence(timeout: 1) { remote.press(.down) }
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        waitForFocus(on: tab)
        screenshot("tv-panel-subtitles")
        remote.press(.right)
        waitForFocus(on: app.buttons["Audio"])
        sleep(1)
        screenshot("tv-panel-audio")
        remote.press(.left)
        remote.press(.left)
        waitForFocus(on: app.buttons["Info"])
        sleep(1)
        screenshot("tv-panel-info")
        let sources = app.buttons["Sources"]
        XCTAssertTrue(sources.waitForExistence(timeout: 5))
        // The speed stepper and Zoom to Fill come first.
        for _ in 0..<3 {
            remote.press(.down)
            sleep(1)
        }
        waitForFocus(on: sources)
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["No playback addons"].waitForExistence(timeout: 5))
        screenshot("tv-sources-sheet")
        remote.press(.menu)
        XCTAssertTrue(position.waitForExistence(timeout: 5))
    }

    @MainActor
    func testRemoteReachesFailureButtons() throws {
        guard let url = ProcessInfo.processInfo.environment["PLAYBACK_FIXTURE_URL"] else {
            throw XCTSkip("Set TEST_RUNNER_PLAYBACK_FIXTURE_URL for the isolated playback fixture.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--playback-ui-test"]
        app.launchEnvironment["PLAYBACK_FIXTURE_URL"] = url + "?fail-once=\(UUID().uuidString)"
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Play fixture"].waitForExistence(timeout: 10))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["Couldn't play this source"].waitForExistence(timeout: 30))
        screenshot("tv-failure")
        let retry = app.buttons["Try Again"]
        waitForFocus(on: retry)
        XCUIRemote.shared.press(.select)
        let position = app.staticTexts["fixture-position"]
        wait(for: [expectation(for: NSPredicate { _, _ in
            (Int(position.value as? String ?? "") ?? -1) >= 1
        }, evaluatedWith: app)], timeout: 15)
    }

    @MainActor
    private func waitForFocus(on element: XCUIElement) {
        let deadline = Date.now.addingTimeInterval(5)
        while !element.hasFocus && Date.now < deadline { Thread.sleep(forTimeInterval: 0.2) }
        XCTAssertTrue(element.hasFocus, "\(element.label) didn't take focus")
    }

    @MainActor
    func testLibraryFocusMovesBetweenRows() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--discovery-ui-test"]
        app.launchEnvironment["DISCOVERY_SCREEN"] = "library"
        app.launch()
        defer { app.terminate() }
        let first = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Resume 1,'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        let initial = expectation(for: NSPredicate { _, _ in first.hasFocus }, evaluatedWith: app)
        wait(for: [initial], timeout: 8)
        let remote = XCUIRemote.shared
        for index in 2...5 {
            remote.press(.right)
            let next = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Resume \(index),")).firstMatch
            let focused = expectation(for: NSPredicate { _, _ in next.exists && next.hasFocus }, evaluatedWith: app)
            wait(for: [focused], timeout: 5)
        }
        remote.press(.down)
        let saved = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Saved '"))
        let movedDown = expectation(for: NSPredicate { _, _ in
            saved.allElementsBoundByIndex.contains { $0.hasFocus }
        }, evaluatedWith: app)
        wait(for: [movedDown], timeout: 5)
        let selected = saved.allElementsBoundByIndex.first { $0.hasFocus }?.label
        remote.press(.right)
        let movedRight = expectation(for: NSPredicate { _, _ in
            saved.allElementsBoundByIndex.contains { $0.hasFocus && $0.label != selected }
        }, evaluatedWith: app)
        wait(for: [movedRight], timeout: 5)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Library rows after focus navigation"
        attachment.lifetime = .keepAlways
        add(attachment)
        remote.press(.up)
        let movedUp = expectation(for: NSPredicate { _, _ in
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Resume '"))
                .allElementsBoundByIndex.contains { $0.hasFocus }
        }, evaluatedWith: app)
        wait(for: [movedUp], timeout: 5)
    }

    @MainActor
    func testReviewsReadWithRemote() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--discovery-ui-test"]
        app.launchEnvironment["DISCOVERY_SCREEN"] = "overview"
        app.launch()
        defer { app.terminate() }
        let read = app.buttons["Read review"].firstMatch
        XCTAssertTrue(read.waitForExistence(timeout: 15))
        // The second review fits in its preview, so only the first offers the rest.
        XCTAssertEqual(app.buttons.matching(identifier: "Read review").count, 1)
        XCTAssertTrue(app.buttons["All reviews"].exists)
        let focused = expectation(for: NSPredicate { _, _ in read.hasFocus }, evaluatedWith: app)
        wait(for: [focused], timeout: 8)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'The ending invites discussion'")).firstMatch.waitForExistence(timeout: 10))
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testDirectorOpensFilmographyWithRemote() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--discovery-ui-test"]
        app.launchEnvironment["DISCOVERY_SCREEN"] = "directors"
        app.launch()
        defer { app.terminate() }
        let director = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Christopher Nolan'")).firstMatch
        XCTAssertTrue(director.waitForExistence(timeout: 15))
        let focused = expectation(for: NSPredicate { _, _ in director.hasFocus }, evaluatedWith: app)
        wait(for: [focused], timeout: 8)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["Filmography"].waitForExistence(timeout: 10))
    }
    @MainActor
    func testFestivalSectionsAndWinnerDetailsWithRemote() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--discovery-ui-test"]
        app.launchEnvironment["DISCOVERY_SCREEN"] = "festival"
        app.launch()
        defer { app.terminate() }
        let picker = app.buttons["festival-section-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 15))
        let remote = XCUIRemote.shared
        for _ in 0..<4 {
            if picker.hasFocus { break }
            remote.press(app.buttons["All awards"].hasFocus ? .down : .up)
            let focused = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in picker.hasFocus }, object: app)
            if XCTWaiter.wait(for: [focused], timeout: 1) == .completed { break }
        }
        XCTAssertTrue(picker.hasFocus)
        remote.press(.select)
        let section = app.buttons["Grand Jury Prizes"]
        XCTAssertTrue(section.waitForExistence(timeout: 5))
        let sectionCell = app.cells.containing(.button, identifier: "Grand Jury Prizes").firstMatch
        for _ in 0..<5 {
            if section.hasFocus || (sectionCell.exists && sectionCell.hasFocus) { break }
            remote.press(.down)
            let focused = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in section.hasFocus || (sectionCell.exists && sectionCell.hasFocus) }, object: app)
            if XCTWaiter.wait(for: [focused], timeout: 1) == .completed { break }
        }
        XCTAssertTrue(section.hasFocus || (sectionCell.exists && sectionCell.hasFocus), app.debugDescription)
        remote.press(.select)
        let winner = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Josephine'")).firstMatch
        XCTAssertTrue(winner.waitForExistence(timeout: 5))
        remote.press(.down)
        for _ in 0..<6 {
            if winner.hasFocus { break }
            remote.press(.left)
            let focused = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in winner.hasFocus }, object: app)
            if XCTWaiter.wait(for: [focused], timeout: 1) == .completed { break }
        }
        XCTAssertTrue(winner.hasFocus)
        remote.press(.select)
        XCTAssertTrue(app.images["Josephine"].waitForExistence(timeout: 10) || app.staticTexts["Josephine"].exists)
        XCTAssertFalse(app.searchFields.firstMatch.exists)
    }

}
#endif
