# Mac updates

The Mac app embeds Sparkle 2 through Swift Package Manager. Users check from the
loge menu or Settings → About and can opt into daily automatic checks. Downloads
and the appcast are verified with Ed25519 signatures before installation. Sparkle
handles replacing the app and relaunching it; loge saves playback before relaunch.
The app remains ad-hoc signed: the initial installation still needs macOS's
Privacy & Security → Open Anyway. Existing installations without Sparkle need
one manual DMG installation to receive the updater.

## Signing key

The public key lives in `project.yml`, which generates `App/Info.plist`. Its private
counterpart belongs in the repository's encrypted Actions secret
`SPARKLE_PRIVATE_KEY`. Never commit the private key or put it in a release asset.
Keep a secure backup: an ad-hoc signed app cannot recover from a lost signing key
through Apple's Developer ID key rotation.

For a fork, use Sparkle's bundled `generate_keys` tool to create a separate key,
replace `SUPublicEDKey` and the feed/download URLs, and configure your own secret.
The official tools are downloaded with the package to
`.build/xcode/SourcePackages/artifacts/sparkle/Sparkle/bin`.
See [Sparkle's signing documentation](https://sparkle-project.org/documentation/).

## Release workflow

1. `Tools/build-dmg.sh` builds the Mac release and creates a styled drag-to-Applications
   image. A pinned build-only `dmgbuild` virtual environment writes Finder metadata
   without requiring a desktop session. `Tools/render-dmg.swift` renders its Retina
   background; `Tools/dmg-settings.py` sets the window and icon positions.
2. `Tools/prepare-mac-update.sh build-N NOTES_FILE` uses `SPARKLE_PRIVATE_KEY` from
   the environment to generate and verify a signed appcast from that DMG. It embeds
   release notes and infers the required macOS version and CPU from the actual app.
3. The workflow publishes the DMG and `appcast.xml` together with the mobile assets.
   The appcast uses the immutable `build-N` release download URL.
4. The workflow downloads the latest published appcast into the Pages artifact alongside
   the SideStore source. This preserves matching signatures on workflow reruns,
   even if the release was already published. The updater reads
   `https://tjh.li/loge/appcast.xml`.

Releases fail early if the signing secret is absent. Publishing does not change
an already published release. Do not manually edit the generated XML: the feed
itself is signed, so any edits require signing again.
