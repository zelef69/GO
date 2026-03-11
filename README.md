# GO_PLAY - YouTube-Only Browser (Flutter + Android)

Single-purpose Android browser focused on YouTube, with strict domain policy, minimal controls, Android PiP support, and Brave adblock-rust integration (JNI).

## Architecture

```
lib/
  app/
    config/
    routes/
  features/
    browser/
    domain_lock/
    adblock/
    pip/
    session/
    settings/
  shared/
    constants/
    platform/
    utils/
```

## Key Components

- Browser UI: `InAppWebView` with minimal controls (back, refresh, loading, settings).
- Domain Lock:
  - `URLValidator`
  - `DomainPolicyService`
  - `NavigationInterceptor`
  - Main-frame navigation is restricted to:
    - `youtube.com`
    - `www.youtube.com`
    - `m.youtube.com`
    - `youtu.be`
- Request Policy:
  - Subresource requests are filtered by domain policy.
  - A limited allowlist of YouTube infrastructure hosts is included for playback/login compatibility.
- Adblock:
  - `FilterListLoader`
  - `AdblockService`
  - `AdblockEngineBridge`
  - Native `adblock-rust` engine through Rust JNI (`android/rust/adblock_jni`) and Android method channel (`go_play/adblock`)
  - Automatic fallback to Dart matcher when native library is not available
- PiP:
  - Flutter <-> Android platform channel (`go_play/pip`)
  - Home press during active playback triggers native `enterPictureInPictureMode()` when enabled.
- Session:
  - Cookie/WebStorage support via WebView stack.
  - Clear session/cache from Settings.

## Build & Run

1. `flutter pub get`
2. `flutter run -d android`

## Build Native adblock-rust JNI

Prerequisites:
- Rust toolchain (`rustup`, `cargo`)
- `cargo-ndk` (`cargo install cargo-ndk`)
- Android NDK (already required by Flutter Android toolchain)

Build command options:
1. Gradle task:
   - `cd android`
   - `./gradlew :app:buildRustAdblockJni` (Windows: `gradlew.bat :app:buildRustAdblockJni`)
2. Script:
   - PowerShell: `./android/scripts/build_rust_adblock.ps1`
   - Bash: `./android/scripts/build_rust_adblock.sh`

Output library path:
- `android/app/src/main/jniLibs/<abi>/libgo_play_adblock_jni.so`

## Known Limitations

1. If Rust JNI library is not built/present, app falls back to Dart adblock logic.
2. Filter list is currently a lightweight starter list (`assets/filters/basic.txt`), not full EasyList/EasyPrivacy.
3. Domain lock is strict for top-level navigation; request allowlist includes required YouTube infrastructure domains for playback/auth to work.
4. No tabs/bookmarks/history/address bar/download manager by design.
