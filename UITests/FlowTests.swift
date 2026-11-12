#if os(iOS)
import XCTest

/// End-to-end checks of browsing flows against live addons. They need the network,
/// Cinemeta, and for playback the local test addon (Tools/test-addon.py) installed, so
/// they only run on request. Screenshots go to `SCREENSHOT_DIR` when it's set:
/// Track switching also uses the MOV fixture server on port 8766; see Tools/test-addon.py.
///
///     TEST_RUNNER_UI_FLOWS=1 TEST_RUNNER_SCREENSHOT_DIR=/tmp/shots xcodebuild test \
///       -scheme loge -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
///       -only-testing:logeUITests/FlowTests
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
    func testSyncIsOptional() throws {
        openTab("Settings")
        let sync = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sync' AND label CONTAINS 'Off'")).firstMatch
        guard sync.waitForExistence(timeout: 5) else {
            throw XCTSkip("Use a simulator without an existing sync connection.")
        }
        sync.tap()
        let code = app.secureTextFields["sync.connectionCode"]
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        let connect = app.buttons["Connect account"]
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
        XCTAssertFalse(connect.isEnabled)
        XCTAssertFalse(app.buttons["Previous sync connection"].exists, "The endpoint sync was removed")
        screenshot("sync-settings-optional")
    }

    @MainActor
    func testAccountSharingKeepsProgressPrivate() throws {
        guard let path = ProcessInfo.processInfo.environment["SYNC_TEST_CODE_FILE"] else {
            throw XCTSkip("Set TEST_RUNNER_SYNC_TEST_CODE_FILE to a disposable one-use account code file.")
        }
        app.terminate()
        app.launchArguments = ["--sync-ui-test"]
        app.launchEnvironment["SYNC_TEST_CODE_FILE"] = path
        app.launch()
        let share = app.buttons["Share setup"]
        XCTAssertTrue(share.waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["Connect account"].exists)
        screenshot("sync-account-connected")
        share.tap()
        let addons = app.switches["Addons"]
        let playback = app.switches["Playback preferences"]
        let appearance = app.switches["Appearance"]
        XCTAssertTrue(addons.waitForExistence(timeout: 5))
        XCTAssertEqual(addons.value as? String, "1")
        XCTAssertEqual(playback.value as? String, "0")
        XCTAssertEqual(appearance.value as? String, "0")
        XCTAssertFalse(app.switches["Playback progress"].exists)
        appearance.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let enabled = expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: appearance)
        wait(for: [enabled], timeout: 5)
        screenshot("sync-sharing-categories")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Add my device"].exists)
    }

    @MainActor
    func test4KPlaybackAdvances() {
        installTestAddonIfNeeded(name: "4K Playback Test", manifestURL: "http://127.0.0.1:8768/manifest.json")
        openSeries("Lanterns")
        episodeCard().tap()
        let source = app.buttons.matching(NSPredicate(format: "label CONTAINS '4K Playback Test'")).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 15))
        source.tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 30))
        let position = app.sliders["Playback position"].value as? String
        XCTAssertNotNil(position)
        app.buttons["More"].tap()
        app.buttons["Playback Info…"].tap()
        XCTAssertTrue(app.staticTexts["Playback Info"].waitForExistence(timeout: 5))
        screenshot("4k-playback-info")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '3840' AND label CONTAINS '2160'"))
            .firstMatch.exists, "Fixture must actually decode at 4K")
        app.buttons["Done"].tap()
        if !app.buttons["Close"].exists { app.tap() }
        XCTAssertNotEqual(app.sliders["Playback position"].value as? String, position)
        screenshot("4k-playing")
        app.buttons["Close"].tap()
        XCTAssertTrue(episodeCard().exists)
    }

    /// Details and sources hide the iPhone's tab bar, and every way back brings it back.
    @MainActor
    func testPhoneTabBarFollowsTitlePages() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("The iPad keeps its tabs on every page.")
        }
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        openTab("Settings")
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(tabBar.exists, "Settings keeps the tab bar")
        openTab("Home")

        startPlayback()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(waitForWindow(landscape: true), "The player didn't turn")
        if !app.buttons["Close"].exists { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap() }
        app.buttons["Close"].tap()
        XCTAssertTrue(waitForWindow(landscape: false), "Browsing didn't turn back upright")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertFalse(tabBar.waitForExistence(timeout: 2), "Closing the player over a title's page keeps the bar hidden")

        // Sources, if playback came through its list, then details, then Home.
        for _ in 0..<2 where !tabBar.exists {
            app.navigationBars.buttons.firstMatch.tap()
            _ = tabBar.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(tabBar.exists, "Going back brings the tab bar back")
    }

    @MainActor
    func testBuiltInDiscoveryWithoutAddons() {
        openTab("Settings")
        let addons = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Addons'")).firstMatch
        XCTAssertTrue(addons.waitForExistence(timeout: 5))
        addons.tap()
        XCTAssertTrue(app.staticTexts["No playback addons yet"].waitForExistence(timeout: 5),
                      "Run this flow on a fresh simulator without installed addons")
        openTab("Home")
        XCTAssertTrue(app.buttons["Play"].firstMatch.waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Popular Movies"].waitForExistence(timeout: 20))
        screenshot("builtin-home")
        openTab("Search")
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Dune")
        let movie = app.buttons["Dune"].firstMatch
        XCTAssertTrue(movie.waitForExistence(timeout: 20))
        movie.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'IMDb '")).firstMatch
            .waitForExistence(timeout: 15))
        let reviewLabel = NSPredicate(format: "label CONTAINS 'Letterboxd'")
        let reviews = app.links.matching(reviewLabel).firstMatch
        for _ in 0..<5 {
            if reviews.exists && reviews.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(reviews.exists || app.buttons.matching(reviewLabel).firstMatch.exists)
        screenshot("builtin-movie-ratings")
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
    func testSearchGenreCanBeRemovedAndNarrowsTypedSearches() {
        openTab("Search")
        XCTAssertFalse(app.buttons["Genre"].exists, "The genre list is the way in before typing")
        app.buttons["Drama"].firstMatch.tap()
        let chip = app.buttons["Drama, remove genre"]
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        screenshot("search-genre-chip")
        chip.tap()
        XCTAssertTrue(app.staticTexts["Genres"].waitForExistence(timeout: 5))

        let field = app.searchFields.firstMatch
        field.tap()
        field.typeText("heat")
        XCTAssertTrue(app.buttons["Genre"].waitForExistence(timeout: 5))
        screenshot("search-typed-genre-menu")
    }

    @MainActor
    func testSearchAndSeeAllFilterByGenreTypeAndSort() {
        openTab("Search")
        let comedy = app.buttons["Comedy"].firstMatch
        XCTAssertTrue(comedy.waitForExistence(timeout: 5))
        screenshot("search-genres")
        comedy.tap()
        XCTAssertTrue(app.staticTexts["Series · Comedy"].waitForExistence(timeout: 20))
        screenshot("search-genre-browse")

        app.segmentedControls.buttons["Series"].tap()
        XCTAssertFalse(app.staticTexts["Movies · Comedy"].exists)
        let field = app.searchFields.firstMatch
        field.tap()
        field.typeText("office")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Office'")).firstMatch
            .waitForExistence(timeout: 30), "No comedy series for office")
        screenshot("search-genre-results")
        field.buttons.firstMatch.tap()

        // A genre's See All can switch to another catalog that offers the genre.
        app.buttons["Series · Comedy"].firstMatch.tap()
        app.buttons["Sort"].firstMatch.tap()
        app.buttons["Featured"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Featured Series · Comedy"].waitForExistence(timeout: 5))
        screenshot("grid-sorted-genre")

        // Cinemeta's "New" catalog filters by year instead.
        openTab("Home")
        app.buttons["Popular Movies"].firstMatch.tap()
        app.buttons["Sort"].firstMatch.tap()
        app.buttons["New"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Year"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars.matching(NSPredicate(format: "identifier BEGINSWITH 'New Movies · '")).firstMatch
            .waitForExistence(timeout: 5))
        screenshot("grid-new-by-year")
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
        // Play starts by itself only with a source remembered from an earlier play.
        startPlayback()
        if !app.buttons["Close"].exists { app.tap() }
        app.buttons["Close"].tap()
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
    func testPlaybackTimelineAdvances() {
        startPlayback(series: "Slow Horses")
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 20))
        let slider = app.sliders["Playback position"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        let initial = slider.value as? String
        XCTAssertNotNil(initial)
        // Pause keeps the controls visible after the auto-hide deadline and samples the real clock.
        sleep(3)
        if !app.buttons["Pause"].exists { app.tap() }
        app.buttons["Pause"].tap()
        XCTAssertNotEqual(slider.value as? String, initial, "Timeline stayed frozen during playback")
        screenshot("advancing-timeline")
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Season"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testClosingActivePlaybackCanStartAgain() {
        // Keep this title separate from the longer track/4K fixtures' resume history.
        startPlayback(series: "Slow Horses")
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
        XCTAssertTrue(app.buttons["Audio"].waitForExistence(timeout: 5), "Done didn't close the timing panel")
        XCTAssertFalse(done.exists, "Done didn't close the timing panel")
        // Tapping the picture closes it too, as it closes a menu.
        app.buttons["Audio"].tap()
        app.buttons["Audio Timing…"].tap()
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Audio"].waitForExistence(timeout: 5), "Tapping the picture didn't close the timing panel")
        XCTAssertFalse(done.exists, "Tapping the picture didn't close the timing panel")
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

    /// Waits for the window to take the shape the device turned to.
    @MainActor
    private func waitForWindow(landscape: Bool, timeout: TimeInterval = 5) -> Bool {
        // The application's frame: on iPad, windows.firstMatch reports an empty one.
        let turned = NSPredicate { [app] _, _ in (app!.frame.width > app!.frame.height) == landscape }
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: turned, object: nil)], timeout: timeout) == .completed
    }

    /// iPhone browsing stays upright when the phone turns; iPad turns with it. The waits
    /// before checking give a wrong turn time to happen.
    @MainActor
    func testRotationAndPullToRefresh() {
        XCTAssertTrue(app.staticTexts["Popular Movies"].waitForExistence(timeout: 15))
        app.swipeDown()
        XCTAssertTrue(app.staticTexts["Popular Movies"].waitForExistence(timeout: 15), "Rows gone after refresh")

        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        func isUpright() -> Bool {
            let frame = app.windows.firstMatch.frame
            return frame.height > frame.width
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(2)
        screenshot("rotated-home")
        XCTAssertEqual(isUpright(), isPhone)
        XCUIDevice.shared.orientation = .portrait
        openSeries("Lanterns")
        XCTAssertTrue(app.buttons["Season"].waitForExistence(timeout: 15))
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(3)
        screenshot("rotated-details")
        XCTAssertEqual(isUpright(), isPhone)
        XCUIDevice.shared.orientation = .portrait
    }

    /// The picture should fill the new size after each turn; check the screenshots.
    @MainActor
    func testRotatingDuringPlayback() {
        startPlayback()
        let pause = app.buttons["Pause"]

        // The test clips are 10 seconds long, so both turns happen well before the end.
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(waitForWindow(landscape: true), "The player didn't turn")
        screenshot("rotated-while-playing")

        // A tap toggles the controls; aim above the middle, where the play button sits.
        if !app.buttons["Close"].exists { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap() }
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 3), "Player closed when rotated")
        if pause.exists { pause.tap() }
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(waitForWindow(landscape: false), "The player didn't turn back")
        screenshot("rotated-while-paused")
        if !app.buttons["Close"].exists { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap() }
        app.buttons["Close"].tap()
        XCTAssertGreaterThan(app.frame.height, app.frame.width, "Browsing didn't turn back upright")
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
        XCTAssertTrue(pip.waitForNonExistence(timeout: 5), "The player screen stayed open")
        screenshot("pip-started")

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
        XCTAssertTrue(restore.waitForNonExistence(timeout: 5), "The floating window stayed")
        XCTAssertFalse(app.buttons["Picture in Picture"].exists, "The player came back")
    }

    @MainActor
    func testPictureInPictureSkippingPreservesPlaybackState() throws {
        installTestAddonIfNeeded(name: "Playback Test Streams", manifestURL: "http://127.0.0.1:8766/manifest.json")
        openSeries("Lanterns")
        episodeCard().tap()
        let source = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Local Multi Track'")).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 15))
        source.tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 30))
        // The controls can fade between XCTest locating Pause and delivering its tap.
        for _ in 0..<3 where !app.buttons["Play"].exists {
            if !app.buttons["Close"].exists { app.tap() }
            if app.buttons["Pause"].exists { app.buttons["Pause"].tap() }
        }
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
        let timeline = app.sliders["Playback position"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 5))
        timeline.adjust(toNormalizedSliderPosition: 0.2)
        let pausedPosition = app.sliders["Playback position"].value as? String
        let pip = app.buttons["Picture in Picture"]
        guard pip.waitForExistence(timeout: 10) else { throw XCTSkip("Picture in Picture isn't available on this simulator") }
        pip.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let restore = springboard.buttons.matching(NSPredicate(format:
            "label IN %@", ["Restore Full Screen", "Vollbildmodus wiederherstellen"])).firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        screenshot("pip-skip-controls")
        let forward = springboard.buttons.matching(NSPredicate(format:
            "label CONTAINS[c] 'forward' OR label CONTAINS[c] 'vorspringen'")).firstMatch
        let backward = springboard.buttons.matching(NSPredicate(format:
            "label CONTAINS[c] 'backward' OR label CONTAINS[c] 'zurückspringen'")).firstMatch
        XCTAssertTrue(forward.exists)
        XCTAssertTrue(backward.exists)
        forward.tap()
        restore.tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5), "Skipping a paused video started playback")
        XCTAssertNotEqual(app.sliders["Playback position"].value as? String, pausedPosition,
                          "PiP's skip completion ran without moving the paused video")
        app.buttons["Play"].tap()
        app.buttons["Picture in Picture"].tap()
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        forward.tap()
        backward.tap()
        forward.tap()
        restore.tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5), "PiP skipping left playback paused")
        let position = app.sliders["Playback position"].value as? String
        XCTAssertNotNil(position)
        sleep(2)
        if !app.buttons["Close"].exists { app.tap() }
        XCTAssertNotEqual(app.sliders["Playback position"].value as? String, position,
                          "Playback did not advance after PiP skips")
        screenshot("pip-skips-playing")
        app.buttons["More"].tap()
        app.buttons["Playback Info…"].tap()
        XCTAssertTrue(app.staticTexts["Video bitrate"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Audio bitrate"].exists)
        screenshot("pip-skips-bitrate")
        app.buttons["Done"].tap()
        if !app.buttons["Close"].exists { app.tap() }
        app.buttons["Close"].tap()
    }

    @MainActor
    func testTransportSeeksPreservePlaybackState() {
        installTestAddonIfNeeded(name: "Playback Test Streams", manifestURL: "http://127.0.0.1:8766/manifest.json")
        openSeries("Lanterns")
        episodeCard().tap()
        let source = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Local Multi Track'")).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 15))
        source.tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 30))
        for _ in 0..<3 where !app.buttons["Play"].exists {
            if !app.buttons["Close"].exists { app.tap() }
            if app.buttons["Pause"].exists { app.buttons["Pause"].tap() }
        }
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
        let timeline = app.sliders["Playback position"]
        func position() -> Double? {
            guard let value = timeline.value as? String else { return nil }
            let parts = value.split(separator: ":").compactMap { Double($0) }
            guard parts.count >= 2 else { return nil }
            return parts.reduce(0) { $0 * 60 + $1 }
        }
        timeline.adjust(toNormalizedSliderPosition: 0)
        expectation(for: NSPredicate { _, _ in position() == 0 }, evaluatedWith: nil)
        waitForExpectations(timeout: 10)
        app.buttons["Forward 10 seconds"].tap()
        let moved = NSPredicate { _, _ in (position() ?? 0) >= 8 }
        expectation(for: moved, evaluatedWith: nil)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.buttons["Play"].exists, "Seeking started a paused video")
        let forwardPosition = position() ?? 0
        app.buttons["Back 10 seconds"].tap()
        let movedBack = NSPredicate { _, _ in
            guard let seconds = position() else { return false }
            return seconds <= forwardPosition - 8
        }
        expectation(for: movedBack, evaluatedWith: nil)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.buttons["Play"].exists)
        screenshot("transport-seeks-paused")
        app.buttons["Play"].tap()
        app.buttons["Forward 10 seconds"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 10))
        let playingPosition = timeline.value as? String
        sleep(2)
        if !app.buttons["Close"].exists { app.tap() }
        XCTAssertNotEqual(timeline.value as? String, playingPosition, "Playback stopped advancing after seeking")
        screenshot("transport-seeks-playing")
        app.buttons["Close"].tap()
    }

    /// With a measured speed below some sources' bitrates, the best one that fits is marked
    /// but not played.
    @MainActor
    func testSourcesRecommendOneForTheConnection() {
        app.terminate()
        app.launchArguments = ["-connectionSpeed", "32000000"]
        app.launch()
        installTestAddonIfNeeded()
        openSeries("Lanterns")
        episodeCard().tap()
        let recommended = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'recommended'")).firstMatch
        XCTAssertTrue(recommended.waitForExistence(timeout: 15), "No source recommended")
        XCTAssertFalse(app.buttons["Pause"].exists, "The recommended source started by itself")
        screenshot("source-recommended")
    }

    @MainActor
    func testSourceBitrateFilteringAndSorting() {
        installTestAddonIfNeeded()
        openSeries("Lanterns")
        episodeCard().tap()
        let higherRate = app.buttons.matching(NSPredicate(format: "label MATCHES '.*25[,.]2 Mbps.*'")).firstMatch
        XCTAssertTrue(higherRate.waitForExistence(timeout: 15))
        screenshot("source-bitrates")
        app.buttons["Sort & Filter"].tap()
        screenshot("source-sort-menu")
        app.buttons["Sort by"].tap()
        app.buttons["Lower bitrate"].tap()
        app.buttons["Sort & Filter"].tap()
        app.buttons["Maximum bitrate"].tap()
        app.buttons["Up to 25 Mbps"].tap()
        XCTAssertTrue(app.staticTexts["Up to 25 Mbps, estimated from the size where not reported. Unknown bitrates stay visible."].exists)
        XCTAssertFalse(higherRate.exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label MATCHES '.*23[,.]6 Mbps.*'")).firstMatch.exists)
        screenshot("source-bitrate-filter")
        app.buttons["Sort & Filter"].tap()
        app.buttons["Maximum bitrate"].tap()
        app.buttons["Any bitrate"].tap()
        XCTAssertTrue(higherRate.exists)
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
        app.buttons["More"].tap()
        app.buttons["Playback Info…"].tap()
        XCTAssertTrue(app.staticTexts["Hardware decoder"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Buffered"].exists)
        sleep(2)
        screenshot("playback-info")
        app.buttons["Done"].tap()
        if !app.buttons["Close"].exists { app.tap() }
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

    /// Screenshots of each main screen, to compare before and after a change.
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
        // The backdrop fades as the page scrolls past it.
        app.swipeUp()
        sleep(1)
        screenshot("tour-details-scrolled")
        app.swipeDown()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Choose a Source'")).firstMatch.tap()
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
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Trakt'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "No Trakt row in Settings")
        row.tap()
        let keys = app.textFields["Client ID"]
        let signedIn = app.staticTexts["Signed in as"]
        let signIn = app.buttons["Sign In"]
        XCTAssertTrue(keys.waitForExistence(timeout: 5) || signedIn.exists || signIn.exists, "No Trakt section")
        screenshot("settings-trakt")
    }

    // MARK: Helpers

    /// Chooses the short local-addon fixture explicitly, independent of remembered sources.
    /// Leaves the controls showing; subsequent Play/Resume actions exercise autoplay.
    @MainActor
    private func startPlayback(series: String = "Lanterns") {
        installTestAddonIfNeeded()
        openSeries(series)
        episodeCard().tap()
        // Once playing, the controls fade out; while they're up, Close is showing.
        let testSource = app.buttons.matching(NSPredicate(format: "label CONTAINS 'DTS 5.1'")).firstMatch
        let pause = app.buttons["Pause"]
        for _ in 0..<30 {
            if pause.exists { return }
            if testSource.exists && testSource.isHittable {
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
        let addons = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Addons'")).firstMatch
        if addons.waitForExistence(timeout: 5) { addons.tap() }
        let installedName = name == "Test Streams" ? ProcessInfo.processInfo.environment["PLAYBACK_TEST_ADDON_NAME"] ?? name : name
        guard !app.staticTexts[installedName].waitForExistence(timeout: 5) else { return }
        let field = app.textFields["Manifest URL"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        let url = name == "Test Streams" ? ProcessInfo.processInfo.environment["PLAYBACK_TEST_ADDON_URL"] ?? manifestURL : manifestURL
        field.typeText(url + "\n")
        XCTAssertTrue(app.staticTexts[installedName].waitForExistence(timeout: 10), "Test addon didn't install")
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
}
#endif
