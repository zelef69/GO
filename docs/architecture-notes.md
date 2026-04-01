# Architecture Notes

## Supplemental Goal

This pass follows both `PROMPT_BRAVE_LEVEL_PLAYER_UX_TH.txt` and
`PROMPT_SLOWNESS_ATTRIBUTION_TH.txt`: make OneTabTube feel closer to a polished
Brave-derived product while also separating where the remaining slowness really comes from.

The focus is not "make the feature exist." The focus is:

- stable watch-page rendering
- smooth player start and next-video handoff
- reliable background, lockscreen, and PiP continuity
- lifecycle transitions that do not lose state or break playback
- low-friction UI behavior without abandoning Brave's architecture

## Product Surface Map

### Entry And Scope Gating

- `android/java/org/chromium/chrome/browser/OneTabYouTubeMode.java`
  - restricts the product surface to allowed YouTube URLs and fallback handling
- `android/java/org/chromium/chrome/browser/BraveIntentHandler.java`
  - normalizes incoming launch intents through `OneTabYouTubeMode.toAllowedOrFallback(...)`

This keeps OneTabTube a Brave-based browser flow with a narrow product surface, not a WebView shell.

### Activity And App Lifecycle Shell

- `android/java/org/chromium/chrome/browser/app/BraveActivity.java`
  - owns Android activity lifecycle integration
  - logs `activity_resume`, `activity_pause`, `activity_stop`, application foreground/background changes, and PiP mode changes through `logOneTabPerf(...)`
  - exposes the PiP entry path and DevTools server startup used by evidence tooling

This is the main Android-side source of truth for:

- foreground/background handoff
- PiP enter and exit
- lifecycle ordering
- app-visible playback continuity markers

### Watch Page And Player Runtime

- `browser/android/youtube_script_injector/youtube_script_injector_tab_helper.cc`
  - injects the page-side runtime that warms the next watch target
  - coordinates `prefetch`, `preconnect`, media warmup, and canonical next-video handoff
  - manages autoplay intent, audible playback recovery, playability recovery, foreground resume, and transition debug state
  - listens for page events such as `pageshow`, `focus`, and page-level `resume`

This is the main place where perceived smoothness is won or lost:

- first visible frame timing
- black-screen duration
- "content not ready" recovery
- audible autoplay behavior
- state continuity after returning from background or PiP

### Evidence And Validation Layer

- `tools/perf_evidence/run_perf_evidence.py`
  - structured runner for `baseline`, `transition`, `background`, `lifecycle`, `lockscreen`, `pip`, and `pip_lockscreen`
- `tools/perf_evidence/run_player_transition_test.ps1`
- `tools/perf_evidence/run_background_play_test.ps1`
- `tools/perf_evidence/run_lifecycle_test.ps1`
- `tools/perf_evidence/run_lockscreen_test.ps1`
- `tools/perf_evidence/run_pip_test.ps1`
- `tools/perf_evidence/run_pip_lockscreen_test.ps1`
- `tools/perf_evidence/collect_logs.ps1`
- `tools/perf_evidence/export_summary.py`

This layer exists so smoothness and continuity claims can be backed by timestamps, logs, screenshots, and dumpsys output instead of only "felt better" verification.

## Continuity Map

The current intended continuity chain is:

1. `BraveIntentHandler` admits only allowed YouTube targets.
2. `BraveActivity` creates and resumes the Brave-derived activity shell.
3. `youtube_script_injector_tab_helper.cc` injects the watch-page runtime.
4. The page runtime warms likely next targets and stores transition state.
5. On `pageshow`, `focus`, or explicit `resume`, the runtime calls foreground and audible recovery helpers.
6. On Android-side lifecycle changes, `BraveActivity` logs the handoff so the evidence runner can verify what happened.
7. `run_perf_evidence.py` correlates player state, screenshots, console events, and activity/media-session state into a run summary.

## Main Risk Points

### Watch Page And Transition Risks

- YouTube SPA navigation and canonical watch navigation can diverge.
- A visually "fast" handoff can still fail later if target-page media readiness is slow.
- A bad warm path can create false-positive evidence while making real transitions worse.

### Player And Playback Risks

- autoplay can look armed but still stay muted or blocked
- playability overlays can survive across navigation unless actively recovered
- renderer or media-pipeline churn can leave the player surface alive but no longer trustworthy

### Lifecycle And PiP Risks

- returning from home, lockscreen, or PiP can race with page readiness
- activity callbacks can say "resume" while the page or media session is not actually ready
- DevTools / CDP discovery can churn during app restart or renderer replacement, which matters for evidence reliability even when the app remains usable

### UX Polish Risks

- leftover browser chrome or toolbar jumps can make the app feel unfinished
- layout resets and flicker are as damaging to perceived quality as outright failures
- background playback that "does not stop" is not enough if resume, controls, or state restoration are confusing

## Current Evidence-Backed Status

As of March 30, 2026:

- transition instrumentation is much more trustworthy than the earlier late-day runs because cross-navigation timing now uses absolute wall-clock markers
- the best honest measured transition is still above target at `3500 ms` in `artifacts/perf_evidence/transition/20260330T163209_R9TRC00GA2E`
- background playback passed in `artifacts/perf_evidence/background/20260330T051937_R9TRC00GA2E`
- lockscreen playback passed in `artifacts/perf_evidence/lockscreen/20260330T052216_R9TRC00GA2E`
- PiP passed in `artifacts/perf_evidence/pip/20260330T053107_R9TRC00GA2E`
- lifecycle continuity itself looked healthy in `artifacts/perf_evidence/lifecycle/20260330T183732_R9TRC00GA2E` because playback advanced and the same video survived the return flow, but the original verdict falsely failed due to narrow log sampling
- the lifecycle harness now reads the streamed logcat artifact instead of only `adb logcat -d -t 200`
- the DevTools attach path now waits for `event=devtools_server enabled=true` and refreshes the forwarded socket before CDP reconnects
- lifecycle now passes end-to-end in `artifacts/perf_evidence/lifecycle/20260330T190258_R9TRC00GA2E` with `same_video_after_return = true`, `after_playing = true`, `saw_activity_pause = true`, and `saw_activity_resume = true`

As of March 31, 2026:

- the PiP lockscreen path now has its own scenario under `pip_lockscreen`
- `artifacts/perf_evidence/pip_lockscreen/20260331T120414_R9TRC00GA2E` exposed repeated fullscreen-repair churn immediately after PiP entry
- `artifacts/perf_evidence/pip_lockscreen/20260331T122209_R9TRC00GA2E` showed the fullscreen-loss symptom improved, but post-unlock inspection still dropped `after_state`
- `artifacts/perf_evidence/pip_lockscreen/20260331T124721_R9TRC00GA2E` now passes end-to-end, with playback advancing across the lockscreen interval and proactive fullscreen repair suppressed once active fullscreen is already stable
- the current attribution therefore treats player readiness and lifecycle/PiP churn as the main bottlenecks, with adblock acting more as a separate regression amplifier than the default slow-path cause

## Constraints For This Pass

- keep Brave Android as the base product
- keep Brave Shields and request paths intact
- do not replace the app with a WebView architecture
- do not paper over transition or lifecycle problems with cosmetic overlays alone
- prefer minimal, explainable patches in the real player, lifecycle, and evidence paths
