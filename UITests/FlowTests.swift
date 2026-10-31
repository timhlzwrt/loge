#if os(iOS)
import XCTest

/// End-to-end checks of browsing flows against live addons. They need the network,
/// Cinemeta, and for playback the local test addon (Tools/test-addon.py) installed, so
/// they only run on request. Screenshots go to `SCREENSHOT_DIR` when it's set:
///
///     TEST_RUNNER_UI_FLOWS=1 TEST_RUNNER_SCREENSHOT_DIR=/tmp/shots xcodebuild test \
///       -scheme MediaApp -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
///       -only-testing:MediaAppUITests/FlowTests
final class FlowTests: XCTestCase {
    private var app: XCUIApplication!

    @MainActor
    override func setUp() async throws {
        guard ProcessInfo.processInfo.environment["UI_FLOWS"] != nil else {
            throw XCTSkip("Set TEST_RUNNER_UI_FLOWS=1 to run.")
        }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launch()
    }

    @MainActor
    func testSearchFindsTitlesAndRemembersTheQuery() {
        openTab("Search")
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("batman")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Batman'")).firstMatch
            .waitForExistence(timeout: 15), "No results for batman")
        screenshot("search-results")

        field.typeText("zzqxjvw")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'No Results'")).firstMatch
            .waitForExistence(timeout: 15), "No empty state for a query without matches")
        screenshot("search-empty")

        // Searching from the keyboard remembers the query; clearing the field shows it.
        field.typeText("\n")
        field.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Recent Searches"].waitForExistence(timeout: 5))
        screenshot("search-recent")
    }

    @MainActor
    func testMarkingAnEpisodeWatchedAndUnwatched() {
        openSeries("Lanterns")
        // The row opens scrolled to Up Next, which is always on screen. Marking it changes
        // what's Up Next, so the card is then found by its episode number.
        let upNext = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Up Next'")).firstMatch
        XCTAssertTrue(upNext.waitForExistence(timeout: 15))
        let number = upNext.label.firstMatch(of: #/Episode (\d+)/#)?.1 ?? ""
        let episode = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Episode \(number),")).firstMatch
        episode.press(forDuration: 2.5)
        screenshot("episode-menu")
        let markWatched = app.buttons["Mark as Watched"]
        let markUnwatched = app.buttons["Mark as Unwatched"]
        XCTAssertTrue(markWatched.waitForExistence(timeout: 3) || markUnwatched.exists)
        let wasWatched = markUnwatched.exists
        (wasWatched ? markUnwatched : markWatched).tap()
        screenshot("episode-marked")

        // The menu now offers the opposite action.
        episode.press(forDuration: 2.5)
        XCTAssertTrue((wasWatched ? markWatched : markUnwatched).waitForExistence(timeout: 3))
        (wasWatched ? markWatched : markUnwatched).tap()
    }

    @MainActor
    func testClosingAutoplayReturnsToDetails() {
        openSeries("Lanterns")
        let play = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Play' OR label BEGINSWITH 'Resume'")).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 15))
        play.tap()
        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 20), "Player didn't open")
        close.tap()
        XCTAssertTrue(app.buttons["Season options"].waitForExistence(timeout: 5),
                      "Closing the player didn't return to the details screen")
        screenshot("after-close")
    }

    @MainActor
    func testLandscapeAndPullToRefresh() {
        XCTAssertTrue(app.staticTexts["Popular Movies"].waitForExistence(timeout: 15))
        app.swipeDown()
        XCTAssertTrue(app.staticTexts["Popular Movies"].waitForExistence(timeout: 15), "Rows gone after refresh")

        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        screenshot("landscape-home")
        XCUIDevice.shared.orientation = .portrait
        openSeries("Lanterns")
        XCTAssertTrue(app.buttons["Season options"].waitForExistence(timeout: 15))
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(3)
        screenshot("landscape-details")
        XCUIDevice.shared.orientation = .portrait
    }

    /// The picture should fill the new size after each turn; check the screenshots.
    @MainActor
    func testRotatingDuringPlayback() {
        openSeries("Lanterns")
        let play = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Play' OR label BEGINSWITH 'Resume'")).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 15))
        play.tap()
        let pause = app.buttons["Pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 20), "Playback didn't start")

        // The test clips are 10 seconds long, so both turns happen well before the end.
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(1)
        screenshot("rotated-while-playing")

        // A tap toggles the controls, so only tap when they're hidden.
        if !pause.isHittable { app.tap() }
        XCTAssertTrue(pause.waitForExistence(timeout: 3), "Player closed when rotated")
        pause.tap()
        XCUIDevice.shared.orientation = .portrait
        sleep(2)
        screenshot("rotated-while-paused")
        app.buttons["Close"].tap()
    }

    /// The player's button hands the video to the floating window and closes the player
    /// screen while playback continues. Needs a simulator with Picture in Picture, such as
    /// an iPad; iPhone simulators report it as unsupported.
    @MainActor
    func testPictureInPicture() throws {
        installTestAddonIfNeeded()
        openSeries("Lanterns")
        let play = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Play' OR label BEGINSWITH 'Resume'")).firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 15))
        play.tap()
        // Without a remembered source, Play opens the source list. Once playing, the
        // controls fade out; while they're up, Close is showing.
        let testSource = app.buttons.matching(NSPredicate(format: "label CONTAINS 'MKV H.264'")).firstMatch
        let pause = app.buttons["Pause"]
        for _ in 0..<30 where !pause.exists {
            if testSource.exists {
                testSource.tap()
            } else if !app.buttons["Close"].exists && app.buttons["Picture in Picture"].exists == false {
                app.tap()
            }
            sleep(1)
        }
        XCTAssertTrue(pause.exists, "Playback didn't start")
        // The controls stay up while paused.
        pause.tap()

        let pip = app.buttons["Picture in Picture"]
        guard pip.waitForExistence(timeout: 5) else {
            throw XCTSkip("Picture in Picture isn't available on this simulator")
        }
        pip.tap()
        sleep(3)
        screenshot("pip-started")
        XCTAssertFalse(app.buttons["Picture in Picture"].exists, "The player screen stayed open")

        // The floating window belongs to SpringBoard, labelled in the simulator's language.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        func windowButton(_ labels: String...) -> XCUIElement {
            springboard.buttons.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
        }
        let restore = windowButton("Restore Full Screen", "Vollbildmodus wiederherstellen")
        XCTAssertTrue(restore.waitForExistence(timeout: 5), "No floating window")
        windowButton("Play", "Wiedergabe").tap()
        restore.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5) || app.buttons["Picture in Picture"].exists,
                      "Restoring didn't bring the player screen back")
        screenshot("pip-restored")

        // Going home while playing moves the video into the floating window by itself.
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(restore.waitForExistence(timeout: 5), "Going home didn't start Picture in Picture")
        restore.tap()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        // Closing the floating window ends playback rather than leaving it running unseen.
        if !app.buttons["Picture in Picture"].isHittable { app.tap() }
        app.buttons["Picture in Picture"].tap()
        let close = windowButton("Close Picture in Picture", "Bild-in-Bild schließen")
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        sleep(2)
        XCTAssertFalse(restore.exists, "The floating window stayed")
        XCTAssertFalse(app.buttons["Picture in Picture"].exists, "The player came back")
    }

    /// A source that doesn't open hands over to the next one instead of stopping.
    @MainActor
    func testBrokenSourceFallsBackToAnother() {
        installTestAddonIfNeeded()
        openSeries("Lanterns")
        // Episode cards open the source list without playing anything first.
        let episode = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Up Next'")).firstMatch
        XCTAssertTrue(episode.waitForExistence(timeout: 15))
        episode.tap()
        let broken = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Returns 404'")).firstMatch
        XCTAssertTrue(broken.waitForExistence(timeout: 15), "No broken test source")
        broken.tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 30), "Didn't fall back to another source")
        XCTAssertFalse(app.staticTexts["Couldn't play this source"].exists)
        screenshot("fallback-playing")
        app.buttons["Close"].tap()
    }

    /// Subtitles that come with a stream and those from subtitle addons join the file's own.
    @MainActor
    func testExternalSubtitles() {
        installTestAddonIfNeeded()
        openSeries("Lanterns")
        let episode = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Up Next'")).firstMatch
        XCTAssertTrue(episode.waitForExistence(timeout: 15))
        episode.tap()
        let source = app.buttons.matching(NSPredicate(format: "label CONTAINS 'MKV H.264'")).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 15))
        source.tap()
        let pause = app.buttons["Pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 20), "Playback didn't start")
        pause.tap()

        let menu = app.buttons["Audio and subtitles"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "No subtitle menu")
        menu.tap()
        let fromStream = app.buttons.matching(NSPredicate(format: "label CONTAINS '· Stream'")).firstMatch
        let fromAddon = app.buttons.matching(NSPredicate(format: "label CONTAINS '· Test Streams'")).firstMatch
        _ = fromStream.waitForExistence(timeout: 5)
        screenshot("subtitle-menu")
        XCTAssertTrue(fromStream.exists, "The stream's subtitle is missing")
        XCTAssertTrue(fromAddon.exists, "The addon's subtitle is missing")
        fromAddon.tap()
        sleep(1)
        screenshot("subtitle-shown-paused")
        app.buttons["Play"].tap()
        sleep(1)
        screenshot("subtitle-shown")
        app.buttons["Close"].tap()
    }

    @MainActor
    func testTraktSettings() {
        openTab("Settings")
        let keys = app.textFields["Client ID"]
        let signedIn = app.staticTexts["Signed in as"]
        let signIn = app.buttons["Sign In"]
        for _ in 0..<4 where !(keys.exists || signedIn.exists || signIn.exists) {
            app.swipeUp()
        }
        XCTAssertTrue(keys.exists || signedIn.exists || signIn.exists, "No Trakt section")
        screenshot("settings-trakt")
    }

    // MARK: Helpers

    @MainActor
    private func openTab(_ name: String) {
        // iPhone shows a tab bar; iPad shows the tabs as plain buttons at the top.
        let tab = app.tabBars.buttons[name].firstMatch
        (tab.exists ? tab : app.buttons[name].firstMatch).tap()
    }

    @MainActor
    private func installTestAddonIfNeeded() {
        openTab("Settings")
        guard !app.staticTexts["Test Streams"].waitForExistence(timeout: 5) else { return }
        let field = app.textFields["Manifest URL"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("http://127.0.0.1:8765/manifest.json\n")
        XCTAssertTrue(app.staticTexts["Test Streams"].waitForExistence(timeout: 10), "Test addon didn't install")
    }

    @MainActor
    private func openSeries(_ name: String) {
        openTab("Home")
        let poster = app.buttons[name].firstMatch
        for _ in 0..<6 where !poster.isHittable {
            app.swipeUp()
        }
        // Home follows Cinemeta's popular lists, which change; search finds it either way.
        if !poster.isHittable {
            openTab("Search")
            let field = app.searchFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(name)
        }
        XCTAssertTrue(poster.waitForExistence(timeout: 15), "\(name) isn't on Home or in search")
        poster.tap()
    }

    @MainActor
    private func screenshot(_ name: String) {
        guard let directory = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] else { return }
        let url = URL(fileURLWithPath: directory).appending(path: "\(name).png")
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
    }
}
#endif
