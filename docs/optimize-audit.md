# Optimize Audit

- Last updated: 2026-04-04 22:30:26 +07:00
- Scope: product-facing optimization pass for OneTabTube on top of the current beta2 snapshot

## Audit Summary

This project's highest-risk performance and stability hotspots are concentrated in four areas:

1. Startup path in [BraveActivity.java](C:/Users/Master/Desktop/GO_PLAY/android/java/org/chromium/chrome/browser/app/BraveActivity.java)
2. YouTube bridge refresh churn in [youtube_native_tab_bridge.cc](C:/Users/Master/Desktop/GO_PLAY/browser/android/youtube_script_injector/youtube_native_tab_bridge.cc)
3. PiP / fullscreen lifecycle coordination in [youtube_script_injector_tab_helper.cc](C:/Users/Master/Desktop/GO_PLAY/browser/android/youtube_script_injector/youtube_script_injector_tab_helper.cc) and [BraveFullscreenVideoPictureInPictureController.java](C:/Users/Master/Desktop/GO_PLAY/android/java/org/chromium/chrome/browser/media/BraveFullscreenVideoPictureInPictureController.java)
4. Media notification action filtering and refresh timing in [BraveMediaSessionHelper.java](C:/Users/Master/Desktop/GO_PLAY/components/browser_ui/media/android/java/src/org/chromium/components/browser_ui/media/BraveMediaSessionHelper.java)

The first optimization patch in this round targets bridge refresh churn because it is high-impact, low-risk, and does not change the current product semantics of playback, PiP, or MIX controls.

## Risk Report

1. Critical: repeated media-session refresh work in [youtube_native_tab_bridge.cc](C:/Users/Master/Desktop/GO_PLAY/browser/android/youtube_script_injector/youtube_native_tab_bridge.cc)
Cause: the bridge recomputes reliable track capability and state multiple times per refresh, triggered by timers, DOM mutation, and video events.
Impact: avoidable DOM scans, media-session churn, extra main-thread work, and UI jank under active playback.

2. High: full-document mutation observation in [youtube_native_tab_bridge.cc](C:/Users/Master/Desktop/GO_PLAY/browser/android/youtube_script_injector/youtube_native_tab_bridge.cc)
Cause: a subtree-wide `MutationObserver` schedules refreshes for broad page changes even when the media state is unchanged.
Impact: unnecessary refresh bursts during YouTube UI churn.

3. High: startup orchestration concentration in [BraveActivity.java](C:/Users/Master/Desktop/GO_PLAY/android/java/org/chromium/chrome/browser/app/BraveActivity.java)
Cause: the activity still owns many product trims, cold-start tab reset, startup mask, and resume logic in one place.
Impact: hard-to-reason startup behavior and regression risk when adding more startup optimizations.

4. High: PiP / fullscreen race sensitivity in [youtube_script_injector_tab_helper.cc](C:/Users/Master/Desktop/GO_PLAY/browser/android/youtube_script_injector/youtube_script_injector_tab_helper.cc)
Cause: PiP relies on fullscreen-backed transitions and delayed state convergence.
Impact: black PiP, stuck fullscreen, or dropped PiP when regressions reappear.

5. Medium: media action visibility depends on page-declared capability timing
Files: [youtube_native_tab_bridge.cc](C:/Users/Master/Desktop/GO_PLAY/browser/android/youtube_script_injector/youtube_native_tab_bridge.cc), [BraveMediaSessionHelper.java](C:/Users/Master/Desktop/GO_PLAY/components/browser_ui/media/android/java/src/org/chromium/components/browser_ui/media/BraveMediaSessionHelper.java)
Impact: controls may disappear or disable when the bridge and Android surface drift temporarily.

6. Medium: one-tab cold-start reset trades correctness for repeated tab creation
File: [BraveActivity.java](C:/Users/Master/Desktop/GO_PLAY/android/java/org/chromium/chrome/browser/app/BraveActivity.java)
Impact: helps product startup today but should be revisited once page-bootstrap cost is reduced.

7. Medium: wide feature imports and initialization surface remain in the main activity
File: [BraveActivity.java](C:/Users/Master/Desktop/GO_PLAY/android/java/org/chromium/chrome/browser/app/BraveActivity.java)
Impact: increases startup cost and maintainability burden.

8. Medium: keepalive timer runs continuously whenever a `<video>` exists
File: [youtube_native_tab_bridge.cc](C:/Users/Master/Desktop/GO_PLAY/browser/android/youtube_script_injector/youtube_native_tab_bridge.cc)
Impact: background churn even when effective state has not changed.

9. Low: state and refresh code paths are duplicated conceptually between helper layers
Files: [youtube_native_tab_bridge.cc](C:/Users/Master/Desktop/GO_PLAY/browser/android/youtube_script_injector/youtube_native_tab_bridge.cc), [youtube_script_injector_tab_helper.cc](C:/Users/Master/Desktop/GO_PLAY/browser/android/youtube_script_injector/youtube_script_injector_tab_helper.cc)
Impact: slows debugging and increases risk of inconsistent fixes.

10. Low: optimization evidence is spread across many ad-hoc artifacts
Files: `artifacts/perf_evidence/*`, local screenshots/logs
Impact: harder to compare regressions quickly.

## Fix Plan

1. Reduce bridge refresh churn without changing control behavior.
2. Re-measure startup and bridge stability after that patch.
3. If startup is still product-poor, optimize post-commit page bootstrap instead of adding more masking.
4. If PiP remains sensitive under autoplay/track changes, isolate that flow next with focused lifecycle guards only.

## Code Changes In This Round

- [youtube_native_tab_bridge.cc](C:/Users/Master/Desktop/GO_PLAY/browser/android/youtube_script_injector/youtube_native_tab_bridge.cc)
  - compute media state once per refresh
  - avoid re-registering media-session actions when the action set is unchanged
  - avoid re-writing playback state when unchanged
  - avoid re-writing position state when the quantized position/rate/duration signature is unchanged
  - remove `timeupdate` from the full bridge refresh path
  - route `timeupdate` through a lightweight debounced position-only update path instead
  - keep the document-wide `MutationObserver`, but gate refreshes so only DOM mutations that touch the player/playlist/transport subtree trigger a full refresh

## Performance / UI / UX Improvements Expected

- Lower main-thread churn from repeated refreshes while YouTube UI mutates
- More stable controls under long playback sessions because the bridge stops re-announcing identical state continuously
- Reduced risk of jank during playback, PiP, and MIX transitions
- Lower repeated DOM/capability scans during normal playback because current-time updates no longer trigger a full capability refresh
- Lower refresh bursts caused by unrelated YouTube DOM churn outside the playback/playlist surface

## Code Changes In Round 5

- live ext4 [MediaSessionHelper.java](\\wsl.localhost\Ubuntu\home\master\src_ext4\components\browser_ui\media\android\java\src\org\chromium\components\browser_ui\media\MediaSessionHelper.java)
  - throttle notification position updates to at most once per second during steady playback
  - still allow immediate updates when duration, playback rate, or position jumps materially
  - reset throttle state on hide, navigation, and observer cleanup to avoid stale carry-over
- mirrored source-of-truth patch in [components-browser_ui-media-android-java-src-org-chromium-components-browser_ui-media-MediaSessionHelper.java.patch](C:/Users/Master/Desktop/GO_PLAY/patches/components-browser_ui-media-android-java-src-org-chromium-components-browser_ui-media-MediaSessionHelper.java.patch)

## Measured Result In Round 5

- Android notification churn during steady playback improved from `18` updates / `10s` to `8` updates / `10s`
- reliable MIX controls remained intact after the optimization, with live Android media session still showing `actions=382`

## Code Changes In Round 6

- [youtube_native_tab_bridge.cc](C:/Users/Master/Desktop/GO_PLAY/browser/android/youtube_script_injector/youtube_native_tab_bridge.cc)
  - reuse `lastReliablePlaylistContext` on `keepalive` refreshes for up to 5 seconds when playlist key and current video id still match
  - let keepalive capability checks read cached playlist-panel results directly instead of rebuilding candidates from `ytInitialData` on every keepalive tick

## Verification In Round 6

- build target `brave/build/android:onetabtube_android_package` passed
- installed APK hash: `8e8dd1eddff3460ba45bf6bd7ca90a68f7e297599d5cc2e33ea94db866120bcd`
- runtime smoke after install still showed OneTabTube as the active media session with `actions=382`
- quick 10-second notification counter check stayed flat, so the keepalive cache patch did not reintroduce notification churn in the sampled window

## Code Changes In Round 7

- [BraveActivity.java](C:/Users/Master/Desktop/GO_PLAY/android/java/org/chromium/chrome/browser/app/BraveActivity.java)
  - changed `resetOneTabHomeAfterColdLauncherStart(...)` to reuse an existing keep-tab on launcher cold start instead of always closing all tabs and opening a fresh homepage tab
  - trim only extra regular tabs
  - load YouTube home only when the keep-tab is not already at the default homepage

## Verification In Round 7

- build target `brave/build/android:onetabtube_android_package` passed
- installed APK hash: `8e8dd1eddff3460ba45bf6bd7ca90a68f7e297599d5cc2e33ea94db866120bcd`
- launcher cold-start evidence at [launcher_cold_start_reuse_tab_20260404_221628.txt](C:/Users/Master/Desktop/GO_PLAY/artifacts/perf_evidence/launcher_cold_start_reuse_tab_20260404_221628.txt) showed `Displayed ... +1s361ms`
- active media session after install still reported `actions=382`

## Code Changes In Round 8

- [BraveActivity.java](C:/Users/Master/Desktop/GO_PLAY/android/java/org/chromium/chrome/browser/app/BraveActivity.java)
  - dedupe redundant startup-mask show work by returning early from `maybeShowOneTabStartupMask()` when the mask is already visible and attached
  - keep startup mask semantics intact for the first actual show/hide cycle

## Verification In Round 8

- build target `brave/build/android:onetabtube_android_package` passed
- installed APK hash: `55aa62d7d7647cfd9cd4e7deb3a7c55fb0ed5700c338dfd5ffa84f433e987d53`
- corrected cold-start marker artifact at [launcher_cold_start_startup_mask_dedupe_20260404_222858.txt](C:/Users/Master/Desktop/GO_PLAY/artifacts/perf_evidence/launcher_cold_start_startup_mask_dedupe_20260404_222858.txt) now shows:
  - one `event=startup_mask show=1`
  - `Displayed ... +1s326ms`
  - one `event=startup_mask hide_reason=main_frame_commit`
- active media session after install still reported `actions=382`

## Code Changes In Round 9

- [BraveActivity.java](C:/Users/Master/Desktop/GO_PLAY/android/java/org/chromium/chrome/browser/app/BraveActivity.java)
  - keep the round-8 startup-mask dedupe
  - keep only the first-layer startup trim for OneTab mode:
    - skip default-browser prompt wiring
    - skip Sync worker eager start
    - skip misc metrics and notification-data startup processing
    - skip RateUtils startup work
    - skip first-install search-engine migration work
  - do not skip or rewrite deeper VPN / Origin / captcha / rewards bootstrap work in this round

## Verification In Round 9

- build target `brave/build/android:onetabtube_android_package` passed
- installed APK hash: `aa19f4190de69907c658263ba9e97d62e0acbf998d70b2a7e324bea655d6d646`
- launcher cold-start samples on the installed build:
  - [launcher_cold_start_startup_trim_rerun3_20260404_225857.txt](C:/Users/Master/Desktop/GO_PLAY/artifacts/perf_evidence/launcher_cold_start_startup_trim_rerun3_20260404_225857.txt) -> `Displayed ... +1s329ms`
  - [launcher_cold_start_startup_trim_revert_20260404_231743.txt](C:/Users/Master/Desktop/GO_PLAY/artifacts/perf_evidence/launcher_cold_start_startup_trim_revert_20260404_231743.txt) -> `Displayed ... +1s307ms`
  - [launcher_cold_start_startup_trim_revert_repeat_20260404_232523.txt](C:/Users/Master/Desktop/GO_PLAY/artifacts/perf_evidence/launcher_cold_start_startup_trim_revert_repeat_20260404_232523.txt) -> `Displayed ... +1s273ms`
- live media session after reinstall still reported `actions=382`

## Rejected Trial After Round 9

- Tried arming launcher cold-start home reset from `onPostCreate()` as a fallback when `maybeDispatchLaunchIntent()` did not appear to set the reset flag.
- Decision: reject for this optimization track.
- Reason:
  - it changes cold-launch page-selection semantics, not just performance
  - it risks reintroducing the same “helper restores page on startup” class of regressions the user explicitly does not want
  - the trial was built only for validation and was deliberately not installed
- Evidence:
  - uninstalled trial build log:
    - `\\wsl.localhost\Ubuntu\home\master\src_ext4\out\android_Component_arm64\codex_onetabtube_build_optimize_launcher_home_reset_fallback.log`

## Code Changes In Round 10

- [BraveActivity.java](C:/Users/Master/Desktop/GO_PLAY/android/java/org/chromium/chrome/browser/app/BraveActivity.java)
  - added `maybeScheduleOneTabDeferredEntitlementInit()`
  - moved OneTab-only `BraveVpnNativeWorker.reloadPurchasedState()` out of `finishNativeInitialization()` and into a delayed warmup
  - moved OneTab-only `BraveOriginSubscriptionPrefs.verifyPurchase(...)` out of `finishNativeInitialization()` and into the same delayed warmup
  - kept the non-OneTab path unchanged
  - kept startup navigation/home-reset behavior unchanged

## Verification In Round 10

- build target `brave/build/android:onetabtube_android_package` passed
- installed APK hash: `4f4497e3b77c26262cbf06e67f38d282fe6227ea1c4973033c9019e963c23b16`
- launcher cold-start samples on the installed build:
  - [launcher_cold_start_defer_entitlements_20260404_234413.txt](C:/Users/Master/Desktop/GO_PLAY/artifacts/perf_evidence/launcher_cold_start_defer_entitlements_20260404_234413.txt) -> `Displayed ... +1s299ms`
  - [launcher_cold_start_defer_entitlements_repeat_20260404_234438.txt](C:/Users/Master/Desktop/GO_PLAY/artifacts/perf_evidence/launcher_cold_start_defer_entitlements_repeat_20260404_234438.txt) -> `Displayed ... +1s299ms`
  - [launcher_cold_start_defer_entitlements_repeat2_20260404_234512.txt](C:/Users/Master/Desktop/GO_PLAY/artifacts/perf_evidence/launcher_cold_start_defer_entitlements_repeat2_20260404_234512.txt) -> `Displayed ... +1s274ms`
- live media session after install still reported `actions=382`
- launcher traces still showed only one startup-mask show followed by `hide_reason=main_frame_commit`
- no `launcher_cold_start_reset_home` marker was observed in the verification traces

## Interpretation After Round 10

- This round appears safe and roughly neutral-to-slightly-positive for cold start.
- It is not a breakthrough optimization by itself, but it removed non-essential entitlement work from the critical startup path without changing launch behavior.
- Keep this patch as the current startup baseline unless a later round shows a regression.

## Code Changes In Round 11 Trial

- [BraveActivity.java](C:/Users/Master/Desktop/GO_PLAY/android/java/org/chromium/chrome/browser/app/BraveActivity.java)
  - trialed a OneTab-only delayed captcha warmup path for the scheduled captcha observer and initial `maybeSolveAdaptiveCaptcha()` startup check
  - measured it against the round-10 baseline
  - removed that deferred captcha path after the measurements failed the keep bar

## Verification In Round 11 Trial

- rejected trial build log:
  - `\\wsl.localhost\Ubuntu\home\master\src_ext4\out\android_Component_arm64\codex_onetabtube_build_optimize_defer_captcha.log`
- rejected trial launcher cold-start samples:
  - [launcher_cold_start_defer_captcha_20260405_000537_run1.txt](C:/Users/Master/Desktop/GO_PLAY/artifacts/perf_evidence/launcher_cold_start_defer_captcha_20260405_000537_run1.txt) -> `Displayed ... +1s303ms`
  - [launcher_cold_start_defer_captcha_20260405_000537_run2.txt](C:/Users/Master/Desktop/GO_PLAY/artifacts/perf_evidence/launcher_cold_start_defer_captcha_20260405_000537_run2.txt) -> `Displayed ... +1s402ms`
  - [launcher_cold_start_defer_captcha_20260405_000537_run3.txt](C:/Users/Master/Desktop/GO_PLAY/artifacts/perf_evidence/launcher_cold_start_defer_captcha_20260405_000537_run3.txt) -> `Displayed ... +1s291ms`
- revert build log:
  - `\\wsl.localhost\Ubuntu\home\master\src_ext4\out\android_Component_arm64\codex_onetabtube_build_optimize_defer_captcha_revert.log`
- installed post-revert APK hash:
  - `396ded7d6784bdc0863e3939e44b45d12d16365d46ad3b0c1c591d618968ab11`
- post-revert launcher cold-start samples:
  - [launcher_cold_start_after_captcha_revert_20260405_002811_run1.txt](C:/Users/Master/Desktop/GO_PLAY/artifacts/perf_evidence/launcher_cold_start_after_captcha_revert_20260405_002811_run1.txt) -> `Displayed ... +1s308ms`
  - [launcher_cold_start_after_captcha_revert_20260405_002811_run2.txt](C:/Users/Master/Desktop/GO_PLAY/artifacts/perf_evidence/launcher_cold_start_after_captcha_revert_20260405_002811_run2.txt) -> `Displayed ... +1s277ms`

## Interpretation After Round 11 Trial

- Deferred captcha observer / initial attestation warmup is not a keep-worthy optimize path for this track.
- The rejected trial did not beat the round-10 baseline and introduced a worse outlier than the current accepted startup path.
- Treat this startup candidate as rejected unless new timing evidence later shows a specific sub-step inside the captcha block is independently expensive enough to target.

## Code Changes In Round 12

- [youtube_native_tab_bridge.cc](C:/Users/Master/Desktop/GO_PLAY/browser/android/youtube_script_injector/youtube_native_tab_bridge.cc)
  - added `currentPageUrl()`
  - added `shouldObserveBridgeLifecycle()`
  - added `shouldResolveReliablePlaylistContext(video)`
  - stopped creating the document-wide lifecycle observer until watch/player/playlist context is real
  - stopped rebuilding reliable playlist context on non-watch/home contexts
  - changed bootstrap from immediate `observeLifecycle()/bindVideoEvents()/refreshMediaSession()` to deferred `scheduleRefresh('bootstrap')`

## Verification In Round 12

- build target `brave/build/android:onetabtube_android_package` passed
- installed APK hash: `0481c08394a26429bd2ea8d5712a76d8b2db02c0bd32f82baa09bc9b65f0c7a4`
- fresh home-page baseline on the pre-round build:
  - [page_home_metrics_before_20260405_1.txt](C:/Users/Master/Desktop/GO_PLAY/artifacts/perf_evidence/page_home_metrics_before_20260405_1.txt) -> `domInteractive 1809.9ms`, `loadEventEnd 1932.9ms`
- final round-12 home-page samples on the installed build:
  - [page_home_metrics_after_20260405_4.txt](C:/Users/Master/Desktop/GO_PLAY/artifacts/perf_evidence/page_home_metrics_after_20260405_4.txt) -> `domInteractive 1116.7ms`, `loadEventEnd 1286.8ms`
  - [page_home_metrics_after_20260405_5.txt](C:/Users/Master/Desktop/GO_PLAY/artifacts/perf_evidence/page_home_metrics_after_20260405_5.txt) -> `domInteractive 1142.7ms`, `loadEventEnd 1224.1ms`

## Interpretation After Round 12

- Round 12 is a keep-worthy page-bootstrap optimization.
- The improvement signal is strongest on `domInteractive/loadEventEnd`; `firstContentfulPaint` stayed noisy on the live home surface.
- This round narrows bridge churn on non-watch contexts without touching control dispatch semantics.

## Code Changes In Round 13

- [youtube_script_injector_tab_helper.cc](C:/Users/Master/Desktop/GO_PLAY/browser/android/youtube_script_injector/youtube_script_injector_tab_helper.cc)
  - kept the native bridge injection on all YouTube pages
  - gated `kYoutubePlaybackStability` so it injects only on real watch pages
  - gated `kYoutubeBackgroundPlayback` so it injects only on real watch pages
  - gated `kYoutubePictureInPictureSupport` so it injects only on real watch pages

## Verification In Round 13

- build target `brave/build/android:onetabtube_android_package` passed
- installed APK hash: `220A0C0E46B4E126B3F5FBDF163CACE3A987CFEB6031C952DF21A534A969D029`
- runtime flag verification:
  - [page_injection_flags_round13_20260405_1.txt](C:/Users/Master/Desktop/GO_PLAY/artifacts/perf_evidence/page_injection_flags_round13_20260405_1.txt)
  - home page -> `playbackGuardInstalled: false`, `nativeBridgeInstalled: true`
  - watch page -> `playbackGuardInstalled: true`, `nativeBridgeInstalled: true`
- watch-page baseline before round 13:
  - [page_watch_metrics_before_20260405_2.txt](C:/Users/Master/Desktop/GO_PLAY/artifacts/perf_evidence/page_watch_metrics_before_20260405_2.txt) -> `domInteractive 1805.1ms`, `loadEventEnd 3071.8ms`
- watch-page sample after round 13:
  - [page_watch_metrics_after_20260405_3.txt](C:/Users/Master/Desktop/GO_PLAY/artifacts/perf_evidence/page_watch_metrics_after_20260405_3.txt) -> `domInteractive 1913.1ms`, `loadEventEnd 2837.7ms`

## Interpretation After Round 13

- Round 13 is a keep-worthy structural cleanup because it removes watch-only helper installation from non-watch pages while preserving the native bridge everywhere.
- The verification is strongest on script-install state, not on a hard timing win yet.
- Watch-page timing is still too noisy and sparse to claim a reliable watch-page speedup from round 13 alone.
- The next optimize round should attribute watch-page helper cost more directly before trimming another watch-only script block.

## Round 13 Recovery Decision

- After round 13 was installed, the user reported a runtime regression: PiP/notification controls were no longer usable.
- Live recovery investigation showed:
  - helper injection had changed in [youtube_script_injector_tab_helper.cc](C:/Users/Master/Desktop/GO_PLAY/browser/android/youtube_script_injector/youtube_script_injector_tab_helper.cc)
  - media-session ownership and control behavior needed to be restored before continuing optimization
- Decision:
  - reject round 13 as the active installed build for now
  - revert the round-13 helper-injection gate
  - return the device to the earlier round-12 build hash `0481C08394A26429BD2EA8D5712A76D8B2DB02C0BD32F82BAA09BC9B65F0C7A4`
- Recovery verification:
  - recovery build log:
    - `\\wsl.localhost\Ubuntu\home\master\src_ext4\out\android_Component_arm64\codex_onetabtube_build_revert_round13_control_regression.log`
  - after recovery, `dumpsys media_session` again showed:
    - `Media button session is com.onetabtube.browser_default/OneTabTube - Debug`
  - `play/pause` dispatch through `cmd media_session` changed the live page state again


## Regression Check

- Build must still pass for `brave/build/android:onetabtube_android_package`
- Play/pause/seek/next/previous behavior in currently working MIX flows must remain unchanged
- Notification and PiP controls must still appear when the bridge resolves reliable track capability

## Remaining Risks

- This patch does not solve all startup cost; it only removes avoidable churn in the bridge
- PiP/fullscreen races remain a separate subsystem risk
- The current activity-level startup simplifications are still local product decisions that may need deeper cleanup later
- The full-document mutation observer and keepalive cadence are still broader than ideal and remain the next likely optimization target inside the bridge
- Live log inspection after round 3 still shows repeated SystemUI/notification updates while playing, which points to a likely follow-up optimization target on the Android notification/media surface after bridge churn is narrowed enough
- After rounds 7 and 8, the next likely high-value optimization target is post-commit homepage bootstrap on launcher cold start rather than more startup-mask tuning
- After round 9, the direction is narrower: keep startup-navigation behavior fixed and look only for non-behavioral deferral/lazy-init wins inside `finishNativeInitialization()` and `onResumeWithNative()`

## Code Changes In Round 14

- [youtube_script_injector_tab_helper.cc](C:/Users/Master/Desktop/GO_PLAY/browser/android/youtube_script_injector/youtube_script_injector_tab_helper.cc)
  - re-enabled injection of `kYoutubeTransitionOptimization`
  - enabled only the prefetch/preconnect/media-warm path with:
    - `ENABLE_TRANSITION_WARM=true`
    - `ENABLE_TRANSITION_PAGE_REVEAL=false`
  - gated playback/presentation helper exports behind the page-reveal flag so the old stable PiP/control globals stay in charge
  - gated the warm-script `click` interception behind the page-reveal flag so prefetch-only mode falls back to normal YouTube page loading instead of forcing helper-driven navigation
  - limited automatic warm bootstrap to real watch pages while still allowing link-hint prefetch from user interaction

## Verification In Round 14

- pre-change baseline on the restored-control build:
  - [20260405T110517_R9TRC00GA2E/summary.json](C:/Users/Master/Desktop/GO_PLAY/artifacts/perf_evidence/transition/20260405T110517_R9TRC00GA2E/summary.json)
  - `next_to_first_frame_ms=5886`
  - `black_screen_duration_ms=4753`
- rejected first installed attempt with click interception still active:
  - build log:
    - `\\wsl.localhost\Ubuntu\home\master\src_ext4\out\android_Component_arm64\codex_onetabtube_build_warm_prefetch_only.log`
  - [20260405T111046_R9TRC00GA2E/summary.json](C:/Users/Master/Desktop/GO_PLAY/artifacts/perf_evidence/transition/20260405T111046_R9TRC00GA2E/summary.json)
  - `next_to_first_frame_ms=8613`
  - `black_screen_duration_ms=7162`
- corrected prefetch-only build:
  - build log:
    - `\\wsl.localhost\Ubuntu\home\master\src_ext4\out\android_Component_arm64\codex_onetabtube_build_warm_prefetch_only_rerun2.log`
  - installed APK hash:
    - `953fc6600012d9dd0601485d04f7ab6fbb5dc83ddb4f2538127453ced7a78a4f`
  - first corrected sample:
    - [20260405T111714_R9TRC00GA2E/summary.json](C:/Users/Master/Desktop/GO_PLAY/artifacts/perf_evidence/transition/20260405T111714_R9TRC00GA2E/summary.json)
    - `next_to_first_frame_ms=3148`
    - `black_screen_duration_ms=2240`
  - repeat corrected sample:
    - [20260405T111845_R9TRC00GA2E/summary.json](C:/Users/Master/Desktop/GO_PLAY/artifacts/perf_evidence/transition/20260405T111845_R9TRC00GA2E/summary.json)
    - `next_to_first_frame_ms=5925`
    - `black_screen_duration_ms=4977`

## Interpretation After Round 14

- The prefetch-only warm path is now fallback-safe:
  - it no longer intercepts clicks
  - if warm cannot help, the page uses normal YouTube navigation
- One corrected sample showed a large improvement, but the repeat sample drifted back near baseline.
- Conclusion:
  - keep this as a safe experiment
  - do not yet claim a significant page-load improvement
  - the next optimization step should reduce warm-target variance before expanding scope
