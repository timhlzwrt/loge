# loge handoff — 2 November 2026

## Start here

- Active local checkout: `/Users/tjh/Developer/MediaApp/.claude/worktrees/todo-batch`.
- Current branch: `codex/remaining-features`, targeting `main`.
- Current base: `661ccc1` on `main`; includes PR #12 and the earlier todo batch.
- Run `Tools/check-checkout.sh`, `pwd`, `git status --short --branch`, and `git worktree list` before editing or building. Fetch and compare remote changes when resuming.
- The top-level `/Users/tjh/Developer/MediaApp` checkout is stale and retains a separate copy of earlier work. Do not build there or copy its old files over this checkout. Its unrelated release/tooling edits were deliberately not included here.
- The 3 November follow-up installed a Debug test build on the paired iPhone after the user configured Xcode signing. No physical iPad or Apple TV installation was made. See the verification follow-up below.

## Implemented

### TMDB and browsing

- Settings accepts an API Read Access Token, validates before saving, and keeps it in the device Keychain. Replacement/removal failures preserve a working connection; cancellation and stale responses cannot overwrite newer credentials. Required approved logo/notice are in Credits.
- Title pages enrich addon metadata using IMDb IDs. Episode IDs, IMDb ratings, playback routing, saved lists and artwork repair retain their existing formats/meaning.
- Added status, release/air dates, original title/language, countries, production companies, separately labeled TMDB ratings/vote counts, movie budget/revenue and series season/episode totals, when available.
- Bounded credential-scoped memory caches deduplicate requests: 128 titles/30 min, 32 people/1 hour, 256 IMDb mappings/1 hour. Errors are not cached. Successful missing IMDb mappings can be cached; malformed/error-shaped responses are retryable failures.
- Small debounced preloads warm current/next featured titles, focused TV titles/directors, and the first actor/director of an open title. No whole-filmography per-title request fan-out.
- Person pages fetch full combined TMDB movie/TV cast and crew credits, deduplicate by media kind + numeric ID, and provide biography, counts, movie/series filters, roles and sorting. This includes appearances and non-directing crew work; it is not restricted to directed films. No 40-title cap.
- IMDb mapping is resolved only when a credit is opened. A title without an IMDb mapping remains visible as metadata, with no playback/save actions using a fabricated ID. Legacy people without a TMDB ID use clearly labeled catalog-search fallback.
- Quiet loading placeholders retain known title/person context. Actor images fall back to initials.
- Festival/director shelves follow all catalogs. Seven bundled festival logos: Cannes, Berlinale, Venice, Sundance, Toronto, Locarno and San Sebastián. Connected curated directors open TMDB person pages. Asset provenance is included.

### Playback and lists

- Preserved yesterday's mixed hero, Letterboxd shelf, genre browsing, filters/sort/year, accent settings, decoded artwork caching/repair, split movie/series saved grids and existing TitleList persistence.
- Watch Later is the default save action. Holding posters/save controls exposes membership in existing custom lists; existing create/rename/delete flows remain.
- Torrent descriptors, magnet/non-HTTP URLs and `.torrent` paths are rejected both at addon filtering and player entry. There is no local peer-to-peer backend. External HTTP providers' server behavior is outside this app.
- Close ends playback and dismisses presentation; timeline refresh polls asynchronous mpv properties and ignores invalid readings. Newer asynchronous mpv commands, separate subtitle layer and timing-panel dismissal were preserved.
- Intro/recap/credits offers use explicit chapter boundaries or duration/confidence-matched TheIntroDB segments. The offer remains visible after ordinary transport controls hide. English is the default audio preference when no preference is stored and a matching track exists.
- Existing local iOS 26 deployment compatibility and iPad orientations are retained in the project/package settings.

## Verified

- `swift test --package-path Core`: 170 tests passed with the optional live TMDB test enabled. Ordinary CI skips that live test without its temporary credential file.
- Live API checks covered Interstellar, Breaking Bad, actor/director combined credits and movie/show IMDb mapping. At verification Nolan returned 78 credits (64 movies/14 shows); provider records may change.
- iPhone: richer information, actor and director filmographies, movie/show filters.
- iPad: same flows, including opening a credited show and loading canonical details/episodes.
- Apple TV: actual person page with live credits and remote segmented-control focus.
- iOS, tvOS and macOS Debug builds passed with `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`. The known Xcode AppIntents metadata-extraction notice remains.
- `git diff --check` passed. A repository scan found no supplied API token.

Local logs/screenshots were written under `/tmp/loge-rich-*` and may not survive cleanup. Earlier playback fixture checks passed close/reopen and advancing timeline, but were not rerun against physical devices after this port.

### Reproduce

```sh
Tools/check-checkout.sh
xcodegen generate
swift test --package-path Core
xcodebuild -project loge.xcodeproj -scheme loge -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/xcode -jobs 2 SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build
```

Use `generic/platform=tvOS Simulator` and `platform=macOS` for the other builds. Keep simulators sequential and builds modest (`-jobs 2`); the user explicitly requested this.

For optional live checks, create a private temporary token file yourself, never in the repo, and set `TMDB_TEST_TOKEN_FILE` for Core tests. For UI tests use `TEST_RUNNER_UI_FLOWS=1`, `TEST_RUNNER_TMDB_TEST_TOKEN_FILE=<temporary file>` and `-only-testing:logeUITests/TMDBFilmographyTests`. The DEBUG-only bootstrap reads the file into an in-memory account and never saves it to Keychain. RemoteDriverTests accepts the same file plus optional `TEST_RUNNER_TMDB_TEST_PERSON_ID`/`TEST_RUNNER_TMDB_TEST_PERSON_NAME` for a deterministic person-page entry. These debug entry points are absent from Release behavior.

The token supplied in chat was used only for checks. Its temporary file and explicit REPL credential binding were removed. Do not copy credentials from chat into source, fixtures, commands, PR text, logs or memory. The user connected TMDB on their own device; no replacement token is committed.

## Remaining and limitations

1. Real-device playback close/reopen, timeline, skip offers, tvOS focus while skipping, audio selection and PiP/source changes still need verification. Simulator playback checks use actual decoding/seeking with synthetic timing boundaries; provider chapter detection remains a separate check.
2. Embedded TMDB member reviews are implemented in the follow-up below. Critic and Letterboxd reviews remain external links.
3. Latest 2026 editions are bundled in the follow-up below, with explicit coverage and checked dates. Historical Wikidata lists remain available and can be incomplete/delayed or time out.
4. TMDB data is provider data, not a guarantee of every real-world credit. Missing IMDb mappings prevent playback/save until mapped; numeric TMDB IDs must never enter the existing IMDb-based library or stream routes.
5. Person-page role filtering is implemented in the 3 November follow-up below.
6. A Debug test build was installed on the paired iPhone in the later follow-up. No Release/archive build, PR merge or deployment has been performed. Check PR CI separately; local success is not a CI result.

## 3 November follow-up — remaining features

The confirmed `todo-batch` worktree now uses `codex/remaining-features`, based on
`661ccc1` (current main, including History, the tvOS browse fix, and PR #12's rename/UI pass).
The top-level checkout's untracked file was left untouched.

First feature: person pages offer All roles, Acting, Directing and Other crew,
combined with the existing movie/series filters and sorting. Apple TV uses a
segmented role picker for remote navigation; other platforms use a menu with an
explicit accessible name and selected value. Counts follow the selected role.
Mixed credits retain every applicable role; only TMDB's Director job counts as directing, so camera and assistant-director jobs remain crew.
This uses existing combined credits with no extra requests or persistence changes.
An offline DEBUG-only launch fixture (`--person-role-ui-test`) supports
`logeUITests/PersonRoleTests` without credentials.

Popularity-ranked directors, embedded TMDB reviews and fuller latest-edition festival
lists are now implemented; details follow below. Top Shelf, real-device playback,
HDR/display matching and live Trakt checks still need the prerequisites listed below.

Verification for this follow-up: 172 Core tests passed; iOS Simulator, tvOS Simulator
and macOS Debug builds passed with Swift warnings treated as errors (the known
AppIntents metadata-extraction notice remains). The offline Apple TV remote test
passed after using a segmented role picker and waiting for native focus transitions.
The final iPhone UI test passed role/media combinations, counts and empty-state checks.
iPad layout was inspected from the current simulator build; its automated runner
crashed while preparing tests, before running assertions. No physical devices were
installed, and no commit or push was made.

### Reviews, discovery and award editions

- Title details show up to three TMDB member review previews, full-text reading and a
  separate paginated review list. Loading, empty, retry and rejected-token states are
  explicit. Content is rendered as native text/Markdown, never executable HTML; links
  allow HTTP(S) without embedded credentials. IMDb and Letterboxd links remain.
- Connected Home scans at most ten TMDB popular-person pages for primary-department
  directors, sorts by provider popularity, and shows up to twelve. This is a bounded
  provider ranking, not an exhaustive ranking of every director. The disconnected
  editorial shelf is honestly labeled Selected Directors. Both features use existing
  credential-scoped bounded caches and cancel stale results.
- All seven festival pages use a bundled, dated 2026 edition: Cannes 21, Venice 21,
  Berlinale 66, Sundance 40, Toronto 36, Locarno 34, San Sebastián 60 award records.
  Ties, repeated winning films and non-film recipients are preserved. Section filters
  work with the TV remote. Film selection seeds catalog Search, requiring the user to
  choose the actual listing rather than inventing an IMDb mapping or availability.
  Previous recorded winners opens the existing Wikidata collection.
- `Core/Sources/LogeCore/Resources/festival-awards-2026.json` is the source of truth.
  Each edition records scope, checkedOn and source URLs. Lists were checked 2026-11-03;
  they are not automatically refreshed. Cannes, Venice, Sundance and San Sebastián
  use festival publications; Berlinale, Toronto and Locarno also use the cited edition
  references where the official site did not expose the complete list. Maintain the
  facts and citations together, preserve joint awards, and update tests/counts when
  changing scope. Attribution is in Settings → About → Data Sources.

### Playback and hardware prerequisites

DEBUG-only discovery and playback launch fixtures avoid Keychain writes, library
history and external addon lookup. `Tools/test-addon.py --bind/--host` can expose the
fixture intentionally to a paired device; localhost remains the default. The playback
fixture uses actual decoding and seeking with synthetic intro/recap/credits boundaries;
it does not validate provider chapter detection, HDR or display matching.

The iPhone simulator regression passed timeline advancement, English default selection
from German-first media, intro/recap/credits seeks, close/reopen and source replacement.
The physical iPhone run failed before installation: Xcode reported No Accounts and no
profile for `li.tjh.logeUITests.xctrunner`. Sign into the existing developer account in
Xcode Settings → Accounts before retrying. No physical build was installed.

For Top Shelf, filtered Apple TV system-log collection required root; passwordless
sudo was unavailable. Read the paired device in Console (TopShelf / li.tjh.MediaApp,
only extension launch/signing errors) before changing the held extension branch.
The device Home-lag, swipe scrubbing, HDR/display matching and live Trakt checks are
still pending hardware access/credentials. Never put private addon URLs in diagnostics.

### Final verification evidence

- `swift test`: 179 tests passed (`/tmp/loge-todo-core-verified.log`).
- Apple TV `DiscoveryTVTests` and `PersonRoleTests`: four tests passed
  (`/tmp/loge-todo-tv-pass2.xcresult`). Native list cells own section-picker focus;
  tvOS search values include the system dictation hint.
- iPhone `DiscoverySnapshotTests` and `PersonRoleTests`: passed
  (`/tmp/loge-todo-iphone-final.xcresult`). The snapshot test also reads full reviews,
  filters awards and searches the chosen winner, and opens a director's filmography.
- macOS and generic tvOS builds passed with Swift warnings treated as errors, with
  only Xcode's known AppIntents extraction notice (`/tmp/loge-todo-mac-verified.log`,
  `/tmp/loge-todo-tv-verified-build.log`).
- Before/after screenshots use deterministic DEBUG fixtures and are stored outside
  git in the task's visualization directory. Blank portraits in the after fixtures
  are intentional missing-image data, not a change to production image loading.

Final native Mac inspection could not proceed: a process sample shows startup waiting
in `TMDBAccount.loadToken` → `SecItemCopyMatching` inside macOS Security. The user was
asked to clear any Keychain prompt themselves; no credential or Keychain permission
was changed. Earlier native Search/title/review inspection succeeded before rebuilding.

The final iPad discovery snapshot/interaction test passed, and its PiP test passed
restore-to-player with position retained (`/tmp/loge-todo-ipad-final.xcresult`). The
initial credits assertion expected a near-end timestamp; an exact-end seek may instead
report EOF before that position is observed. The revised regression observes both
actual position and ended state. Generic iOS, macOS and tvOS final builds passed
(`/tmp/loge-todo-ios-verified-build.log`, `/tmp/loge-todo-mac-last.log`,
`/tmp/loge-todo-tv-last.log`); no Swift warnings remain.

The corrected iPad playback regression passed
(`/tmp/loge-todo-ipad-playback-pass.xcresult`): real timeline advancement, selected
English audio, intro/recap/credits seeking (position or confirmed EOF), close/reopen
and a real source URL replacement. This completes simulator playback verification;
physical playback and the hardware-only checks above remain outstanding. The local
fixture server was stopped after testing. No commit, push or physical install was made.

### User-cleared prerequisites — 3 November

The user signed into Xcode and approved the Mac Keychain prompt. The Mac build now
starts normally. Native checks verified Settings/Data Sources, live title details
with exactly three review previews, the separate review list and full-text reading,
provider director artwork, and Sundance section filtering followed by a winner-seeded
Search (Josephine). Rendered screenshots were inspected; no new code was needed.

Xcode signing now succeeds for the physical iPhone, and the Debug app/test runner
were installed. The first attempt stopped at device unlock/authentication; the next
attempt started but timed out before the local clip was reachable. After the user
confirmed playback was working, both regressions were retried. The nil-item fixture
keeps this testing out of saved watch history, remembered sources and Trakt.

Physical iPhone final result: both `PlaybackRegressionTests` passed, zero failures
(`/tmp/loge-iphone-hardware-connected.xcresult`, log with the same prefix). The device
exercised actual decoding, advancing time, selected audio, all three synthetic timed
skips, close/reopen, source replacement and PiP restoration with position retained.
These tests do not cover real provider chapters, AIOStreams, HDR, display matching,
Apple TV hardware or live Trakt. The temporary LAN fixture server was stopped.
The installed Debug build retains the existing bundle ID and persistence format;
no commit or push was made.

### Mac browse polish — 3 November

The user rejected the persistent Mac scroll tracks and the award-ledger-first festival
page. `HorizontalShelf` now hides Mac horizontal tracks even with the system's
always-visible scrollbar preference, and shows previous/next mouse buttons only when
content overflows. It is used across catalog, genre, festival/director, library and
cast shelves. Trackpad scrolling remains native; iOS/tvOS retain touch/remote scrolling.
Mac featured-carousel dots are clickable, named controls; animation respects reduced motion.

Festival pages now lead with a deduplicated winning-film poster grid. Award captions
stay under each title; All awards opens the complete section-grouped list, including
non-film recipients. Edition coverage/check dates live there rather than dominating
the film page. Existing historical collections remain available.

A Cinemeta match requires exactly one distinct IMDb movie with the same normalized
title and a release year within one year of the festival. Those winners open their
normal title details directly. Uncertain matches retain award context and Find title;
errors offer retry. Tiles remain actionable while loading, resolving within their
destination. Grid lookup concurrency is capped at four, successful/nil matches are
cached in bounded memory, and simultaneous grid/detail requests share work.

The director shelf supplements up to ten popular-person pages with bare popularity/
portrait requests for the five existing director identities. Sorting uses current
provider popularity across that bounded candidate pool; it is not a claim to an
exhaustive global ranking. Native Mac verification showed Nolan, Tarantino, Spielberg,
Miyazaki and Scorsese together, with actual portraits.

Real Mac before/after captures are in the task visualization directory's `mac-polish`
folder. The festival images use live catalog artwork; no fixture portraits were used.

Polish verification: 188 Core tests passed (`/tmp/loge-polish-core-final.log`).
iPhone discovery/role tests passed (`/tmp/loge-polish-iphone.xcresult`), iPad festival
filter/direct-title navigation passed (`/tmp/loge-polish-ipad.xcresult`), and all four
Apple TV discovery/role tests passed (`/tmp/loge-polish-tv-verified.xcresult`). Native
Mac checks verified mouse paging in both directions, hidden tracks, five real director
portraits, festival filtering, full award access and Josephine opening directly as a
normal title. Shelf endpoints were measured at offsets 0 and 566; sidebar hiding
changed the bound to 422 correctly. Offsets normalize the sidebar safe-area inset.
Temporary geometry accessibility diagnostics were removed before the clean build.

Final Debug builds used Swift warnings as errors on all platforms: logs
`/tmp/loge-polish-mac-clean.log`, `/tmp/loge-polish-ios-verified.log`,
`/tmp/loge-polish-tv-clean.log`. Xcode's known AppIntents extraction notice remains.
No physical-device installation, commit or push was made for this UI-polish pass.
