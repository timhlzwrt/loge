# Install and set up loge

[Back to loge](../README.md) · [Platform requirements](REQUIREMENTS.md)

loge is pre-1.0 and is not in the App Store. Only download official builds from
[timhlzwrt/loge Releases](https://github.com/timhlzwrt/loge/releases).
The iOS and tvOS `.ipa` files are unsigned; your sideloading tool signs them.
A free Apple ID is sufficient, but its signatures expire after seven days.
Refreshing a signature is separate from updating to a newer loge build.

Current source minimums are **iOS/iPadOS 26, tvOS 26 and macOS 26**. The inspected
`build-97` downloads require **iOS 26, tvOS 27 and macOS 27**; the lower tvOS/Mac
minimum applies to new builds. See [Requirements](REQUIREMENTS.md).

## iPhone and iPad

### Install an IPA from a computer

1. Download **`loge-iOS.ipa`** from the latest release. The same file supports
   both iPhone and iPad.
2. Set up [iloader](https://github.com/nab138/iloader), following its own device,
   Apple ID and signing instructions. It supports Mac, Windows and Linux.
3. Connect your device, sign in through the tool and import the IPA.
4. Complete any device-trust or Developer Mode steps requested by the tool.
5. Refresh/reinstall the signed app before its signature expires. Import a
   newer IPA to update loge; avoid deleting the app just to update it.

Sideloading tools depend on Apple's authentication services. If a tool cannot
sign in, consult its current documentation rather than changing your addon
setup or treating it as a loge playback failure. Revoke signing certificates
only if you understand which other apps depend on them.

### SideStore / AltStore Classic source

If you already use a working [SideStore](https://sidestore.io) or
[AltStore Classic](https://altstore.io) setup, add this URL under **Sources → +**:

```text
https://tjh.li/loge/source.json
```

Install loge from that source. It lists new builds as updates. Signature refresh
depends on your sideloading tool and its configuration, not on loge. This is an
AltStore **Classic** source, not an AltStore PAL marketplace listing.

## Apple TV

1. Download **`loge-tvOS.ipa`**, not the iOS IPA.
2. Pair the Apple TV with a tvOS-capable signing/install tool, such as
   [atvloadly](https://github.com/bitxeno/atvloadly) or
   [Sideloadly](https://sideloadly.io). Follow that tool's current host-platform
   and network-pairing instructions.
3. Install the IPA and arrange refreshes before the free seven-day signature
   expires. SideStore itself does not run on tvOS.

For a source build, [`Tools/install-tv.sh`](../Tools/install-tv.sh) uses an
atvloadly service. Set `ATVLOADLY` to your own service address; the script's
developer-machine default is not a public loge service.

## Mac

The distributed build is for **Apple silicon**.

1. Download **`loge-macOS.dmg`**, open it, and drag **loge** into **Applications**.
2. Open loge. If macOS refuses the first launch, dismiss the message.
3. Open **System Settings → Privacy & Security** and use **Open Anyway** for
   loge, then confirm the launch. Only do this for the official download you
   intended to install; do not disable Gatekeeper globally.

The app is **ad-hoc signed, not Apple-notarized**. Sparkle's Ed25519 update
verification is separate from Apple's code signing/notarization and does not
remove the first-install Gatekeeper check.

For subsequent builds, use **loge → Check for Updates…** or **Settings → About**.
You can enable automatic checks there. Both downloaded updates and the feed are
signature-verified. An old build without the updater needs one manual DMG
installation first. Mac installs do not expire after seven days.

## First run

1. Open **Settings → Addons**. Cinemeta's built-in catalogs work without setup;
   playback needs an addon that provides direct video streams.
2. Paste the provider's configured **Manifest URL** ending in `/manifest.json`
   into **Add addon**, then select **Install**. Do not paste its configuration
   webpage instead.
3. Open a title, choose an episode for a series, then select **Sources** and a
   playable stream. A previously chosen source can be reused when available.
4. Set preferred audio/subtitle languages and playback preferences in Settings.

Addon order affects provider priority. Use **Edit** on iPhone/iPad, drag rows on
Mac, or choose **Move Up / Move Down** from an addon's menu on Apple TV.

Configured manifest URLs may contain credentials. Treat the complete URL as a
secret; never include it in a public issue or screenshot of an editable field.

## Optional accounts

No account is required for basic browsing and playback. These are three
separate integrations, not three required setup steps.

### Private sync and shared setups

**Settings → Sync** connects to your own HTTPS service using a connection code.
There is no default server. Your devices can share progress, watched state,
ordered addons and preferences. Other accounts can join selected setup
categories without receiving your private viewing progress.

See [Private sync](SYNC.md) for server deployment, joining devices, expiring
invitations, conflicts and recovery keys. Save the recovery key securely.
Watch Later, custom lists and remembered stream URLs remain local.

### Trakt playback progress

1. Create your own application at [Trakt applications](https://trakt.tv/oauth/applications)
   with redirect URI `urn:ietf:wg:oauth:2.0:oob`.
2. Under **Settings → Trakt**, enter its **Client ID** and **Client Secret**,
   then select **Save**.
3. Select **Sign In**, open the displayed verification URL and enter the code.
4. Connect the same Trakt account on the other device. Pause/close playback on
   the first device, then use **Sync Now** on the second if needed.

loge imports paused progress on launch/foreground and sends scrobbles and
watched/unwatched updates. Recent completed plays clear stale unfinished
entries without overwriting newer local rewatches. Matching requires IMDb
identifiers; addon-only identifiers may not sync. It does not import your full
Trakt watched history, sync lists/settings/addons, or queue failed uploads offline.

**A connected self-hosted account pauses Trakt imports and scrobbling.** Choose
the same sync mode on the devices you want to hand off between.

### TMDB metadata

Open **Settings → TMDB → Connect TMDB** and paste the **API Read Access Token**
from your [TMDB API settings](https://www.themoviedb.org/settings/api). Use the
read access token, not the API key. loge checks it before storing it in Keychain.
On Apple TV, your phone's Apple TV Remote keyboard can enter the token.

## Troubleshooting

- **Catalogs load but no sources appear:** install a playback addon, confirm it
  covers the selected title and check provider availability. A catalog entry is
  not evidence of an available stream.
- **Unsupported source:** only direct HTTP(S) video URLs play. Torrents, magnet
  links and info hashes need a provider/service that resolves them first.
- **Buffering:** try a smaller file or lower bitrate. Recommendations depend on
  a download-speed measurement from prior playback; a fresh device may have none.
- **Different Continue Watching on two devices:** confirm the same account and
  sync mode, save progress by pausing/closing, then request sync. Check pending
  conflicts in Settings → Sync and the Trakt limits above.
- **No subtitles in PiP:** this is a current renderer limitation, not a setting.
- **App stops opening after a week:** refresh its iOS/tvOS signature through your
  sideloading tool. Deleting loge can remove local library data and is not needed
  just to refresh a signature.
- **Mac won't open:** follow the first-install Gatekeeper steps above. A signed
  update feed is not an Apple notarization ticket.

**Identify your build:** Settings → About shows the commit and date, plus a
GitHub compare link. Releases are `build-N`, with the commit count as the build
number—not a stable semantic-version release train.

If a problem remains, [open a bug report](https://github.com/timhlzwrt/loge/issues/new/choose)
with the device/OS, build commit, steps, expected result and actual result.
Redact credentials, full configured addon/stream URLs, connection codes and
recovery keys. Provider name/host is enough to identify an addon.
