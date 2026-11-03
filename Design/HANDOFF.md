# Matinee redesign: handoff

A redesign of Home, Details, Sources and Player for iPhone/iPad, Apple TV and Mac. The direction is
Apple's own TV app on iOS/tvOS/macOS 27 (Liquid Glass) with Strand's artwork-led calm. Read the
project's `CLAUDE.md` first; its conventions, privacy rule and verification steps all apply.

- **Reference screens:** `Design/mockups/` — open `index.html` in a browser. One HTML file per
  screen and platform, static, at native size. They are the source of truth for layout and
  hierarchy; this file is the source of truth for values and behaviour.
- **tvOS scale:** tvOS mockups are 1280×720 for a 1920×1080 screen. Multiply every tvOS
  pixel value in the mockups by **1.5** to get points. iPhone (390×844) and Mac (1280×800) are 1:1.
- **Placeholders:** colour fields stand in for posters, backdrops and stills; letter-spaced text
  stands in for title logos (`TitleLogo` already loads the addon's logo). Episode descriptions and
  stream names are sample text.

## Decisions already made (from review)

1. Tab bars and player bars show **icons only**, no text labels (keep accessibility labels).
2. Episodes on iPhone scroll **horizontally**, like tvOS.
3. Sources show **no file names and no addon names**.
4. **Less text overall:** no cast lines, no "X min left" under Continue Watching cards (the
   progress bar says it), no runtime under every episode, no stream details under the player title.
5. Use the whole screen: full-bleed backdrops, content runs under the floating Mac sidebar.
6. Keep `Color.canvas` (charcoal, not black) as the background, as `CLAUDE.md` says. Player
   backgrounds are black.
7. Tint stays white, no accent colour; colour comes from artwork only.

## Tokens

| Token | Value |
|---|---|
| Canvas | `Color.canvas` (unchanged) |
| Primary text | white |
| Secondary text | `.secondary` (≈ white 60 %) |
| Primary button | white capsule, black label, semibold; play glyph + "Resume" / "Resume S1, E6" |
| Secondary buttons | circular, icon only, Liquid Glass |
| Glass | `.glassEffect()` / `.buttonStyle(.glass)`; group adjacent controls in a `GlassEffectContainer` so they read as one capsule |
| Rating | yellow `star.fill` + IMDb rating, last item of the meta line |
| Meta line order | `Genre · Year · Runtime · ★ Rating` (first genre only on iPhone) |
| Progress bar | 3 pt (4 pt tvOS) capsule, inset 10–14 pt from the card edges and bottom, white on white 32 % |
| Watched | white `checkmark.circle.fill` bottom-right on the still |
| Episode caption | `EPISODE 6` (+ ` · 17 MIN LEFT` when started): caption, semibold, uppercase, secondary; title below it in headline weight |
| Section headers | title2 bold (iPhone 22, Mac 19, tvOS 33 pt); chevron only when the header opens a grid |

Corner radii (continuous): landscape cards 14 (iPhone) / 12 (Mac) / 24 pt (tvOS);
posters 12 / 10 / 21 pt; grouped lists 20 (iPhone) / 12 pt (Mac); Mac window content 16.

Liquid Glass is available on every deployment target (27.0), so use the system APIs rather than
blur materials. Check the white primary button against the system's `.glassProminent` with a
white tint; keep whichever looks like the mockup.

## Navigation (`App/LogeApp.swift` → `RootView`)

- Tabs: **Home, My List, Settings, Search** (`role: .search`). My List is new as a tab; today it is
  only a row on Home (`MyListRow`). Keep the row on Home too.
- iPhone: system Liquid Glass tab bar with Search as the separate circle; icons only.
- Mac: `.sidebarAdaptable` sidebar with a **Catalogs** `TabSection` listing the installed catalogs
  (Popular Movies, Popular Series, …) that open `CatalogGridView`. No search field in the toolbar;
  the sidebar has Search. Backdrops extend under the sidebar (`.backgroundExtensionEffect()`).
- tvOS: the system sidebar, collapsed to the "Home" chip at top-left.

## Home (`HomeView`, `TVHome`, `FeaturedCarousel`, `LibraryRows`, `CatalogRow`)

- Hero: full-bleed backdrop with `BackdropFade` plus a left-side fade on tvOS/Mac. Logo, meta line,
  two-line synopsis (none on iPhone), then Resume + glass "Add to My List". Page dots on iPhone/Mac.
  - **iPhone:** edge to edge from the top of the screen (not a card), about 560 pt tall, content
    centred.
  - **tvOS:** no buttons in the hero; focus starts on Continue Watching.
- Continue Watching: landscape stills with the title over the image bottom-left (bold, shadow) and
  the inset progress bar. No caption under the card, except the **focused** card on tvOS, which shows
  "6 min left" under it.
- Catalog rows: posters, no titles under them.

## Details (`MetaDetailView`, `PlayButton`, `MyListButton`, `EpisodesSection`, `EpisodeCard`)

- Backdrop, logo, meta line, synopsis (iPhone: under the buttons, "more" to expand via `ExpandableText`).
- Buttons: `Resume S1, E6` primary, then glass circles **Add to My List** and **Choose a Source**
  (`list.bullet`), icon only on every platform.
- No cast or director line.
- Season picker: "Season 1 ⌄" title2 bold menu on all platforms (no segmented control).
- Episodes: horizontal row on iPhone and tvOS, 4-column grid on Mac. Each: still, episode caption,
  title; on iPhone and Mac also a two-line overview. Start the row at the current episode on iPhone.

## Sources (`SourcesView`, `StreamRow`)

Presentation changes per platform:

- **iPhone:** a sheet (large detent) with grabber, centred title + "5 sources", glass close button.
  Inset grouped lists.
- **Mac:** a sheet over the window: "Choose a Source", the title and count, grouped lists, then
  Cancel / Play (Play is the default button).
- **tvOS:** full screen; dimmed backdrop, title bottom-left, list in the right half. Focused row is
  the system white focus style.

Content:

- Group by resolution: **4K, 1080p, 720p**, then **Other** for anything unparsed.
- Row: release type as the title (Remux, BluRay, WEB-DL, WEB); below it codec · HDR · audio
  (`HEVC · HDR10 · TrueHD Atmos 7.1`); size right-aligned with tabular digits.
- Last played (remembered source): trailing `checkmark`.
- Not cached: whole row at ~45 % opacity and `· not cached` appended to the second line.
  Cached is the norm and gets no marker.
- No filter control, no sort control, no file names, no addon names, no explanatory footer.

**Data needed (Phase 2 "readable sources list" in `CLAUDE.md`):** `StreamSource` has no parsed
fields today. Add a parser in `LogeCore` (with tests in `Core/Tests`) that reads resolution,
release type, video codec, HDR format, audio format/channels, size and cached state from
`name`, `title` and `description`. `behaviorHints.filename` may be used as parser input only, never
shown. Unparseable streams go to **Other** and show `cleanName`. Order within a group: largest
size first.

## Player (`PlayerView`, `PlayerControls`, `TrackMenu`, `TimingPanel`, `NextEpisodeOverlay`)

- **tvOS:**
  - Bottom: title (title2 bold) above a full-width timeline with elapsed time left and remaining
    time right.
  - Swiping down shows a glass tab capsule at top centre, **Info · Subtitles · Audio**, with a glass
    panel under it.
  - Subtitles panel: Language list with a checkmark on the active track, then Size and Delay
    steppers (`−  Medium  +`, `−  +0.3 s  +`).
  - No icon buttons at the bottom.
- **iPhone (landscape):**
  - Top-left: glass close button. Top-right: one glass capsule with PiP and AirPlay.
  - Centre: back 10 s, pause, forward 10 s as plain symbols, no circles.
  - Bottom: title left, one glass capsule right with Subtitles, Audio and Sources (icons only), then
    the timeline, then the times.
- **Mac:**
  - Player window with only "Title · S1 · E6" in the title bar.
  - One floating glass capsule at the bottom centre: back 10 s, pause, forward 10 s, elapsed time,
    timeline, remaining time, Subtitles, Audio, PiP and Full Screen.
- **Up Next** (all platforms): glass card bottom-right with the next episode's still, "Up Next · in 8 s" (caption, secondary),
  the episode title, and Play Now / Cancel.

## Out of scope

Search, Settings, the See All grid and iPad-specific layouts are not mocked. Keep their current
look and apply the tokens above where they touch shared components (`Artwork`,
`WatchProgressBar`, `InfoLine`, `Metrics`).

## Done when

- Every screen above matches its mockup on all three platforms, in light of the decisions list.
- The project's own checks pass (`CLAUDE.md` → Conventions): warning-free builds for iOS, tvOS and
  macOS, `swift test` in `Core`, and simulator screenshots of each screen, including tvOS focus
  driven with `UITests/RemoteDriverTests.swift`.
- Accessibility: every icon-only button has a label; VoiceOver reads "Last played" and "Watched";
  Dynamic Type does not clip the meta line or episode titles.
- No addon manifest URL, file name or addon name is shown or logged.
