import XCTest

extension XCTestCase {
    /// Saves the screen to `SCREENSHOT_DIR` (set `TEST_RUNNER_SCREENSHOT_DIR` when running);
    /// does nothing when it isn't set.
    @MainActor
    func screenshot(_ name: String) {
        guard let directory = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] else { return }
        let url = URL(fileURLWithPath: directory).appending(path: "\(name).png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
    }
}
