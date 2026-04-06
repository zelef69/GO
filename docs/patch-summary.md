# Patch Summary

## BETA+3 Prefix Product(+1)

This repo snapshot is aligned to the latest device-verified GO_PLAY APK baseline that is currently installed on the test device.

Current validated APK:

- `/home/master/src_ext4/out/android_Component_arm64/apks/OneTabTube.apk`
- SHA-256 `8E49725AFE44405792321664A9468A80A96E532D67CE4A9415D7FC2663D392B2`

What was synced into repo for this baseline:

- the live OneTab auth/payment Java sources and resources used by the latest APK
- the Firebase/Thunder payment backend sources and rules used by the latest APK
- the updated handoff snapshot files
- a repo-side mirror of the direct build-tree manifest recovery patch at
  [patches/chrome-android-java-AndroidManifest.xml.onetab-auth-recovery.patch](C:/Users/Master/Desktop/GO_PLAY/patches/chrome-android-java-AndroidManifest.xml.onetab-auth-recovery.patch)

Why the extra manifest recovery patch mirror exists:

- the latest APK was recovered from the real `src_ext4` build tree after the packaged manifest dropped the OneTab auth/payment activities
- this repo does not carry `chrome/android/java/AndroidManifest.xml` directly in the Windows workspace
- the mirror patch keeps the exact recovery delta used by the latest APK inside the repo so future resume/push work does not have to rediscover it from the device again

## fix onetab+pip+outwatchpage

This repo state matches the current OneTabTube debug APK that was last rebuilt and installed for the OneTab/PiP/watch-page baseline.

What this integrated fix set covers:

- OneTab enforcement hardened so restored tab state is pruned back to a single regular tab after tab state initialization
- top tab switcher affordance removed in OneTab mode so landscape no longer shows a live tab-count button
- PiP restore path kept stable
- PiP expand now returns to the YouTube watch page instead of crashing or falling back into fullscreen

Current validated APK:

- `/home/master/src_ext4/out/android_Component_arm64/apks/OneTabTube.apk`
- SHA-256 `F22D0767A0241591974CF48135CF4A6A571CC65AF7D08F9662CBDE52DEA16A0F`

## Scope Of This Pass

This pass is the Brave-level player UX follow-up. It consolidates prior playback, autoplay, playability, PiP, and evidence work into a clearer player-focused package instead of leaving the repo documented mainly as adblock work plus scattered perf notes.

## April 2, 2026 PiP Restore Follow-Up

This follow-up specifically restores the full Brave-derived PiP path for OneTabTube after the earlier `rerun200` device fix had hard-disabled it.

Main product-level change:

- remove the OneTabTube-only PiP hard-disable gates instead of replacing the underlying Brave PiP implementation

Files changed for that restore:

- `android/java/org/chromium/chrome/browser/app/BraveActivity.java`
- `android/java/org/chromium/chrome/browser/toolbar/top/BraveToolbarLayoutImpl.java`

What changed in practice:

- `BraveActivity` now allows the normal PiP request path, user-leave PiP entry path, and PiP support checks to run for OneTabTube again
- the OneTabTube debug PiP action now routes into the normal system PiP request path instead of clearing PiP state
- `BraveToolbarLayoutImpl` no longer force-hides the PiP button purely because OneTabTube mode is enabled

Why this approach was chosen:

- the full PiP, playback continuity, and restore machinery was still present in the Brave base
- only a thin product gate had been suppressing it
- lifting that gate is safer and faster than forking a custom PiP implementation

Device-backed outcome from `rerun201`:

- the PiP button is visible again on the YouTube watch page
- tapping the PiP button and pressing Home enters pinned PiP mode
- playback continues while pinned
- screen-off preserve / restore markers fire during the pinned session

Remaining risk:

- Samsung launcher handoff after power / unlock is still noisy, so one cleaner foreground-return validation pass is still worth doing even though PiP entry and continuity are working again

## April 2, 2026 PiP Direct-Tap Wiring Fix

Problem this follow-up fixed:

- the earlier PiP restore brought the feature back, but the visible toolbar button still depended on the old fullscreen/JS timing path
- that meant the prior `rerun201` evidence proved "PiP can still happen" and "Home-assisted entry works" but did not honestly prove "tap the button and PiP enters immediately"

Files changed:

- `android/java/org/chromium/chrome/browser/app/BraveActivity.java`
- `android/java/org/chromium/chrome/browser/toolbar/top/BraveToolbarLayoutImpl.java`

What changed:

- added an Android-side immediate PiP request path in `BraveActivity`
- kept the existing Brave PiP machinery instead of inventing a separate OneTabTube flow
- changed the toolbar PiP button to call the immediate PiP path directly
- kept one delayed retry so the button still has a second chance if the first request lands slightly before the player is fully ready

Why this was the right change:

- it keeps the implementation inside the existing Brave activity/lifecycle architecture
- it fixes the actual user-facing behavior instead of only making the debug or fullscreen callback path look healthy
- it is smaller and safer than rewriting PiP around the YouTube injector or inventing a custom player shell path

Evidence:

- build passed as `rerun204`
  - `/home/master/src_ext4/out/android_Component_arm64/codex_onetabtube_build_repro_from_baseline_rerun204.log`
- direct tap evidence on `R9TRC00GA2E`
  - `tmp_toolbar_pip_logcat.txt`
  - `tmp_toolbar_pip_dumpsys.txt`
  - `window_dump_pip_verify.xml`
- key signals now observed after the real button tap:
  - `event=pip_enter_request:toolbar_button`
  - `event=pip_immediate_request:toolbar_button:entered=true`
  - `event=pip_mode_changed:true`
  - `mode=pinned`
  - `mLastReportedPictureInPictureMode=true`

## April 2, 2026 Brave-Upstream PiP Alignment

Why this pass happened:

- the `rerun204` immediate-entry workaround proved that the user-facing tap path could work
- but the user explicitly asked for a more stable fix based on the real Brave GitHub code instead of a local guess

Files changed:

- `android/java/org/chromium/chrome/browser/youtube_script_injector/BraveYouTubeScriptInjectorNativeHelper.java`
- `android/java/org/chromium/chrome/browser/toolbar/top/BraveToolbarLayoutImpl.java`
- `android/java/org/chromium/chrome/browser/app/BraveActivity.java`

Brave sources used directly:

- `https://github.com/brave/brave-core/blob/master/android/java/org/chromium/chrome/browser/youtube_script_injector/BraveYouTubeScriptInjectorNativeHelper.java`
- `https://github.com/brave/brave-core/blob/master/android/java/org/chromium/chrome/browser/toolbar/top/BraveToolbarLayoutImpl.java`
- `https://github.com/brave/brave-core/blob/master/android/java/org/chromium/chrome/browser/app/BraveActivity.java`
- `https://github.com/brave/brave-core/blob/master/browser/android/youtube_script_injector/youtube_script_injector_tab_helper.cc`

What changed:

- restored the helper-side Brave behavior where the native callback calls `enterPictureInPictureMode(...)` directly
- restored the toolbar-side Brave behavior where the PiP button only triggers `setFullscreen(...)`
- removed the now-unused local immediate-entry helper from `BraveActivity`

What this proved:

- the Brave-upstream entry wiring still works in OneTabTube on real hardware
- direct toolbar PiP entry still succeeds with the upstream path
- the pinned task survives in recents across a power/off -> wake cycle

What this did not solve yet:

- launcher relaunch after wake still spawned a new fullscreen task instead of reusing the pinned task
- so the remaining problem is now clearly the post-wake relaunch / task-reuse path, not the PiP entry path itself

Follow-up reality check after more reruns:

- repeated Samsung validation showed that the upstream-aligned path is still flaky in this shell
- that means the next patch should not abandon the Brave baseline, but it probably does need one narrow OneTabTube-specific stability layer on top

## Modules Touched

### `browser/android/youtube_script_injector/youtube_script_injector_tab_helper.cc`

Main responsibilities improved across the recent player UX work:

- next-video warmup through `prefetch`, `preconnect`, and media warm paths
- direct canonical `next_fast_nav` handoff when a next target is prepared
- playability self-heal for blocked or broken watch pages
- audible playback enforcement so video playback and audible playback are not treated as the same condition
- foreground, focus, and `resume` recovery hooks through `resumeWarmPipeline(...)`

Why this helps smoothness:

- reduces avoidable watch-page handoff delay
- makes autoplay and resume behavior more deterministic
- avoids leaving the user stuck on a playability overlay or muted playback state

Main risk:

- aggressive warm or recovery logic can make evidence look good while hurting real transitions if it is not kept tightly scoped

### `android/java/org/chromium/chrome/browser/app/BraveActivity.java`

Recent work here keeps Android-side state visible and debuggable:

- lifecycle markers from `onResume`, `onPause`, and `onStop`
- PiP state markers from `onPictureInPictureModeChanged(...)`
- application foreground/background markers
- DevTools server startup logging for evidence correlation

Why this helps smoothness:

- lifecycle and PiP bugs usually look like "random playback loss" unless the Android shell is instrumented
- these markers let the runner separate an app-shell failure from a page-level failure

Main risk:

- Android lifecycle callbacks can fire in a healthy order while the page or renderer is still unstable, so these markers help but are not the whole truth by themselves
- proactive PiP fullscreen repair can become self-inflicted churn if it keeps forcing fullscreen after the player is already effectively stable

### `tools/perf_evidence/run_perf_evidence.py`

This runner is now the main performance and continuity evidence entry point.

Key capabilities:

- `baseline` and `transition` measurement for watch-page handoff
- `background`, `lifecycle`, `lockscreen`, and `pip` continuity scenarios
- screenshot capture
- `dumpsys activity` and `dumpsys media_session` artifacts
- filtered app-event extraction into `app_events.log`
- machine-readable `summary.json`

Important fixes in this pass:

- logcat capture is now started before app launch so run artifacts actually contain the early lifecycle markers
- lifecycle verdicts now read from the streamed `logcat_full.txt` artifact instead of a narrow `adb logcat -d -t 200` snapshot, which previously caused false lifecycle failures even when `activity_pause` and `activity_resume` were present in the saved log
- the runner now waits for `event=devtools_server enabled=true` before the initial forward and refreshes the forwarded socket before CDP reconnects, which closed the attach failure that had blocked end-to-end lifecycle artifacts
- mid-scenario CDP reconnect now has a lightweight path that refreshes the forwarded socket without automatically force-stopping and relaunching the app, which matters for `pip_lockscreen`

Why this helps smoothness work:

- it makes lifecycle continuity failures explainable instead of speculative
- it reduces false positives and false negatives in the evidence pipeline

Main risk:

- DevTools / CDP discovery can still churn during some reruns, but the attach path is now much more resilient because it no longer trusts a stale forwarded socket across reconnects

### `tools/perf_evidence/*.ps1` And `export_summary.py`

New or prompt-aligned helpers now include:

- `run_player_transition_test.ps1`
- `run_background_play_test.ps1`
- `run_lifecycle_test.ps1`
- `run_lockscreen_test.ps1`
- `run_pip_test.ps1`
- `run_pip_lockscreen_test.ps1`
- `collect_logs.ps1`
- `export_summary.py`

Why this helps:

- gives QA and follow-up debugging a small set of repeatable entry points
- makes manual log capture possible even when CDP automation is unstable

## Brave-Derived Behavior Preserved

This pass does not replace the browser with a custom player shell.

Still preserved:

- Brave Android activity and tab model
- OneTabYouTube URL gating
- Brave-derived watch-page path
- Brave Shields and adblock stack
- Android media-session and PiP architecture

## Evidence-Backed Outcome

As of March 30, 2026:

- background playback: passed
  - `artifacts/perf_evidence/background/20260330T051937_R9TRC00GA2E`
- lockscreen playback: passed
  - `artifacts/perf_evidence/lockscreen/20260330T052216_R9TRC00GA2E`
- PiP: passed
  - `artifacts/perf_evidence/pip/20260330T053107_R9TRC00GA2E`
- best honest transition result: improved but still failing target
  - `artifacts/perf_evidence/transition/20260330T163209_R9TRC00GA2E`
  - `next_to_first_frame_ms = 3500`
  - `navigation_to_first_frame_ms = 2747`
  - `black_screen_duration_ms = 2140`
- lifecycle continuity looked healthy in the completed March 30, 2026 run
  - `artifacts/perf_evidence/lifecycle/20260330T183732_R9TRC00GA2E`
  - same video survived the return flow
  - playback advanced after returning
  - original verdict was falsely failed because the old log sampling path missed `activity_pause` and `activity_resume`
- lifecycle log collection is now fixed, and the next rerun produced a non-empty `lifecycle_perf_logs_during.txt`
  - `artifacts/perf_evidence/lifecycle/20260330T184547_R9TRC00GA2E`
  - this confirmed the streamed-log path was working before the attach-path fix landed
- lifecycle now passes end-to-end
  - `artifacts/perf_evidence/lifecycle/20260330T190258_R9TRC00GA2E`
  - `status = passed`
  - `same_video_after_return = true`
  - `after_playing = true`
  - `saw_activity_pause = true`
  - `saw_activity_resume = true`

## Honest Remaining Risks

- transition performance is improved but still not at the `<= 3000 ms` finish line
- lifecycle evidence is now closed for this pass, but CDP attach churn remains a maintenance risk worth watching in future cold-start or reconnect-heavy runs
- media pipeline churn remains a real risk area for perceived polish, especially when returning from background or during heavy watch-page changes

## April 2, 2026 Post-Unlock Crash Fix

After the later Samsung reruns, the real blocker was no longer "does PiP enter?" but "does the app crash when fullscreen drops while pinned or after unlock?".

What changed:

- `android/java/org/chromium/chrome/browser/media/BraveFullscreenVideoPictureInPictureController.java`
  - restored to the Brave-upstream minimal wrapper
  - removed the stale OneTabTube-only reflection logic that had started probing private controller internals such as `getWebContents()`
- `build/android/bytecode/java/org/brave/bytecode/BraveFullscreenVideoPictureInPictureControllerClassAdapter.java`
  - removed the `dismissActivityIfNeeded` owner redirect that forced the runtime path through the reflection-heavy Brave wrapper
- `/home/master/src_ext4/chrome/android/java/src/org/chromium/chrome/browser/media/FullscreenVideoPictureInPictureController.java`
  - took ownership of the `START` / `RESUME` `mDismissPending` clear directly in the controller so the desired Brave behavior survives without reflection

Why this was necessary:

- the real device crash logs showed `Effective video fullscreen change: false` immediately followed by:
  - `BraveReflectionUtil` `NoSuchMethodException` for `getWebContents()`
  - then later the same reflection failure for `dismissActivityIfNeeded(Activity,int)`
  - followed by `AssertionError` and a fatal app crash
- this meant the old wrapper/adapter combination was no longer safe in the current build pipeline, even though the PiP entry path itself was working

Observed result on `rerun208`:

- build: passed
  - `/home/master/src_ext4/out/android_Component_arm64/codex_onetabtube_build_repro_from_baseline_rerun208.log`
- APK SHA-256:
  - `d44788f94f8f731f78715a623ac622eb93157eb62bfafc8bdfe0be23b4f4b939`
- direct toolbar-button PiP:
  - still enters `mode=pinned`
- old crash signature:
  - not observed in direct PiP -> launcher testing
  - not observed in the latest power/wake run either

Remaining gap:

- the Samsung secure keyguard still blocks a final clean post-unlock verification run, so the wake/unlock UX is not yet marked fully verified

## April 2, 2026 Brave GitHub PiP Realignment (`rerun226`)

After the device owner clarified that "เหมือนของ Brave" means the behavior from the public Brave GitHub repo, the active PiP runtime path was pivoted back toward Brave GitHub instead of continuing the local Samsung-specific unlock-bounce graph.

What changed:

- `android/java/org/chromium/chrome/browser/youtube_script_injector/BraveYouTubeScriptInjectorNativeHelper.java`
  - restored the Brave-style direct PiP entry from the YouTube helper:
    - `resumeMediaSession(true)`
    - `enterPictureInPictureMode(new PictureInPictureParams.Builder().build())`
  - removed the local controller/recent-fullscreen recovery chain from the active path
- `browser/android/youtube_script_injector/youtube_script_injector_tab_helper.cc`
  - restored the shorter recent-fullscreen grace (`1500ms`)
  - removed the stale fullscreen re-arm logic in `MaybeSetFullscreen()`
  - removed the immediate PiP recovery call from `OnFullscreenScriptComplete(...)`
  - restored the visible-tab/fullscreen-trigger behavior in `MediaEffectivelyFullscreenChanged(...)`
- `build/android/bytecode/java/org/brave/bytecode/BraveFullscreenVideoPictureInPictureControllerClassAdapter.java`
  - restored Brave GitHub’s `dismissActivityIfNeeded(...)` owner redirect to the Brave wrapper
- `android/java/org/chromium/chrome/browser/app/BraveActivity.java`
  - removed the active screen on/off receiver registration from `onStartWithNative()`
  - removed the extra PiP restore/repair work from:
    - `onResume()`
    - `onWindowFocusChanged(...)`
    - `onTopResumedActivityChanged(...)`
    - `onUserLeaveHint()`
    - `onPictureInPictureUiStateChanged(...)`
    - `onPause()`
    - `onStop()`
  - simplified `onPictureInPictureModeChanged(...)` back toward Brave’s mode-change behavior

What did not change:

- OneTabTube product pruning and UI cleanup remain in place
- Brave Shields/adblock integration remains intact
- the source still contains some older local PiP helper code in `BraveActivity.java`, but it is no longer meant to drive the primary runtime path

Build/install result:

- build: passed
  - `/home/master/src_ext4/out/android_Component_arm64/codex_onetabtube_build_repro_from_baseline_rerun226.log`
- APK SHA-256:
  - `0a18ecfafc9218457383a1f8c17e90990fceb08eef9f4ead84556f2019411d35`
- install on `R9TRC00GA2E`: passed
- warm launch smoke:
  - passed via `adb shell am start -W -n com.onetabtube.browser_default/com.google.android.apps.chrome.Main`

Honest remaining gap:

- `rerun226` still needs a real manual PiP -> lock -> unlock validation pass on device before claiming that the Brave-GitHub-aligned path is better, worse, or equivalent on this Samsung phone

## April 2, 2026 Verified Lockscreen-Return PiP Snapshot (`rerun236`)

This is the publish snapshot for the specific issue where PiP used to break after returning from the lock screen.

What changed in the final working path:

- `browser/android/youtube_script_injector/youtube_script_injector_tab_helper.cc`
  - added a direct Fullscreen API fallback so the unlock-time recovery path no longer stalls waiting only for the fullscreen button to reappear
  - loosened the stale hidden-document gate so post-unlock visibility restoration is less likely to dead-end
- `chrome/android/java/src/org/chromium/chrome/browser/media/FullscreenVideoPictureInPictureController.java`
  - retained PiP while pinned if the device reports transient fullscreen loss after unlock
  - stopped refreshing PiP params from a non-fullscreen state
  - re-requests fullscreen before letting the PiP session degrade into page-state content
  - the tracked mirror for this live controller change is:
    - `patches/chrome-android-java-src-org-chromium-chrome-browser-media-FullscreenVideoPictureInPictureController.java.patch`

Why this version matters:

- this is the first known-good build where the device owner confirmed that returning from the lock screen no longer leaves PiP broken for the issue being debugged here
- repository note:
  - this version can leave the lock screen and continue using PiP without reproducing the earlier unlock-time PiP problem

Observed result on `R9TRC00GA2E`:

- build: passed
  - `/home/master/src_ext4/out/android_Component_arm64/codex_onetabtube_build_repro_from_baseline_rerun236.log`
- APK SHA-256:
  - `d1a38475750ab77154aaca6d52d8fff3c1bc20f22de4b9dba8a9f79fd8d1e71f`
- install:
  - passed
- warm launch:
  - passed
- lockscreen -> unlock -> PiP usability:
  - passed by manual device-owner verification
  - reported outcome: after returning from the lock screen, PiP is usable normally on this version

Honest scope note:

- this documents the verified-good snapshot for the investigated bug on the connected Samsung test device
- it does not claim that all future upstream YouTube / Android / OEM changes can never affect PiP behavior again

## April 4, 2026 beta1 fix onetab+pip+control+lifecycle

This is the beta1 publish snapshot requested after the device-owner verification pass.

What this beta1 snapshot includes:

- One-tab product behavior remains enforced in the active app surface
- PiP entry/exit lifecycle is stabilized enough for repeated manual use on the current Samsung test device
- PiP expand returns to the YouTube watch page instead of crashing or forcing fullscreen
- notification and PiP controls are wired into the current OneTabTube playback path
- bottom toolbar / multi-tab regression pruning remains in the shipped source snapshot

Latest verified build tied to this note:

- build log:
  - `/home/master/src_ext4/out/android_Component_arm64/codex_onetabtube_build_pip_fullscreen_play_resume_fix.log`
- APK SHA-256:
  - `18c01e6f21d837fb0ef2f557326cd3f47f0a19cc6b8a76c0fa98fa479491233b`

Manual verification recorded for this beta1 note:

- device: `R9TRC00GA2E`
- result:
  - user verified that entering/exiting PiP works normally for 3 rounds

Honest scope note:

- this beta1 note records the currently verified source/runtime snapshot only
- actual behavior can still vary later if upstream YouTube, Chromium, Android, or OEM behavior changes

## April 4, 2026 beta2 fix upgread control/autoplay

This is the beta2 source-of-truth snapshot requested for the current control/autoplay workstream.

What this beta2 snapshot includes:

- YouTube MIX `next/previous` control logic is tightened around reliable queue context instead of broad fallback navigation
- notification and PiP transport controls remain wired through the active OneTabTube playback path
- autoplay-next video-presentation carry-forward logic is added so the next item can try to restore focused video presentation after a fullscreen-presented item ends
- current desk-state and progress handoff are aligned with the installed APK snapshot

Latest build tied to this beta2 note:

- build log:
  - `/home/master/src_ext4/out/android_Component_arm64/codex_onetabtube_build_pip_autoplay_presentation_carry.log`
- APK SHA-256:
  - `836B85FF35E2278E106B0087056496D062169D7F3787C70EC30CE1DA413FE35F`

Verification status recorded for this beta2 note:

- device: `R9TRC00GA2E`
- verified:
  - source changes for control/autoplay are present in the installed build
  - build and install passed
  - current runtime desk-state is aligned in `docs/current-status.md` and `docs/progress-log.md`
- not yet fully verified:
  - autoplay-next restoring focused video presentation in a real pinned-PiP autoplay transition
  - automatic replay on the current session hit a separate `fullscreen -> PiP` Java visibility race before that truth-check completed

Honest scope note:

- this beta2 snapshot is the current source/runtime truth for the repository and installed APK
- it does not claim that the autoplay-next PiP presentation issue is fully closed yet; it records the exact in-repo state and latest known verification boundary
