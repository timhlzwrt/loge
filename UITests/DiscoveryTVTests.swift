#if os(tvOS)
import XCTest

final class DiscoveryTVTests: XCTestCase {
    @MainActor
    func testReviewsReadWithRemote() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--discovery-ui-test"]
        app.launchEnvironment["DISCOVERY_SCREEN"] = "overview"
        app.launch()
        defer { app.terminate() }
        let read = app.buttons["Read review"]
        XCTAssertTrue(read.waitForExistence(timeout: 15))
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
