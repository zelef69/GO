# Performance And Playback Evidence

## Scope

This document records the evidence model for the Brave-level player UX pass from `PROMPT_BRAVE_LEVEL_PLAYER_UX_TH.txt`.

It covers:

- watch-page transition timing
- player continuity
- lifecycle pause and resume
- background playback
- lockscreen playback
- PiP
- PiP plus lockscreen interaction
- supporting visual and log artifacts

Primary device used in the latest runs:

- `R9TRC00GA2E`

## Tooling

Structured runner:

- `tools/perf_evidence/run_perf_evidence.py`

Wrappers:

- `tools/perf_evidence/run_player_transition_test.ps1`
- `tools/perf_evidence/run_background_play_test.ps1`
- `tools/perf_evidence/run_lifecycle_test.ps1`
- `tools/perf_evidence/run_lockscreen_test.ps1`
- `tools/perf_evidence/run_pip_test.ps1`
- `tools/perf_evidence/run_pip_lockscreen_test.ps1`

Support tools:

- `tools/perf_evidence/collect_logs.ps1`
- `tools/perf_evidence/export_summary.py`

## Artifact Layout

Each run writes to:

- `artifacts/perf_evidence/<mode>/<timestamp>_<device>/`

Important modes for the current pass:

- `transition`
- `lifecycle`
- `pip`
- `pip_lockscreen`

Typical contents:

- `metadata.json`
- `summary.json`
- `summary.txt`
- `console_events.json`
- `logcat_full.txt`
- `app_events.log`
- screenshots
- mode-specific `dumpsys activity` and `dumpsys media_session` snapshots

## Metrics

### Transition Metrics

- `next_to_navigation_start_ms`
  - host-observed time from next-click to the first navigation signal
- `navigation_to_first_frame_ms`
  - host-observed time from navigation start to first visible frame
- `next_to_first_frame_ms`
  - end-to-end user-visible handoff time
- `black_screen_duration_ms`
  - approximate blank or black interval until first real frame

Target for this pass:

- every tested transition should stay at or below `3000 ms`

### Continuity Metrics

- `current_time_advanced`
  - proves playback continued or resumed instead of only reporting a static "playing" flag
- `same_video_after_return`
  - verifies that home or lifecycle return did not drop the user onto a different watch context
- `after_playing`
  - verifies the returned player is in a real playing-ready state

### Lifecycle Markers

Collected from `BraveActivity` and page-side logging:

- `activity_resume`
- `activity_pause`
- `activity_stop`
- `application_state:<state>`
- `pip_mode_changed:true|false`
- `devtools_server enabled=true`
- page-side `OTB_PERF` milestones such as `navigation_start`, `page_load`, `playing`, and `first_frame`

## Important Evidence Change In This Pass

Earlier lifecycle verdicts relied on:

```powershell
adb logcat -d -t 200 -s cr_OneTabTubePerf:I OneTabTubePerf:I
```

That was too narrow and caused false lifecycle failures because real `activity_pause` and `activity_resume` markers could exist in the saved run log but still miss the last-200-line snapshot.

The runner now:

- starts logcat capture before app launch
- keeps the full streamed log in `logcat_full.txt`
- derives `app_events.log` and lifecycle perf-log artifacts from that streamed file instead of the narrow snapshot

This makes the lifecycle verdict path much more trustworthy.

## How To Read A Run

### Transition Run

Start with:

1. `summary.json`
2. `console_events.json`
3. before and after screenshots

Interpretation:

- if `next_to_navigation_start_ms` is low but `navigation_to_first_frame_ms` is still high, the main problem is on the target watch page after handoff
- if `next_to_first_frame_ms` looks surprisingly good but screenshots or console events disagree, treat the run as suspicious
- if `playerAdsDom` or playability error state appears on the target page, treat that as a real regression signal

### Lifecycle Or Background Run

Start with:

1. `summary.json`
2. `app_events.log`
3. `lifecycle_*` or `background_*` dumps
4. screenshots

Interpretation:

- `same_video_after_return = true` and positive `current_time_advanced` together are stronger evidence than a single lifecycle callback
- if activity markers are present but playback did not recover, the bug is probably page-side or media-session side
- if playback recovered but CDP disconnected, treat that as an automation reliability issue rather than an immediate user-visible regression

### PiP Run

Start with:

1. `summary.json`
2. `app_events.log`
3. `pip_activity.txt`
4. screenshots

Interpretation:

- PiP is only a pass if playback continuity survives both entry and return
- a successful PiP request without continuity is not enough

### PiP Lockscreen Run

Start with:

1. `summary.json`
2. `app_events.log`
3. `pip_lockscreen_activity_during.txt`
4. `pip_lockscreen_activity_after_unlock.txt`
5. `logcat_full.txt`

Interpretation:

- if PiP stays pinned but fullscreen repair keeps firing, treat lifecycle churn as a real contributor to perceived slowness and instability
- if `after_state` is missing while the app-side artifacts still look healthy, treat that as tooling churn unless the logs show a matching user-visible PiP exit or relaunch
- if a reconnect path restarts the app, the artifact is invalid for attribution and the runner must be fixed first

## Current Evidence Snapshot

### Baseline Transition

Artifact:

- `artifacts/perf_evidence/baseline/20260330T043415_R9TRC00GA2E`

Result:

- `next_to_navigation_start_ms = 1628`
- `navigation_to_first_frame_ms = 2908`
- `next_to_first_frame_ms = 4537`
- `black_screen_duration_ms = 2908`

### Best Honest Recent Transition

Artifact:

- `artifacts/perf_evidence/transition/20260330T163209_R9TRC00GA2E`

Result:

- `next_to_first_frame_ms = 3500`
- `navigation_to_first_frame_ms = 2747`
- `black_screen_duration_ms = 2140`

Interpretation:

- better than earlier `~4.0 s` honest runs
- still above target
- remaining bottleneck is mostly on target-page media readiness, not only on click handoff

### Regression-Catching Transition

Artifact:

- `artifacts/perf_evidence/transition/20260330T161914_R9TRC00GA2E`

Result:

- `next_to_first_frame_ms = 15160`
- target page reported `playerAdsDom = true`

Interpretation:

- useful reminder that a fast path is not enough if target-page state can still collapse under real content conditions

### Background, Lockscreen, And PiP

Passed artifacts:

- background: `artifacts/perf_evidence/background/20260330T051937_R9TRC00GA2E`
- lockscreen: `artifacts/perf_evidence/lockscreen/20260330T052216_R9TRC00GA2E`
- pip: `artifacts/perf_evidence/pip/20260330T053107_R9TRC00GA2E`

### PiP Lockscreen

Focused artifacts:

- `artifacts/perf_evidence/pip_lockscreen/20260331T120414_R9TRC00GA2E`
- `artifacts/perf_evidence/pip_lockscreen/20260331T122209_R9TRC00GA2E`
- `artifacts/perf_evidence/pip_lockscreen/20260331T124721_R9TRC00GA2E`

What they showed:

- the earlier run exposed repeated `pip_fullscreen_repair_requested:*` loops immediately after PiP entry
- the follow-up run no longer showed the same fullscreen-loss symptom in the app events, which suggests the player-side PiP state is improving
- the remaining failure in the follow-up run was post-unlock inspection churn, so the evidence harness itself needs to avoid app restarts during reconnect-heavy flows
- the latest run now passes end-to-end, keeps `after_state`, and records `pip_fullscreen_repair_suppressed:entered:active_fullscreen`, which is the expected sign that proactive repair churn has been reduced

### Lifecycle

Completed continuity artifact:

- `artifacts/perf_evidence/lifecycle/20260330T183732_R9TRC00GA2E`

What it showed:

- same video survived return
- playback advanced after return
- old verdict falsely failed because the narrow log snapshot missed activity markers

Follow-up artifact after the log-source fix:

- `artifacts/perf_evidence/lifecycle/20260330T184547_R9TRC00GA2E`

What it showed:

- `lifecycle_perf_logs_during.txt` is no longer empty
- streamed app markers are now being captured from the run log

End-to-end passing lifecycle artifact after the attach-path fix:

- `artifacts/perf_evidence/lifecycle/20260330T190258_R9TRC00GA2E`

What it showed:

- `status = passed`
- `current_time_advanced = 123.46437200000001`
- `same_video_after_return = true`
- `after_playing = true`
- `saw_activity_pause = true`
- `saw_activity_resume = true`
- `app_events.log` captured the expected lifecycle sequence from initial resume through home and return

## When To Use Manual Logs

Use `collect_logs.ps1` when:

- CDP discovery is unstable
- the app is visibly on screen but automation cannot attach cleanly
- you need lifecycle, media-session, and window-state evidence even without a clean structured run

This is especially useful for:

- background return bugs
- lockscreen return bugs
- PiP exit bugs
- renderer or DevTools churn that blocks full automation

## Honest Current Status

As of March 30, 2026:

- the evidence stack is strong enough to support real player UX work
- transition timing is improved but not finished
- background, lockscreen, and PiP have passing evidence
- lifecycle evidence is now closed with a passing end-to-end artifact after the log-source and DevTools attach fixes
- PiP lockscreen is now a dedicated tracked scenario because it mixes player continuity, fullscreen state, lifecycle ordering, and reconnect-heavy evidence collection
- PiP lockscreen now also has a passing artifact on March 31, 2026 after the proactive-repair suppression and lightweight reconnect changes
