#if os(iOS)
import XCTest

final class SavedListTests: XCTestCase {
    @MainActor
    func testCreateRenameAndDeleteList() throws {
        guard ProcessInfo.processInfo.environment["UI_FLOWS"] != nil else {
            throw XCTSkip("Set TEST_RUNNER_UI_FLOWS=1 to run.")
        }
        let app = XCUIApplication()
        app.launch()
        let tab = app.tabBars.buttons["My Lists"].firstMatch
        (tab.exists ? tab : app.buttons["My Lists"].firstMatch).tap()
        app.buttons["Manage Lists"].tap()
        app.buttons["New List"].tap()
        let name = "Test List \(UUID().uuidString.prefix(6))"
        let field = app.textFields["List name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Nothing in \(name)"].waitForExistence(timeout: 5))
        screenshot("lists-created")

        app.buttons["Manage Lists"].tap()
        app.buttons["Rename List"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: name.count) + "Renamed List")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Nothing in Renamed List"].waitForExistence(timeout: 5))

        app.buttons["Manage Lists"].tap()
        app.buttons["Delete List"].tap()
        app.alerts.buttons["Delete List"].tap()
        XCTAssertFalse(app.staticTexts["Nothing in Renamed List"].exists)
        screenshot("lists-watch-later")
    }

    @MainActor
    func testLongPressPosterSavesToCustomList() throws {
        guard ProcessInfo.processInfo.environment["UI_FLOWS"] != nil else {
            throw XCTSkip("Set TEST_RUNNER_UI_FLOWS=1 to run.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let listsTab = app.tabBars.buttons["My Lists"].firstMatch
        (listsTab.exists ? listsTab : app.buttons["My Lists"].firstMatch).tap()
        app.buttons["Manage Lists"].tap()
        app.buttons["New List"].tap()
        let name = "Poster Save \(UUID().uuidString.prefix(6))"
        let nameField = app.textFields["List name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(name)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Nothing in \(name)"].waitForExistence(timeout: 5))

        let searchTab = app.tabBars.buttons["Search"].firstMatch
        (searchTab.exists ? searchTab : app.buttons["Search"].firstMatch).tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Interstellar")
        let poster = app.buttons["Interstellar"].firstMatch
        XCTAssertTrue(poster.waitForExistence(timeout: 20), "No public Cinemeta result for Interstellar")
        poster.press(forDuration: 2.5)
        XCTAssertTrue(app.buttons["Save to"].waitForExistence(timeout: 5), "Poster long press didn't open Save to")
        app.buttons["Save to"].tap()
        XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 5))
        app.buttons[name].tap()

        // Expanded iPhone search hides the other tabs until its Close action is used.
        if app.buttons["Close"].exists { app.buttons["Close"].tap() }
        (listsTab.exists ? listsTab : app.buttons["My Lists"].firstMatch).tap()
        XCTAssertTrue(app.navigationBars["My Lists"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Interstellar"].firstMatch.waitForExistence(timeout: 5),
                      "The title wasn't saved to the selected custom list")
        XCTAssertFalse(app.staticTexts["Nothing in \(name)"].exists)
        screenshot("lists-poster-saved")

        app.buttons["Manage Lists"].tap()
        app.buttons["Delete List"].tap()
        app.alerts.buttons["Delete List"].tap()
        XCTAssertTrue(app.navigationBars["My Lists"].waitForExistence(timeout: 5))
        app.buttons["Manage Lists"].tap()
        XCTAssertFalse(app.buttons["Delete List"].exists, "Deleted list remained selected")
    }

    @MainActor
    private func screenshot(_ name: String) {
        guard let directory = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] else { return }
        let url = URL(fileURLWithPath: directory).appending(path: "\(name).png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
    }
}
#endif
