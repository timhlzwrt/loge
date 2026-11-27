# Install loge

[Back to loge](../README.md)

loge isn't in the App Store. You install it yourself with a free Apple ID, which takes about
15 minutes the first time. You need **iOS/iPadOS 26, tvOS 26 or macOS 26** (Apple silicon).

Only download loge from [GitHub Releases](https://github.com/timhlzwrt/loge/releases) or the
SideStore source below.

- [iPhone and iPad with SideStore](#iphone-and-ipad-with-sidestore) (recommended)
- [iPhone and iPad with iloader only](#iphone-and-ipad-with-iloader-only)
- [Apple TV](#apple-tv)
- [Mac](#mac)
- [First run](#first-run)
- [Something's wrong](#somethings-wrong)

## iPhone and iPad with SideStore

SideStore is an app store on your phone that installs apps signed with your own Apple ID. It
renews them by itself and offers each new loge build as an update. You need a computer once,
to install SideStore.

### 1. Prepare the iPhone or iPad

1. Make sure it has a passcode.
2. Open **Settings → Privacy & Security → Developer Mode**, turn it on and let it restart.
3. Install **LocalDevVPN** from the App Store. SideStore uses it to install and renew apps on
   the device by itself; it doesn't route your traffic anywhere.

### 2. Install SideStore from a computer

1. On your Mac, Windows or Linux computer, download and open
   [iloader](https://github.com/nab138/iloader). On Windows, install iTunes first; on Linux,
   install `usbmuxd`.
2. Connect the iPhone or iPad with a cable, tap **Trust** and enter its passcode.
3. In iloader, sign in with your Apple ID. It doesn't have to be the one on the device; many
   people use a separate free Apple ID for signing. The email is case-sensitive.
4. Select your device, then **Install SideStore (Stable)**.
5. On the device, open **Settings → General → VPN & Device Management**, choose your Apple ID
   under Developer App and trust it.

### 3. Install loge

1. Open **LocalDevVPN** and tap **Connect** (allow the VPN configuration the first time).
2. Open **SideStore** and sign in with the same Apple ID.
3. Go to **Sources**, tap **+** and add:

   ```text
   https://tjh.li/loge/source.json
   ```

4. Open the loge source and install loge.

That's it. Continue with [First run](#first-run).

### Keeping it working

- Free Apple ID apps run for 7 days. SideStore renews them in the background while
  LocalDevVPN is connected; open SideStore now and then so it can.
- If loge stops opening, open LocalDevVPN, then SideStore → **My Apps**, and tap the days
  counter next to loge to renew it. Don't delete loge: that deletes its library on the device.
- New builds appear as updates in **My Apps**.
- A free Apple ID allows 3 sideloaded apps at once, SideStore included.
- After an iOS update or reset SideStore may lose its pairing file; iloader places it again
  (see [SideStore's guide](https://docs.sidestore.io)).

## iPhone and iPad with iloader only

Without SideStore you need the computer every 7 days, and you install updates by hand.

1. Do steps 1.1 and 1.2 and steps 2.1–2.3 above.
2. Download **`loge-iOS.ipa`** from the
   [latest release](https://github.com/timhlzwrt/loge/releases/latest) (one file for iPhone
   and iPad).
3. In iloader, select your device and import the IPA.
4. Trust your Apple ID as in step 2.5.

Before the 7 days are up, or when there's a new build, import the latest IPA again the same
way. Installing over the existing app keeps your library.

## Apple TV

SideStore and iloader don't run on Apple TV. Use
[atvloadly](https://github.com/bitxeno/atvloadly) (runs on a home server or NAS and renews
the app for you) or [Sideloadly](https://sideloadly.io) (Mac or Windows, renew by hand every
7 days):

1. Download **`loge-tvOS.ipa`** from the
   [latest release](https://github.com/timhlzwrt/loge/releases/latest), not the iOS file.
2. Pair the Apple TV with the tool, following its instructions.
3. Install the IPA with your Apple ID.

## Mac

1. Download **`loge-macOS.dmg`** from the
   [latest release](https://github.com/timhlzwrt/loge/releases/latest), open it and drag
   loge into Applications.
2. Open loge. macOS refuses the first time because loge isn't notarized by Apple: close the
   message, open **System Settings → Privacy & Security** and choose **Open Anyway**.

The Mac app doesn't expire. It updates itself: **loge → Check for Updates…**, or turn on
automatic checks in Settings (⌘,).

## First run

loge shows catalogs from Cinemeta out of the box. To play anything it needs a stream addon:

1. Copy your addon's **manifest URL**, the link ending in `/manifest.json` (not its
   configuration page).
2. In loge, tap **Add Addon** on Home, or open Settings and tap the addons value in
   "takes sources from …".
3. Paste the URL and choose **Install**.

Open a title and choose **Play**, or **Sources** to pick a file yourself.

If you already use loge on another device, **Share Setup** there (Settings on iPhone, iPad and
Mac) and **Import Setup** here copies your addons and preferences in one go.

Optional:

- **TMDB** adds cast, crew and recommendations. In Settings, tap TMDB and paste the
  **API Read Access Token** (not the API key) from
  [your TMDB API settings](https://www.themoviedb.org/settings/api). On Apple TV you can type
  it with your phone's Apple TV Remote keyboard.
- **Sync** keeps progress, Watch Later, addons and preferences the same on your devices. It
  needs a server you run yourself; see [Private sync](SYNC.md).

Your manifest URL can contain your addon's settings and keys. Treat it like a password: don't
post it in issues or screenshots.

## Something's wrong

- **loge won't open after a week:** renew it (see
  [Keeping it working](#keeping-it-working)). Don't delete it.
- **SideStore can't install or renew:** check LocalDevVPN is connected and you're on Wi-Fi.
  Problems with SideStore or iloader themselves belong with
  [SideStore](https://docs.sidestore.io), not loge.
- **No sources for a title:** your stream addon has nothing for it, or none is installed.
  Catalogs list titles whether or not anything can play them.
- **A source won't play:** loge plays direct video links. Torrents need an addon or debrid
  service that turns them into links.
- **Buffering:** pick a smaller file, or set a maximum bitrate in Settings.

**Your build number** is in Settings → About (tap the large "loge"). Builds are numbered
`build-N` on GitHub.

Still stuck? Ask in [Discussions](https://github.com/timhlzwrt/loge/discussions). Found a
bug? [Report it](https://github.com/timhlzwrt/loge/issues/new/choose) with your device, OS,
build and what happened. Name your addon (or its host), never its full URL.
