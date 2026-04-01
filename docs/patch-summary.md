# Patch Summary

## Scope Of This Pass

This pass is the Brave-level player UX follow-up. It consolidates prior playback, autoplay, playability, PiP, and evidence work into a clearer player-focused package instead of leaving the repo documented mainly as adblock work plus scattered perf notes.

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
