import XCTest

final class PersonRoleTests: XCTestCase {
    @MainActor
    func testRoleAndMediaFilters() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--person-role-ui-test"]
        app.launch()
        defer {
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
        #if os(tvOS)
        let roles = app.segmentedControls["person-role-filter"]
        XCTAssertTrue(roles.waitForExistence(timeout: 15))
        let remote = XCUIRemote.shared
        for _ in 0..<4 {
            if roles.buttons["All roles"].hasFocus { break }
            remote.press(.down)
        }
        XCTAssertTrue(roles.buttons["All roles"].hasFocus)
        remote.press(.right)
        let actingFocused = expectation(for: NSPredicate { _, _ in roles.buttons["Acting"].hasFocus }, evaluatedWith: app)
        wait(for: [actingFocused], timeout: 5)
        remote.press(.right)
        let directingFocused = expectation(for: NSPredicate { _, _ in roles.buttons["Directing"].hasFocus }, evaluatedWith: app)
        wait(for: [directingFocused], timeout: 5)
        remote.press(.select)
        XCTAssertTrue(app.buttons["All (2)"].waitForExistence(timeout: 5))
        XCTAssertTrue(roles.buttons["Directing"].isSelected)
        #else
        let roles = app.buttons["person-role-filter"]
        XCTAssertTrue(roles.waitForExistence(timeout: 15))
        roles.tap()
        app.buttons["Directing"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["All (2)"].exists)
        XCTAssertTrue(app.segmentedControls.buttons["Movies (1)"].exists)
        app.segmentedControls.buttons["Series (1)"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Directed series'")).firstMatch.exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Camera series'")).firstMatch.exists)
        roles.tap()
        app.buttons["Acting"].tap()
        XCTAssertTrue(app.staticTexts["No credits in this category."].exists)
        app.segmentedControls.buttons["All (2)"].tap()
        roles.tap()
        app.buttons["Other crew"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["All (2)"].exists)
        roles.tap()
        app.buttons["All roles"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["All (4)"].exists)
        #endif
    }
}
