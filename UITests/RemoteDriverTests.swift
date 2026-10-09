import XCTest

/// Drives the Apple TV simulator's Siri Remote from the command line, for checking
/// focus and navigation by hand. Skipped unless `REMOTE_DIR` is set, so ordinary
/// test runs never wait on it:
///
///     mkdir -p /tmp/remote && : > /tmp/remote/commands
///     TEST_RUNNER_REMOTE_DIR=/tmp/remote xcodebuild test -scheme MediaApp \
///       -destination 'platform=tvOS Simulator,name=Apple TV 4K (3rd generation)' \
///       -only-testing:MediaAppUITests/RemoteDriverTests
///
/// Then append one command per line to `$REMOTE_DIR/commands`:
/// `up`, `down`, `left`, `right`, `select`, `hold-select`, `menu`, `playpause`,
/// `type <text>`, `wait <seconds>` or `stop`. After running each line the driver
/// appends that line's number to `$REMOTE_DIR/done`.
final class RemoteDriverTests: XCTestCase {
    @MainActor
    func testDriveRemote() throws {
        guard let directory = ProcessInfo.processInfo.environment["REMOTE_DIR"] else {
            throw XCTSkip("Set TEST_RUNNER_REMOTE_DIR to drive the remote.")
        }
        let commandsURL = URL(fileURLWithPath: directory).appending(path: "commands")
        let doneURL = URL(fileURLWithPath: directory).appending(path: "done")
        try "".write(to: doneURL, atomically: true, encoding: .utf8)

        let app = XCUIApplication()
        app.launch()

        var executed = 0
        let deadline = Date.now.addingTimeInterval(60 * 60)
        while Date.now < deadline {
            let text = (try? String(contentsOf: commandsURL, encoding: .utf8)) ?? ""
            // The last element is either empty or a line still being written.
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).dropLast()
            while executed < lines.count {
                let line = String(lines[lines.startIndex + executed])
                if line == "stop" { return }
                perform(line, in: app)
                executed += 1
                try append("\(executed)\n", to: doneURL)
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    @MainActor
    private func perform(_ line: String, in app: XCUIApplication) {
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        let remote = XCUIRemote.shared
        switch parts.first {
        case "up": remote.press(.up)
        case "down": remote.press(.down)
        case "left": remote.press(.left)
        case "right": remote.press(.right)
        case "select": remote.press(.select)
        case "hold-select": remote.press(.select, forDuration: 1.5)
        case "menu": remote.press(.menu)
        case "playpause": remote.press(.playPause)
        case "type": app.typeText(parts.count > 1 ? parts[1] : "")
        case "wait": Thread.sleep(forTimeInterval: Double(parts.count > 1 ? parts[1] : "1") ?? 1)
        default: print("RemoteDriver: unknown command \(line)")
        }
    }

    private func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
    }
}
