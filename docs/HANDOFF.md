# Loge handoff — 2 November 2026

## Start here

- Active local checkout: `/Users/tjh/Developer/MediaApp/.claude/worktrees/todo-batch`.
- Handoff branch: `codex/tmdb-discovery-handoff`, targeting `main`.
- Base: `d7d4502` on `main`; its tree matches `4243d49` from yesterday's `claude/todo-batch`.
- Run `Tools/check-checkout.sh`, `pwd`, `git status --short --branch`, and `git worktree list` before editing or building. Fetch and compare remote changes when resuming.
- The top-level `/Users/tjh/Developer/MediaApp` checkout is stale and retains a separate copy of earlier work. Do not build there or copy its old files over this checkout. Its unrelated release/tooling edits were deliberately not included here.
- Nothing in this batch has been installed on the user's physical iPad, iPhone or Apple TV. Commit/PR creation does not deploy it.

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
xcodebuild -project MediaApp.xcodeproj -scheme MediaApp -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/xcode -jobs 2 SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build
```

Use `generic/platform=tvOS Simulator` and `platform=macOS` for the other builds. Keep simulators sequential and builds modest (`-jobs 2`); the user explicitly requested this.

For optional live checks, create a private temporary token file yourself, never in the repo, and set `TMDB_TEST_TOKEN_FILE` for Core tests. For UI tests use `TEST_RUNNER_UI_FLOWS=1`, `TEST_RUNNER_TMDB_TEST_TOKEN_FILE=<temporary file>` and `-only-testing:MediaAppUITests/TMDBFilmographyTests`. The DEBUG-only bootstrap reads the file into an in-memory account and never saves it to Keychain. RemoteDriverTests accepts the same file plus optional `TEST_RUNNER_TMDB_TEST_PERSON_ID`/`TEST_RUNNER_TMDB_TEST_PERSON_NAME` for a deterministic person-page entry. These debug entry points are absent from Release behavior.

The token supplied in chat was used only for checks. Its temporary file and explicit REPL credential binding were removed. Do not copy credentials from chat into source, fixtures, commands, PR text, logs or memory. The user connected TMDB on their own device; no replacement token is committed.

## Remaining and limitations

1. Test real-device playback close/reopen, timeline, skip offers, tvOS focus while skipping, audio selection and PiP/source changes. Skip model tests and UI placement are implemented; actual skip seeking was not exercised end-to-end with a chaptered fixture in this batch.
2. Reviews remain outbound IMDb critic/Letterboxd links, not embedded review text. Letterboxd currently excludes private/personal projects from API access. Do not describe this as a completed embedded-review feature.
3. Festival pages show selected recorded prize winners from Wikidata, newest first (up to 40), not every award from the latest festival edition. Data can be incomplete/delayed or time out; Retry and official links exist. Locarno explicitly combines competitions.
4. TMDB data is provider data, not a guarantee of every real-world credit. Missing IMDb mappings prevent playback/save until mapped; numeric TMDB IDs must never enter the existing IMDb-based library or stream routes.
5. Person-page role filtering (acting versus directing/other crew) could be a useful future refinement; the current filters are Movies/Series and sorting.
6. No physical-device installation, Release/archive build, PR merge or deployment has been performed. Check PR CI separately; local success is not a CI result.
