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
        let environment = ProcessInfo.processInfo.environment
        let screens = environment["DISCOVERY_SCREENS"]?.split(separator: ",").map(String.init) ?? ["person"]
        // Seconds for artwork and addon responses to arrive, and how many screens further down to capture.
        let settle = environment["DISCOVERY_SETTLE"].flatMap(UInt32.init) ?? 0
        let scrolls = environment["DISCOVERY_SCROLLS"].flatMap(Int.init) ?? 0
        for screen in screens {
            let app = XCUIApplication()
            app.launchArguments += ["--discovery-ui-test"]
            app.launchEnvironment["DISCOVERY_SCREEN"] = screen
            app.launch()
            if screen == "person" {
                XCTAssertTrue(app.staticTexts["Filmography"].waitForExistence(timeout: 20))
            }
            sleep(settle)
            for page in 0...scrolls {
                if page > 0 {
                    app.swipeUp(velocity: .slow)
                    sleep(2)
                }
                let url = URL(fileURLWithPath: directory).appending(path: page == 0 ? "\(screen).png" : "\(screen)-\(page).png")
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try app.screenshot().pngRepresentation.write(to: url)
            }
            app.terminate()
        }
    }
}
#endif
