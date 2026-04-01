# OneTabTube

OneTabTube is a Brave-derived Android browser fork that constrains the product surface to a one-tab, YouTube-only browsing shell while retaining Brave's normal browser engine and Shields/adblock wiring.

This fork does not claim permanent or perfect YouTube ad blocking. It retains Brave's adblocking stack and aims to preserve Brave Shields behavior for YouTube, but actual effectiveness can vary as upstream rules and YouTube behavior evolve.

## Current Product Behavior

- Default home target is `https://www.youtube.com/`
- Navigation is filtered through a centralized allowlist policy
- Non-allowlisted URLs are redirected back to YouTube home
- New-tab, incognito, and tab-switcher paths are blocked or collapsed into the existing tab
- Major Brave product surfaces such as Rewards, Wallet, VPN, News, Leo, sync/account upsell, bookmarks/history/downloads menu entry points, and widget incognito entry are hidden in the main product flow
- Brave Shields code paths remain wired through the normal Brave Android stack

## Repository Layout Requirement

Brave's build scripts expect a full Brave checkout layout, not a standalone folder on the desktop.

Expected layout:

```text
C:\Users\Master\src\
  brave\        <- this repository
  chromium src\ <- synced by Brave tooling
```

The current workspace is at `C:\Users\Master\Desktop\GO_PLAY`, so build scripts fail before GN generation unless the repo is moved or linked into the expected checkout layout and Chromium dependencies are synced.

## Setup

1. Place this repository at `C:\Users\Master\src\brave` or create an equivalent junction/symlink.
1. Install Node dependencies:

```powershell
npm install
```

1. Initialize the Brave/Chromium checkout:

```powershell
npm run init -- --target_os=android --target_arch=arm64
```

1. If the checkout is already initialized, sync it:

```powershell
npm run sync -- --target_os=android --target_arch=arm64
```

## Build Debug APK

Equivalent Brave build command used for this fork:

```powershell
npm run build -- --target_os=android --target_arch=arm64 --target=chrome_public_apk
```

With the current OneTabTube naming patch, the upstream-produced APK basename is:

```text
C:\Users\Master\src\out\android_Component_arm64\apks\OneTabTube.apk
```

The Brave wrapper then copies that into the expected packaged output artifact:

```text
C:\Users\Master\src\out\android_Component_arm64\apks\OneTabTubeMonoarm64.apk
```

## Install

After a successful build:

```powershell
adb install -r C:\Users\Master\src\out\android_Component_arm64\apks\OneTabTubeMonoarm64.apk
```

If you need to inspect the upstream Chromium-side APK before Brave's copy/sign wrapper runs, check:

```text
C:\Users\Master\src\out\android_Component_arm64\apks\OneTabTube.apk
```

## Manual Smoke Test

1. Launch the app and confirm it opens to YouTube home.
2. Open a `youtube.com/watch?v=...` link and confirm it stays in the same tab.
3. Open a `youtu.be/...` link and confirm it resolves in-app.
4. Open a non-allowlisted URL such as `https://google.com` and confirm redirect to YouTube home.
5. Confirm there is no usable new-tab, incognito, or tab-switcher entry point in the main UI.
6. Confirm Shields still appears and normal page navigation still uses Brave browser internals rather than WebView glue code.

## Known Limitations

- This implementation is currently a restricted product mode layered onto Brave Android Java/resources, not a fully isolated GN flavor/target.
- Android manifest package identity is separated to `com.onetabtube.browser*`, and the copied output artifact name is now `OneTabTube*`.
- The current workspace does not contain the full Brave/Chromium checkout layout required to finish a local APK build.
- Allowlist coverage includes YouTube hosts plus limited Google account/consent hosts, but some future auth or embed flows may require further tuning.
