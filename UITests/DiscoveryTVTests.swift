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

        remote.press(.up)
        waitForFocus(on: skip)
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
        XCTAssertEqual(app.buttons.matching(identifier: "Read review").count, 2)
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
