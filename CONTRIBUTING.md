# Contributing

[Back to loge](README.md) · [Roadmap](ROADMAP.md)

Start with an existing issue, a reproducible bug, or a small proposal. Discuss
broad changes to playback, sync, navigation or dependencies before implementing
them. iPhone/iPad and Apple TV are equal primary platforms; preserve Mac behavior too.

## Local setup

Use the verified Xcode 27.2 toolchain and XcodeGen. The generated `.xcodeproj` is ignored;
edit `project.yml` and regenerate it rather than committing project-file edits.
Runtime minimums are documented separately in [Requirements](docs/REQUIREMENTS.md).

```sh
xcodegen generate
(cd Core && swift test)
```

## Checks before a pull request

Build all three platforms with Swift warnings treated as errors:

```sh
for destination in 'generic/platform=iOS Simulator' \
                   'generic/platform=tvOS Simulator' \
                   'platform=macOS'; do
  xcodebuild build -project loge.xcodeproj -scheme loge \
    -destination "$destination" -derivedDataPath .build/xcode \
    SWIFT_TREAT_WARNINGS_AS_ERRORS=YES || exit
done
python3 -B -m unittest discover -s Tools -p test_publish_release.py
```

For gateway changes, use a local virtual environment and run its tests:

```sh
python3 -m venv .build/gateway-tests
.build/gateway-tests/bin/python -m pip install -r Tools/sync-gateway/requirements-dev.txt
.build/gateway-tests/bin/python -m unittest discover -s Tools/sync-gateway -p 'test_*.py'
```

The Core suite is offline by default; live provider/service tests are opt-in.
Do not describe skipped live checks as verified. CI also runs the gateway tests,
release-publishing regressions, Core tests and the three platform builds.
The `xcode-27` runner label is repository-specific; forks need their own
compatible runner configuration.

## UI and playback checks

For UI changes, inspect the affected flow on iPhone, iPad and Mac; check focus
and remote navigation on Apple TV when affected. Use the existing `UITests/`
flows and [app overview](docs/APP_OVERVIEW.md#verification-workflow), not a second
test harness. The local [test addon](Tools/test-addon.py) provides synthetic
streams without personal provider credentials.

Planned verification focuses on simulators, automated tests and Mac builds;
real-device testing isn't a release requirement. Simulator checks don't establish
HDR output, display matching, physical remote gestures or real cross-device handoff.
If contributors supply hardware or live-service results, report those separately.
Include screenshots for visual changes and state which platforms could not be tested.
See the maintainer's [testing scope](ROADMAP.md#a-note-from-the-maintainer).

## Keep changes focused

- Follow the existing SwiftUI/platform patterns and domain-based Core layout.
- Reuse existing components and utilities; avoid dependencies for small features.
- Add focused regression tests for behavior changes. Keep unrelated refactors out.
- Document user-visible behavior and changed compatibility/sync contracts.
- Inspect the complete diff for generated files, debugging output and secrets.

## Protect private configuration

Never commit configured addon manifest URLs, stream URLs with credentials,
Trakt/TMDB tokens, sync connection codes, recovery keys or signing private keys.
Use synthetic fixtures and redact screenshot/log contents before sharing them.
Do not dump app preferences to diagnose a problem: they can contain addon credentials.

The sync gateway's administrative token and CouchDB service must stay private.
Use the [self-hosting guide](Tools/sync-gateway/README.md) for isolated local tests.
For Mac release-signing changes, read [Mac updates](docs/MAC_UPDATES.md).

## Packaging

- `Tools/build-ipa.sh`: unsigned iOS/tvOS IPAs in `.build/ipa`.
- `Tools/build-dmg.sh`: Mac DMG in `.build/dmg`, self-signed when `MAC_SIGNING_KEYCHAIN` is set.
- Signed Mac update publishing requires the maintainer's Actions secret; it is
  not required for ordinary development and must never enter a pull request.

Contributions are made under the repository's [GPL-3.0 licence](LICENSE).
