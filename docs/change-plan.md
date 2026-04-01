# Change Plan

## Goal

Close the gap between "OneTabTube can play videos" and "OneTabTube feels stable and low-friction at Brave quality" for:

- watch page rendering
- player continuity
- next-video transitions
- background playback
- lockscreen playback
- PiP
- lifecycle return flows
- evidence quality

## Baseline Findings Driving The Plan

The current plan is driven by measured evidence, not guesswork:

- baseline transition evidence on March 30, 2026 showed `next_to_first_frame_ms = 4537` and `black_screen_duration_ms = 2908`
- later honest fast-path evidence improved to `3500 ms`, but still missed the `<= 3000 ms` target
- user-reported issues included muted playback, repeated "content not ready" overlays, and instability when returning from background
- background, lockscreen, PiP, and lifecycle flows now have passing artifacts, with lifecycle finally closed after fixing both log-source and DevTools attach reliability
- March 31, 2026 `pip_lockscreen` runs showed repeated fullscreen-repair churn and post-unlock reconnect instability, so lifecycle/PiP cost is now part of the ranked slowness attribution instead of only a correctness bug
- the latest `pip_lockscreen` rerun now passes end-to-end, which supports continuing this plan with player and lifecycle cost still ranked ahead of adblock for the normal slow path

## Change Groups

### 1. Player And Watch-Page Stability

- keep the user on canonical watch URLs when recovering or handing off to the next video
- preserve the existing watch page and player surface instead of forcing unnecessary recreation
- make audible playback recovery explicit so "video is playing" and "video is audible" are treated as separate success conditions
- keep playability recovery tied to real error states instead of optimistic assumptions

### 2. Transition Smoothness

- measure click-to-first-frame honestly across navigation boundaries
- warm only the next target paths that have evidence of helping
- prefer direct canonical next navigation when the target is already prepared
- keep tuning aimed at reducing the `navigation_to_first_frame_ms` bottleneck, which is still the largest remaining transition cost in the best recent runs

### 3. Lifecycle, Background, And PiP Correctness

- verify that activity pause and resume markers line up with real playback continuity
- keep the same video and playing state when returning from home, lockscreen, or PiP whenever the product intent says playback should continue
- reduce race conditions between Android lifecycle callbacks and page readiness
- keep PiP transitions from causing black screens, stale UI, or lost playback state

### 4. Evidence Tooling

- keep `run_perf_evidence.py` as the single structured entry point
- keep `pip_lockscreen` as a distinct scenario instead of hiding it inside generic PiP or generic lockscreen runs
- collect screenshots, console events, filtered app logs, `dumpsys activity`, and `dumpsys media_session`
- store enough evidence to explain failures without relying only on manual repro
- prefer the streamed `logcat_full.txt` artifact as the source of lifecycle verdicts because narrow `logcat -d -t 200` snapshots miss real events
- keep mid-scenario CDP reconnect separate from app restart so reconnect-heavy evidence does not invalidate itself

### 5. Documentation

- keep architecture notes centered on player, watch page, lifecycle, PiP, and background playback
- make testing docs directly runnable by QA or future debugging passes
- document measured status honestly, including unfinished parts

## Execution Order

1. Map the real player, watch-page, lifecycle, and PiP paths.
2. Capture baseline evidence.
3. Fix the most user-visible continuity failures first.
4. Patch the evidence harness so regressions are easy to prove.
5. Rebuild and rerun the structured tests.
6. Update the docs with measured outcomes, risks, and next steps.

## Exact Validation Steps

Build:

```powershell
wsl.exe -d Ubuntu -- bash -lc "cd /home/master/src_ext4/out/android_Component_arm64 && AUTONINJA_BUILD_ID=codex_perf ../../brave/vendor/depot_tools/ninja.py -j 14 apks/OneTabTube.apk"
```

Transition:

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

Manual log collection when automation itself is unstable:

```powershell
.\tools\perf_evidence\collect_logs.ps1 -Device R9TRC00GA2E
```

## Acceptance Criteria

This supplemental task is considered successful only when the repo has all of the following:

- a clear player/watch-page architecture map
- a documented smoothness and continuity plan
- repeatable tooling for transition, background, lifecycle, lockscreen, and PiP evidence
- real before/after evidence for the changed flows
- honest current status for each flow
- explicit risks and next steps for unfinished gaps

The product-level finish line remains stricter:

- watch page and player feel stable
- next-video transitions stop feeling obviously slow or blank
- PiP is usable, not merely enterable
- background and lockscreen playback remain continuous
- lifecycle returns do not lose context or surprise the user

## Current Remaining Gaps

- the transition target is still not fully closed because the best honest measured run remains `3500 ms`
- lifecycle evidence now passes end-to-end, but DevTools / CDP attach churn remains a future automation risk on cold-start and reconnect-heavy flows
- PiP lockscreen still needs continued validation because fullscreen-repair churn and post-unlock reconnect stability now sit on the critical path for both UX correctness and slowness attribution
- user-facing polish still depends on keeping watch-page resume behavior stable under real device churn, not only under clean test runs
