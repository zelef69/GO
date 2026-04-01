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

## Review Order For Any Failed Run

1. `summary.json`
2. `app_events.log`
3. `console_events.json`
4. screenshots
5. `dumpsys activity` artifact
6. `dumpsys media_session` artifact
7. `logcat_full.txt`
