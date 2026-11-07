# Platform requirements

[Back to loge](../README.md)

## Runtime minimums

The current source targets **iOS 26.0, iPadOS 26.0, tvOS 26.0 and macOS 26.0**.
iPhone and iPad use the same iOS target and `.ipa`; Mac is a native macOS app,
not a Mac Catalyst build. The distributed Mac build is for **Apple silicon**;
Intel Mac support is not verified or advertised.

There is no Android, Windows, Linux or visionOS app target. A sideloading tool
running on Windows/Linux does not make those platforms loge clients.

These values are defined in two places which must stay aligned:

- [`project.yml`](../project.yml), under `options.deploymentTarget`: app and UI-test targets.
- [`Core/Package.swift`](../Core/Package.swift), under `platforms`: the shared Swift package.

[`Tools/sidestore-source.py`](../Tools/sidestore-source.py) also advertises the
iOS minimum as `minOSVersion`. Sparkle derives the Mac minimum from the built app
when generating its signed update feed; do not hand-edit that feed.

The downloaded **`build-97`** release requires **iOS/iPadOS 26.0, tvOS 27.0 and
macOS 27.0**, verified from the actual IPA/DMG app plists, not just the README.
Earlier source used **tvOS 27.0 and macOS 27.0** deployment targets.
Lowering the source target does not retroactively change those downloads. The
OS 26 minimum applies to new builds containing this change.

## Why OS 26, rather than 27 or an older release?

The app uses SwiftUI's Liquid Glass APIs without older-OS fallbacks:

- [`glassEffect(_:in:)`](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:))
  is introduced in iOS, iPadOS, tvOS and macOS **26.0**.
- [`GlassEffectContainer`](https://developer.apple.com/documentation/swiftui/glasseffectcontainer)
  and the glass button styles are used in playback and source controls.
- [`backgroundExtensionEffect()`](https://developer.apple.com/documentation/swiftui/view/backgroundextensioneffect())
  is introduced in **26.0** and used behind featured artwork and title details.

The installed SDK's SwiftUI / SwiftUICore interfaces confirm these availability
annotations. Building the entire app at target 26.0 catches any unguarded newer
API use; no app-source compatibility changes were needed.

The player does not force OS 27 either. The
[vendored MPVKit package](../Vendor/MPVKit/Package.swift) declares **iOS/tvOS 15**
and **macOS 12**. Inspection of the patched Libmpv Mach-O object build commands
confirms those same minimums for its arm64 device/Mac slices. The app's SwiftUI
API floor, not mpv's package floor, sets loge's minimum.

Supporting earlier OS releases would require real availability fallbacks and
testing; changing only the deployment numbers would not be sufficient.

## Build tools are a separate requirement

- **Verified build toolchain:** **Xcode 27.2**, build `27B52`, and XcodeGen **2.46.0**.
- **Verified compiler:** Apple Swift **6.4.2**; app source uses Swift **6** language mode.
- **Package manifest:** Swift tools **6.0** for LogeCore, not a claim that every
  Swift 6.0 / Xcode 16 toolchain can build the app's OS 26 SwiftUI APIs.
- **Project generator:** [XcodeGen](https://github.com/yonaskolb/XcodeGen).

An SDK version does not set an app's runtime minimum. See Apple's
[Xcode support matrix](https://developer.apple.com/support/xcode/) for the macOS
version needed to run a particular Xcode release. Xcode 26 is not installed in
the verification environment, so it is not advertised as a tested toolchain.
The source's OS 26 APIs require corresponding SDKs; a hard Xcode 27 minimum
has not been established and should not be inferred from the CI runner label.

## Verification record — 7 November 2026

- iOS Simulator build: **passed**, deployment target **26.0**.
- tvOS Simulator build: **passed**, deployment target **26.0**.
- Native macOS arm64 build: **passed**, deployment target **26.0**.
- Device-target Release builds for iOS/tvOS and a generic Mac Release build:
  **passed** at **26.0**, with code signing disabled for this build check.
- The local generic Mac Release binary contains **arm64 and x86_64** slices;
  that establishes compilation, not Intel hardware/runtime verification.
- All three used `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` with Xcode 27.2.
- LogeCore: **247 tests passed**; opt-in live-service checks were skipped.
- Release-publishing regressions: **12 tests passed**.
- Generated app plists report `MinimumOSVersion = 26.0` on iOS/tvOS and
  `LSMinimumSystemVersion = 26.0` on macOS.

**Scope:** compilation/API-availability checks establish the deployment floor;
they are not a runtime certification on OS 26. The installed simulators and
host run **27.2**. Minimum-version simulator smoke tests remain
[verification work](../ROADMAP.md#next-verification-first) when runtimes are available.
Hardware output is outside the [planned testing scope](../ROADMAP.md#a-note-from-the-maintainer).
Xcode emits destination-selection diagnostics; no Swift compiler warnings
were observed in these builds.

The downloaded **`build-97` Mac DMG** was also inspected: its app plist and
Mach-O load command both require **macOS 27.0**, and its executable contains
only **arm64**. Its published Sparkle feed likewise advertises **27.0**.
That is why the existing download is described as Apple-silicon-only despite
the broader architectures in the locally built source binary.

To repeat the checks, use the commands in [Contributing](../CONTRIBUTING.md).
