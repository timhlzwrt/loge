#if os(iOS)
import XCTest

/// End-to-end checks of browsing flows against live addons. They need the network,
/// Cinemeta, and for playback the local test addon (Tools/test-addon.py) installed, so
/// they only run on request. Screenshots go to `SCREENSHOT_DIR` when it's set:
/// Track switching also uses the generated MOV server on port 8766; see docs/REVIEW_VALIDATION.md.
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
        field.typeText("\n")
        field.tap()

        field.typeText("zzqxjvw")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'No Results'")).firstMatch
            .waitForExistence(timeout: 15), "No empty state for a query without matches")
        screenshot("search-empty")

        // Only the successful query should be remembered.
        field.typeText("\n")
        field.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Recent Searches"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["batman"].exists)
        XCTAssertFalse(app.buttons["batmanzzqxjvw"].exists)
        screenshot("search-recent")
    }

    @MainActor
    func testMarkingAnEpisodeWatchedAndUnwatched() {
        openSeries("Lanterns")
        // Marking the card changes what's Up Next, so it's then found by its episode number.
        let card = episodeCard()
        let number = card.label.firstMatch(of: #/Episode (\d+)/#)?.1 ?? "1"
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
        XCTAssertTrue(app.buttons["Season"].waitForExistence(timeout: 5),
                      "Closing the player didn't return to the details screen")
        screenshot("after-close")
    }

    @MainActor
    func testClosingActivePlaybackCanStartAgain() {
        startPlayback()
        for attempt in 0..<3 {
            if attempt > 0 {
                app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Play' OR label BEGINSWITH 'Resume'"))
                    .firstMatch.tap()
            }
            XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 20))
            app.buttons["Close"].tap()
            XCTAssertTrue(app.buttons["Season"].waitForExistence(timeout: 5), "Closing playback lost the details screen")
            XCTAssertEqual(app.state, .runningForeground)
        }
        screenshot("repeated-close")
    }

    @MainActor
    func testPlayerTransportStaysCentered() {
        startPlayback()
        app.buttons["Pause"].tap()
        XCTAssertFalse(app.buttons["Play Now"].exists, "Up Next appeared before the short clip's credits")
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            let play = app.buttons["Play"]
            XCTAssertTrue(play.waitForExistence(timeout: 5))
            let screen = app.frame
            XCTAssertEqual(play.frame.midX, screen.midX, accuracy: 12)
            XCTAssertEqual(play.frame.midY, screen.midY, accuracy: 12)
            screenshot(orientation == .portrait ? "centered-portrait" : "centered-landscape")
        }
        app.buttons["Audio"].tap()
        app.buttons["Audio Timing…"].tap()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(app.frame.contains(done.frame))
        XCTAssertTrue(app.frame.contains(app.buttons["Play sound earlier"].frame))
        screenshot("timing-landscape")
        done.tap()
        app.buttons["Close"].tap()
    }

    @MainActor
    func testSwitchingSourceKeepsPlayerUsable() {
        startPlayback()
        app.buttons["Pause"].tap()
        app.buttons["Sources"].tap()
        let source = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Test Header'")).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        source.tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 20), "Replacement source didn't start")
        app.buttons["Pause"].tap()
        screenshot("source-replaced")
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Season"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.buttons["Season"].waitForExistence(timeout: 15))
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(3)
        screenshot("landscape-details")
        XCUIDevice.shared.orientation = .portrait
    }

    /// The picture should fill the new size after each turn; check the screenshots.
    @MainActor
    func testRotatingDuringPlayback() {
        startPlayback()
        let pause = app.buttons["Pause"]

        // The test clips are 10 seconds long, so both turns happen well before the end.
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(1)
        screenshot("rotated-while-playing")

        // A tap toggles the controls; aim above the middle, where the play button sits.
        if !app.buttons["Close"].exists { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap() }
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 3), "Player closed when rotated")
        if pause.exists { pause.tap() }
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
        startPlayback()
        // The controls stay up while paused.
        app.buttons["Pause"].tap()

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
        episodeCard().tap()
        let broken = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Test Broken'")).firstMatch
        XCTAssertTrue(broken.waitForExistence(timeout: 15), "No broken test source")
        screenshot("sources")
        broken.tap()
        let pause = app.buttons["Pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 30), "Didn't fall back to another source")
        // Keep controls visible while taking the screenshot and closing the short test clip.
        pause.tap()
        XCTAssertFalse(app.staticTexts["Couldn't play this source"].exists)
        screenshot("fallback-playing")
        app.buttons["Close"].tap()
    }

    @MainActor
    func testTrackSwitchingWhilePlaying() {
        installTestAddonIfNeeded(name: "Playback Test Streams", manifestURL: "http://127.0.0.1:8766/manifest.json")
        openSeries("Lanterns")
        episodeCard().tap()
        let source = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Local Multi Track'")).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 15))
        source.tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 30))
        let initialPosition = app.sliders["Playback position"].value as? String
        XCTAssertNotNil(initialPosition)

        for index in 0..<3 {
            if !app.buttons["Audio"].exists { app.tap() }
            app.buttons["Audio"].tap()
            let language = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", index == 1 ? "English" : "German")).firstMatch
            XCTAssertTrue(language.waitForExistence(timeout: 5))
            screenshot("tracks-audio-menu-\(index)")
            language.tap()
            XCTAssertFalse(app.alerts.firstMatch.exists)
            app.buttons["Subtitles"].tap()
            let subtitle = index == 1 ? app.buttons["Off"] : app.buttons.matching(NSPredicate(format: "label CONTAINS %@", index == 0 ? "German" : "English")).firstMatch
            XCTAssertTrue(subtitle.waitForExistence(timeout: 5))
            subtitle.tap()
            for _ in 0..<15 where !app.buttons["Pause"].exists {
                if !app.buttons["Close"].exists { app.tap() }
                sleep(1)
            }
            screenshot("tracks-after-switch-\(index)")
            XCTAssertTrue(app.buttons["Pause"].exists, "Track change interrupted playback")
        }
        XCTAssertNotEqual(app.sliders["Playback position"].value as? String, initialPosition,
                          "Playback position did not advance while switching tracks")
        screenshot("tracks-playing")
        app.buttons["Close"].tap()
        XCTAssertTrue(episodeCard().exists)
    }

    /// Subtitles that come with a stream and those from subtitle addons join the file's own.
    @MainActor
    func testExternalSubtitles() {
        installTestAddonIfNeeded()
        openSeries("Lanterns")
        episodeCard().tap()
        let source = app.buttons.matching(NSPredicate(format: "label CONTAINS 'DTS 5.1'")).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 15))
        source.tap()
        let pause = app.buttons["Pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 20), "Playback didn't start")
        pause.tap()

        let menu = app.buttons["Subtitles"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "No subtitle menu")
        menu.tap()
        let fromStream = app.buttons.matching(NSPredicate(format: "label CONTAINS '· Stream'")).firstMatch
        let fromAddon = app.buttons.matching(NSPredicate(format: "label CONTAINS '· Addon'")).firstMatch
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

    /// Screenshots of each redesigned screen, to compare with `Design/mockups`.
    @MainActor
    func testScreenTour() {
        installTestAddonIfNeeded()
        openTab("Home")
        sleep(3)
        screenshot("tour-home")
        app.swipeUp()
        sleep(1)
        screenshot("tour-home-rows")

        openSeries("Lanterns")
        XCTAssertTrue(app.buttons["Season"].waitForExistence(timeout: 15))
        sleep(2)
        screenshot("tour-details")
        app.buttons["Choose a Source"].tap()
        let source = app.buttons.matching(NSPredicate(format: "label CONTAINS 'DTS 5.1'")).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 15), "No test sources")
        screenshot("tour-sources")
        source.tap()

        let pause = app.buttons["Pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 30), "Playback didn't start")
        pause.tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        if !app.buttons["Close"].exists { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap() }
        screenshot("tour-player")
        app.buttons["Sources"].tap()
        sleep(2)
        screenshot("tour-player-sources")
        // The sheet's Close is the later of the two.
        app.buttons.matching(identifier: "Close").allElementsBoundByIndex.last?.tap()
        XCUIDevice.shared.orientation = .portrait
        sleep(1)
        if !app.buttons["Close"].exists { app.tap() }
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

    /// Chooses the short local-addon fixture explicitly, independent of remembered sources.
    /// Leaves the controls showing; subsequent Play/Resume actions exercise autoplay.
    @MainActor
    private func startPlayback() {
        installTestAddonIfNeeded()
        openSeries("Lanterns")
        episodeCard().tap()
        // Once playing, the controls fade out; while they're up, Close is showing.
        let testSource = app.buttons.matching(NSPredicate(format: "label CONTAINS 'DTS 5.1'")).firstMatch
        let pause = app.buttons["Pause"]
        for _ in 0..<30 where !pause.exists {
            if testSource.isHittable {
                testSource.tap()
            } else if !app.buttons["Close"].exists {
                app.tap()
            }
            sleep(1)
        }
        XCTAssertTrue(pause.exists, "Playback didn't start")
    }

    /// The first episode card in view: the row starts at the one up next.
    @MainActor
    private func episodeCard() -> XCUIElement {
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Episode '")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), "No episode cards")
        return card
    }

    @MainActor
    private func openTab(_ name: String) {
        // iPhone shows a tab bar; iPad shows the tabs as plain buttons at the top.
        let tab = app.tabBars.buttons[name].firstMatch
        (tab.exists ? tab : app.buttons[name].firstMatch).tap()
    }

    @MainActor
    private func installTestAddonIfNeeded(name: String = "Test Streams", manifestURL: String = "http://127.0.0.1:8765/manifest.json") {
        openTab("Settings")
        guard !app.staticTexts[name].waitForExistence(timeout: 5) else { return }
        let field = app.textFields["Manifest URL"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(manifestURL + "\n")
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 10), "Test addon didn't install")
    }

    @MainActor
    private func openSeries(_ name: String) {
        openTab("Home")
        let poster = app.buttons[name].firstMatch
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
