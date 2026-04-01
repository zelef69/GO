# Slowness Attribution

## Scope

This note tracks the evidence-backed attribution pass from `PROMPT_SLOWNESS_ATTRIBUTION_TH.txt`.

The goal is to separate cost across:

- Brave Shields and adblock
- watch-page and player rendering
- navigation and one-tab reuse
- lifecycle, background, lockscreen, and PiP restore
- cache, session, and profile reuse

## Method

Primary evidence sources:

- `tools/perf_evidence/run_perf_evidence.py`
- `artifacts/perf_evidence/baseline/20260330T043415_R9TRC00GA2E`
- `artifacts/perf_evidence/transition/20260330T163209_R9TRC00GA2E`
- `artifacts/perf_evidence/transition/20260330T161914_R9TRC00GA2E`
- `artifacts/perf_evidence/pip_lockscreen/20260331T120414_R9TRC00GA2E`
- `artifacts/perf_evidence/pip_lockscreen/20260331T122209_R9TRC00GA2E`
- `artifacts/perf_evidence/pip_lockscreen/20260331T124721_R9TRC00GA2E`

Key timing buckets used in this pass:

- `next_to_navigation_start_ms`
- `navigation_to_first_frame_ms`
- `next_to_first_frame_ms`
- `black_screen_duration_ms`
- `current_time_advanced`
- PiP and lifecycle markers from `app_events.log`

## Baseline Findings

### Transition Baseline

Artifact:

- `artifacts/perf_evidence/baseline/20260330T043415_R9TRC00GA2E`

Measured result:

- `next_to_navigation_start_ms = 1628`
- `navigation_to_first_frame_ms = 2908`
- `next_to_first_frame_ms = 4537`
- `black_screen_duration_ms = 2908`

Interpretation:

- the biggest honest cost is still after navigation begins
- the dominant slow path is not simply tap handling or allowlist interception
- target watch-page and media readiness still account for most of the visible delay

### Best Recent Honest Transition

Artifact:

- `artifacts/perf_evidence/transition/20260330T163209_R9TRC00GA2E`

Measured result:

- `next_to_first_frame_ms = 3500`
- `navigation_to_first_frame_ms = 2747`
- `black_screen_duration_ms = 2140`

Interpretation:

- the path is better than the earlier `~4.5 s` baseline
- the remaining bottleneck still sits mainly in player and watch-page readiness after navigation

## Current Attribution Summary

### 1. Player / Watch-Page Rendering Contribution: High

Evidence:

- `navigation_to_first_frame_ms` remains the largest bucket in both the baseline and the best honest recent transition
- the user-visible slow feel includes late title, icon, and page-shell hydration after the video path begins
- PiP fullscreen repair work has also shown that player and fullscreen state can churn even after the shell transition technically succeeds

Current conclusion:

- player and watch-page readiness is still the biggest slow-path contributor

### 2. Lifecycle / PiP / Restore Contribution: High

Evidence:

- `artifacts/perf_evidence/pip_lockscreen/20260331T120414_R9TRC00GA2E/app_events.log` showed repeated `pip_fullscreen_repair_requested:*` loops immediately after PiP entry
- the same run showed the app fighting transient fullscreen loss instead of staying on a clean stable path
- `artifacts/perf_evidence/pip_lockscreen/20260331T122209_R9TRC00GA2E/summary.json` still failed because post-transition inspection lost the watch page after PiP and unlock
- `artifacts/perf_evidence/pip_lockscreen/20260331T124721_R9TRC00GA2E/summary.json` now passes end-to-end and `app_events.log` shows `pip_fullscreen_repair_suppressed:entered:active_fullscreen`, which confirms proactive repair churn was part of the earlier cost

Current conclusion:

- lifecycle and PiP handling contributes materially to perceived slowness and instability
- even when the video keeps playing, extra fullscreen repair and restore churn adds latency and visual weirdness

### 3. Navigation / One-Tab Reuse Contribution: Medium

Evidence:

- `next_to_navigation_start_ms` is non-trivial at `1628 ms`, so this layer is not free
- canonical watch handoff and one-tab reuse work improved stability, but the dominant remaining delay still comes later
- bad navigation variants such as playlist or radio paths were already shown to cause broken states, so this layer is still important to keep tight

Current conclusion:

- navigation and one-tab reuse matter, but they are not currently the top bottleneck

### 4. Cache / Session / Profile Reuse Contribution: Medium

Evidence:

- the repo already benefits from reuse enough to avoid full cold-start cost on every transition
- however PiP, lockscreen, and reconnect-heavy paths still show reuse gaps, especially when the app or tooling has to rediscover a live watch page

Current conclusion:

- reuse is helping, but it is not yet strong enough to hide lifecycle churn under stress

### 5. Brave Shields / Adblock Contribution: Low To Medium

Evidence:

- the representative PiP and lifecycle artifacts are dominated by fullscreen, lifecycle, and restore markers, not adblock activity
- the typical before-state in `artifacts/perf_evidence/pip_lockscreen/20260331T122209_R9TRC00GA2E/summary.json` shows `playerAdsDom = false`
- the clearly bad ad-related transition artifact exists at `artifacts/perf_evidence/transition/20260330T161914_R9TRC00GA2E`, where `playerAdsDom = true` and the run explodes to `15160 ms`

Current conclusion:

- adblock is a real regression amplifier when an ad path leaks through
- but the normal dominant slowness today is not explained mainly by adblock cost

## Ranked Bottlenecks

1. player and watch-page readiness after navigation
2. lifecycle and PiP restore churn
3. navigation and one-tab handoff overhead
4. cache and session reuse gaps under reconnect-heavy flows
5. adblock overhead in the normal path

## Fix Order

1. remove unnecessary PiP fullscreen repair churn and stabilize post-unlock restore
2. keep `pip_lockscreen` evidence reliable so lifecycle fixes can be measured honestly
3. continue reducing `navigation_to_first_frame_ms` on canonical next-watch transitions
4. keep monitoring ad leakage regressions separately instead of treating them as the default cause

## Honest Status

As of March 31, 2026:

- the evidence does not support blaming adblock as the main current cause of slowness
- the strongest current contributors are player/watch-page readiness and lifecycle/PiP churn
- the latest `pip_lockscreen` artifact now passes with `current_time_advanced = 132.566535`, so the current lifecycle work is moving the right bottleneck instead of only shifting evidence around
- attribution is good enough to prioritize fixes, but every major patch still needs before-and-after artifacts
