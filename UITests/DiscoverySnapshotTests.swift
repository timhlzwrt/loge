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
            ?? ["person"]
        for screen in screens {
            let app = XCUIApplication()
            app.launchArguments += ["--discovery-ui-test"]
            app.launchEnvironment["DISCOVERY_SCREEN"] = screen
            app.launch()
            if screen == "person" {
                XCTAssertTrue(app.staticTexts["Filmography"].waitForExistence(timeout: 20))
            }
            let image = app.screenshot()
            let url = URL(fileURLWithPath: directory).appending(path: "\(screen).png")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try image.pngRepresentation.write(to: url)
            app.terminate()
        }
    }
}
#endif
