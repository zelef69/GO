# Testing

## Device And Package

Primary validation device for the latest evidence:

- `R9TRC00GA2E`

Package under test:

- `com.onetabtube.browser_default`

Primary APK path used in these runs:

- `\\wsl.localhost\Ubuntu\home\master\src_ext4\out\android_Component_arm64\apks\OneTabTube.apk`

## Build Command

```powershell
wsl.exe -d Ubuntu -- bash -lc "cd /home/master/src_ext4/out/android_Component_arm64 && AUTONINJA_BUILD_ID=codex_perf ../../brave/vendor/depot_tools/ninja.py -j 14 apks/OneTabTube.apk"
```

## Evidence Commands

Transition baseline and transition test:

```powershell
python .\tools\perf_evidence\run_perf_evidence.py --device R9TRC00GA2E --mode baseline --transitions 1
python .\tools\perf_evidence\run_perf_evidence.py --device R9TRC00GA2E --mode transition --transitions 5
```

Background and lifecycle:

```powershell
python .\tools\perf_evidence\run_perf_evidence.py --device R9TRC00GA2E --mode background
python .\tools\perf_evidence\run_perf_evidence.py --device R9TRC00GA2E --mode lifecycle
```

Lockscreen and PiP:

```powershell
python .\tools\perf_evidence\run_perf_evidence.py --device R9TRC00GA2E --mode lockscreen
python .\tools\perf_evidence\run_perf_evidence.py --device R9TRC00GA2E --mode pip
python .\tools\perf_evidence\run_perf_evidence.py --device R9TRC00GA2E --mode pip_lockscreen --lockscreen-seconds 10
```

Prompt-aligned wrappers:

```powershell
.\tools\perf_evidence\run_player_transition_test.ps1 -Device R9TRC00GA2E
.\tools\perf_evidence\run_background_play_test.ps1 -Device R9TRC00GA2E
.\tools\perf_evidence\run_lifecycle_test.ps1 -Device R9TRC00GA2E
.\tools\perf_evidence\run_lockscreen_test.ps1 -Device R9TRC00GA2E
.\tools\perf_evidence\run_pip_test.ps1 -Device R9TRC00GA2E
.\tools\perf_evidence\run_pip_lockscreen_test.ps1 -Device R9TRC00GA2E -LockscreenSeconds 10
```

Manual capture when automation needs backup evidence:

```powershell
.\tools\perf_evidence\collect_logs.ps1 -Device R9TRC00GA2E
```

## Watch Page Smoothness Checklist

- cold launch opens an allowed YouTube target without obvious chrome churn
- watch page stabilizes without long black or blank intervals
- first visible frame arrives quickly
- related and next-video rows do not visibly jump after initial render
- toolbar and browser chrome do not flicker or reset unnecessarily

## Player Continuity Checklist

- direct-open watch page starts real playback
- audible playback is present, not only moving video frames
- pause and resume remain responsive
- moving to the next video does not leave the player stuck or muted
- error or playability overlays do not remain stuck after recovery should have happened

## Transition Checklist

- `next_to_first_frame_ms <= 3000` for the target path
- `black_screen_duration_ms` is short enough that the handoff feels continuous
- screenshots do not show long black or blank states
- `console_events.json` and `summary.json` agree on the transition order

## PiP Checklist

- PiP request succeeds
- playback continues during PiP
- audio remains in sync and continuous
- returning from PiP restores the same watch context without a jarring reset
- entering or leaving PiP does not produce a new black-screen regression

## PiP Lockscreen Checklist

- PiP enters before the screen turns off
- the activity remains pinned across screen-off and unlock
- the PiP shell keeps showing video content instead of expanding to the full watch page by mistake
- `after_state` is still collectible after unlock, or the failure is clearly identified as tooling churn rather than app behavior
- `pip_fullscreen_repair_requested:*` does not loop repeatedly once the player is already stable

## Lifecycle Checklist

- home and return keep the same video when product intent says playback should continue
- activity pause and resume markers appear in the collected perf logs
- after returning, the player is still in a real playing state
- the page does not come back muted, frozen, or on a stale error surface
- if automation fails, collect manual logs and confirm whether the failure is app behavior or CDP discovery churn

## Background Playback Checklist

- current time advances while the app is in the background
- media session remains valid during the hold window
- returning to the app does not lose playback state
- controls remain coherent with the actual playback state

## Lockscreen Checklist

- playback survives screen-off interval when product intent allows it
- unlock returns to the same session
- current time advances across the lockscreen interval
- audio does not disappear on unlock

## UI And UX Regression Checklist

- no leftover browser UI appears in normal OneTabTube flows
- back behavior is predictable
- loading states look intentional rather than broken
- sign-in, consent, or blocked flows do not leave the app in a half-broken state
- orientation or resize changes do not destabilize the player surface

## Current Measured Status

As of March 30, 2026:

- transition target: still failing
  - best honest artifact is `artifacts/perf_evidence/transition/20260330T163209_R9TRC00GA2E`
  - `next_to_first_frame_ms = 3500`
- background playback: passed
  - `artifacts/perf_evidence/background/20260330T051937_R9TRC00GA2E`
- lockscreen playback: passed
  - `artifacts/perf_evidence/lockscreen/20260330T052216_R9TRC00GA2E`
- PiP: passed
  - `artifacts/perf_evidence/pip/20260330T053107_R9TRC00GA2E`
- lifecycle continuity: passed
  - completed continuity evidence: `artifacts/perf_evidence/lifecycle/20260330T183732_R9TRC00GA2E`
  - log-source fix evidence: `artifacts/perf_evidence/lifecycle/20260330T184547_R9TRC00GA2E`
  - end-to-end passing artifact: `artifacts/perf_evidence/lifecycle/20260330T190258_R9TRC00GA2E`

## April 2, 2026 PiP Restore Follow-Up

Manual spot-check from the restored `rerun201` build:

- build: passed
  - `/home/master/src_ext4/out/android_Component_arm64/codex_onetabtube_build_repro_from_baseline_rerun201.log`
- APK SHA-256:
  - `05ece024a2c488c8f2256655aa48a64c2fb08e11186354483394602dae3ce920`
- watch-page UI:
  - PiP button is visible again on the YouTube watch page
- PiP entry:
  - tapping the PiP button, then pressing Home, moves the task into `mode=pinned`
  - `mLastReportedPictureInPictureMode=true` was observed in `dumpsys activity`
- playback continuity:
  - YouTube QoE traffic kept advancing while pinned (`seq=4 -> 5 -> 6 -> 8`)
  - adblock events continued to appear during the pinned session
- screen-off handling:
  - `cr_OneTabTubePerf` showed `screen_off`, `pip_global_preserve_armed`, and `pip_restore_armed`
- remaining validation gap:
  - Samsung launcher handoff after power / unlock is still noisy, so one cleaner post-power-cycle foreground-return pass is still recommended before calling the lockscreen-return UX fully polished

## April 2, 2026 PiP Direct-Tap Follow-Up

Manual rerun from the newer `rerun204` build to close the gap between "fullscreen/JS path exists" and "a real user tap on the visible PiP button actually enters PiP":

- build: passed
  - `/home/master/src_ext4/out/android_Component_arm64/codex_onetabtube_build_repro_from_baseline_rerun204.log`
- APK SHA-256:
  - `d21da8e3a45cdce3b949af6b09e1ea5f3fc09b505bb621676eef84ee5ae2a3ec`
- device:
  - `R9TRC00GA2E`
- flow:
  - `adb shell am force-stop com.onetabtube.browser_default`
  - `adb logcat -c`
  - open `https://youtu.be/dQw4w9WgXcQ`
  - wait for the watch page to settle
  - tap the visible PiP button directly
- result:
  - PiP entered immediately from the button tap without needing Home
  - `tmp_toolbar_pip_logcat.txt` contains:
    - `event=pip_enter_request:toolbar_button`
    - `event=pip_immediate_request:toolbar_button:entered=true`
    - `event=pip_mode_changed:true`
  - `tmp_toolbar_pip_dumpsys.txt` contains:
    - `mode=pinned`
    - `mLastReportedPictureInPictureMode=true`
  - `window_dump_pip_verify.xml` is the UI dump collected from the watch page before the tap
- remaining validation gap:
  - power/off unlock preserve/restore has not yet been rerun after the immediate-entry change, so the old `rerun201` power-cycle evidence is still the newest coverage for that part

## April 2, 2026 Brave-Upstream PiP Wiring Follow-Up

Manual validation after replacing the local immediate-entry workaround with the actual Brave-upstream PiP wiring:

- build: passed
  - `/home/master/src_ext4/out/android_Component_arm64/codex_onetabtube_build_repro_from_baseline_rerun206.log`
- APK SHA-256:
  - `1a611f8412dd27e15e99df7007ad9130bf81cea53fc6d7051a5cc6e5f64632d9`
- device:
  - `R9TRC00GA2E`
- upstream alignment:
  - toolbar button reverted to the Brave-upstream `setFullscreen(...)` path
  - `BraveYouTubeScriptInjectorNativeHelper.enterPictureInPicture(...)` reverted to the Brave-upstream direct `enterPictureInPictureMode(...)` call
- direct tap result:
  - pass
  - `tmp_toolbar_pip_logcat_rerun206.txt` contains:
    - `OTB_PERF event=fullscreen_script_result result=fullscreen_triggered`
    - `event=pip_mode_changed:true`
  - `tmp_toolbar_pip_recents_rerun206.txt` contains:
    - pinned OneTabTube task `#533`
    - `mode=pinned`
- power/off -> wake result:
  - partial
  - pinned OneTabTube task still exists in recents after wake
  - this confirms the session is not disappearing immediately
- foreground-return result after wake:
  - fail
  - launcher relaunch created a new fullscreen OneTabTube task `#534` instead of reusing the pinned task `#533`
- current honest conclusion:
  - Brave-upstream PiP entry wiring is working on hardware
  - the remaining instability is specifically the relaunch-after-wake task reuse path, not the direct PiP entry path itself

## April 2, 2026 Repeated Upstream-Aligned Reruns

Repeated Samsung reruns after the upstream alignment were not cleanly repeatable yet:

- some reruns still showed a valid upstream-style PiP transition
- other reruns failed earlier because:
  - the PiP button never appeared in `window_dump_waitpip.xml`
  - or the blind-tap path could not be trusted without the button being present
- honest conclusion:
  - the code is now anchored to Brave upstream
  - but OneTabTube still needs one more narrow fix to make PiP entry/return repeatable enough to call stable on this device

## April 2, 2026 Post-Unlock Crash Follow-Up (`rerun208`)

This follow-up exists because the device owner reported a real crash after unlock, and later log collection proved that this was not just lockscreen noise.

Build:

- passed
  - `/home/master/src_ext4/out/android_Component_arm64/codex_onetabtube_build_repro_from_baseline_rerun208.log`
- APK SHA-256:
  - `d44788f94f8f731f78715a623ac622eb93157eb62bfafc8bdfe0be23b4f4b939`

Crash root cause that was fixed:

- old logs showed:
  - `Effective video fullscreen change: false`
  - `BraveReflectionUtil` `NoSuchMethodException` for `getWebContents()`
  - then `NoSuchMethodException` for `dismissActivityIfNeeded(Activity,int)`
  - then `AssertionError` / fatal crash

What to verify on `rerun208`:

1. Launch a watch page with:
   - `adb -s R9TRC00GA2E shell am start -W -a android.intent.action.VIEW -d "https://youtu.be/dQw4w9WgXcQ" com.onetabtube.browser_default`
2. Enter PiP from the visible toolbar button.
3. Confirm:
   - `mode=pinned`
   - `mLastReportedPictureInPictureMode=true`
   - no `BraveReflectionUtil` PiP fatal in `adb logcat -d`
   - no new entry in `adb logcat -b crash -d`

Latest observed result:

- direct PiP -> launcher: passed
- latest power/wake run:
  - no old crash signature
  - crash buffer stayed empty
  - device still returned to Samsung secure keyguard after wake

Honest remaining gap:

- final post-unlock validation still requires the phone to be manually unlocked, because `wm dismiss-keyguard` is not enough on this device and `uiautomator dump` can fail while the keyguard is active

## Review Order For Any Failed Run

1. `summary.json`
2. `app_events.log`
3. `console_events.json`
4. screenshots
5. `dumpsys activity` artifact
6. `dumpsys media_session` artifact
7. `logcat_full.txt`

## Current PiP Validation Focus - April 2, 2026 (`rerun226`)

Current target:

- validate the Brave-GitHub-aligned PiP path instead of the earlier local unlock-bounce recovery path

Current APK:

- `/home/master/src_ext4/out/android_Component_arm64/apks/OneTabTube.apk`
- SHA-256:
  - `0a18ecfafc9218457383a1f8c17e90990fceb08eef9f4ead84556f2019411d35`

Manual device steps:

1. Open a YouTube watch page in OneTabTube.
2. Enter PiP normally.
3. Lock the device.
4. Unlock the device manually.
5. Observe whether PiP:
   - stays intact like Brave-style PiP
   - goes black
   - visibly walks through page/fullscreen states
   - or crashes/dismisses

If the run fails, capture immediately:

- `adb -s R9TRC00GA2E shell screencap -p /sdcard/pip_after_unlock_rerun226.png`
- `adb -s R9TRC00GA2E pull /sdcard/pip_after_unlock_rerun226.png C:\Users\Master\Desktop\GO_PLAY\pip_after_unlock_rerun226.png`
- `adb -s R9TRC00GA2E logcat -b crash -d > C:\Users\Master\Desktop\GO_PLAY\tmp_toolbar_pip_crash_rerun226.txt`
- `adb -s R9TRC00GA2E logcat -d -v threadtime cr_OneTabTubePerf:I chromium:I VideoPersist:I AndroidRuntime:E DEBUG:E *:S > C:\Users\Master\Desktop\GO_PLAY\tmp_toolbar_pip_logcat_rerun226.txt`
- `adb -s R9TRC00GA2E shell dumpsys activity activities > C:\Users\Master\Desktop\GO_PLAY\tmp_toolbar_pip_activities_rerun226.txt`
- `adb -s R9TRC00GA2E shell dumpsys window windows > C:\Users\Master\Desktop\GO_PLAY\tmp_toolbar_pip_windows_rerun226.txt`

## April 2, 2026 Verified Lockscreen-Return PiP Result (`rerun236`)

Manual validation result for the build that is being published as the current good snapshot for this issue:

- build:
  - passed
  - `/home/master/src_ext4/out/android_Component_arm64/codex_onetabtube_build_repro_from_baseline_rerun236.log`
- APK SHA-256:
  - `d1a38475750ab77154aaca6d52d8fff3c1bc20f22de4b9dba8a9f79fd8d1e71f`
- device:
  - `R9TRC00GA2E`
- flow:
  - open a YouTube watch page
  - enter PiP
  - lock the device
  - unlock the device
  - continue using the PiP window
- result:
  - passed
  - user-verified outcome: after returning from the lock screen, PiP is usable normally on this version
  - this is the repository version to keep marked as:
    - lockscreen return no longer reproduces the PiP issue

Known evidence chain behind this result:

- the last broken rerun before the fix was `rerun235`
  - `tmp_toolbar_pip_logcat_rerun235_live.txt`
  - `pip_after_unlock_rerun235_live.png`
- the successful published snapshot is `rerun236`
  - build/install/warm launch passed
  - manual truth-check passed
