#if os(iOS)
import XCTest

final class DiscoverySnapshotTests: XCTestCase {
    @MainActor
    func testScreenshots() throws {
        guard let directory = ProcessInfo.processInfo.environment["DISCOVERY_SCREENSHOT_DIR"] else {
            throw XCTSkip("Set TEST_RUNNER_DISCOVERY_SCREENSHOT_DIR to capture comparison screens.")
        }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let screens = ProcessInfo.processInfo.environment["DISCOVERY_SCREENS"]?.split(separator: ",").map(String.init)
            ?? ["person", "overview", "festival", "directors"]
        for screen in screens {
            let app = XCUIApplication()
            app.launchArguments += ["--discovery-ui-test"]
            app.launchEnvironment["DISCOVERY_SCREEN"] = screen
            let baseline = ProcessInfo.processInfo.environment["DISCOVERY_BASELINE"] == "1"
            app.launchEnvironment["DISCOVERY_BASELINE"] = baseline ? "1" : "0"
            app.launch()
            let ready = switch screen {
            case "person": app.staticTexts["Filmography"]
            case "festival": app.buttons["All awards"]
            case "directors" where !baseline: app.scrollViews["popular-directors"]
            default: app.staticTexts["Popular Directors"]
            }
            XCTAssertTrue(ready.waitForExistence(timeout: 20))
            if screen == "overview" {
                XCTAssertTrue(app.buttons["Read review"].waitForExistence(timeout: 15))
            }
            let image = app.screenshot()
            let url = URL(fileURLWithPath: directory).appending(path: "\(screen).png")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try image.pngRepresentation.write(to: url)
            if screen == "overview" {
                app.buttons["Read review"].tap()
                XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'The ending invites discussion'")).firstMatch.waitForExistence(timeout: 10))
            } else if screen == "festival" {
                app.buttons["festival-section-picker"].tap()
                app.buttons["Grand Jury Prizes"].tap()
                let winner = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Josephine'")).firstMatch
                XCTAssertTrue(winner.waitForExistence(timeout: 5))
                winner.tap()
                XCTAssertTrue(app.images["Josephine"].waitForExistence(timeout: 10) || app.staticTexts["Josephine"].exists)
                XCTAssertFalse(app.searchFields.firstMatch.exists)
            } else if screen == "directors" && !baseline {
                app.buttons.matching(NSPredicate(format: "label CONTAINS 'Christopher Nolan'")).firstMatch.tap()
                XCTAssertTrue(app.staticTexts["Filmography"].waitForExistence(timeout: 10))
            }
            app.terminate()
        }
    }
}
#endif
