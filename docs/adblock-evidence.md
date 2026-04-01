# Adblock Evidence

## Scope

This document records the evidence-driven adblock validation flow requested by `PROMPT_EVIDENCE_ADBLOCK_TEST_TH.txt`.

The goal for this pass was not to claim a permanent `100%` block rate. The goal was narrower and testable:

- preserve Brave-derived Shields/adblock architecture
- add enough evidence tooling to debug and validate real-device behavior
- pass the requested `Test 1` and `Test 2` runs on-device with the real `next` button flow

Device used for the passing evidence in this pass:

- `R9TRC00GA2E`

Package under test:

- `com.onetabtube.browser_default`

Primary APK path used in the successful device runs:

- `\\wsl.localhost\Ubuntu\home\master\src_ext4\out\android_Component_arm64\apks\OneTabTube.apk`

## What Changed

The successful adblock run in this repo came from a series of minimal Brave-path fixes rather than a replacement blocker:

- restored updater/default wiring for Brave component-backed adblock data in OneTabTube dev builds
- added OneTabTube-only startup prewarm/retry for the existing Brave adblock service and components
- added OneTabTube fallback download/caching for public filter lists/resources when the dev build does not have a Brave services key
- fixed a real runtime crash in the custom resource store path so the adblock stack could stay alive on-device
- fixed the YouTube resource fallback so required scriptlets such as `json-prune` and `set-constant` were available during real playback flows

Brave-derived paths intentionally preserved:

- Brave Shields preference registration
- Brave adblock service and engines
- Brave request interception / blocking path
- Brave resource/filter loading model

## Evidence Tooling Added

Repo structure required by the prompt now exists:

- `tools/adblock_evidence/`
- `artifacts/adblock_evidence/`
- `docs/adblock-evidence.md`

Key tooling:

- `tools/adblock_evidence/run_adblock_evidence.py`
  - drives the real watch-page flow
  - starts playback
  - clicks the actual `next` target on the live page
  - waits for the configured playback interval
  - records per-video JSON results
- `tools/adblock_evidence/run_baseline.ps1`
- `tools/adblock_evidence/run_test1.ps1`
- `tools/adblock_evidence/run_test2.ps1`
- `tools/adblock_evidence/export_summary.py`

Each run stores:

- metadata
- full logcat capture
- filtered app/devtools logs
- per-video structured result data
- screenshots
- network evidence
- machine-readable summary JSON

## Exact Build Command

```powershell
wsl.exe -d Ubuntu -- bash -lc "cd /home/master/src_ext4/out/android_Component_arm64 && AUTONINJA_BUILD_ID=codex_perf ../../brave/vendor/depot_tools/ninja.py -j 14 apks/OneTabTube.apk"
```

## Exact Test Commands

Baseline:

```powershell
python .\tools\adblock_evidence\run_adblock_evidence.py --device R9TRC00GA2E --mode baseline --videos 3 --hold-seconds 5
```

Test 1:

```powershell
python .\tools\adblock_evidence\run_adblock_evidence.py --device R9TRC00GA2E --mode test1 --videos 20 --hold-seconds 5
```

Test 2:

```powershell
python .\tools\adblock_evidence\run_adblock_evidence.py --device R9TRC00GA2E --mode test2 --videos 20 --hold-seconds 60
```

## Baseline Findings

Baseline artifact:

- `artifacts/adblock_evidence/baseline/20260330T034157_R9TRC00GA2E_3x5s`

What baseline told us:

- the evidence harness could drive the real `next` flow on-device
- the app could already land in playback without obvious ad UI in the sampled baseline run
- that alone was not enough to prove readiness, because earlier debugging showed component-backed payloads and resource/scriptlet readiness were still the real weak points

This is why the pass stayed evidence-driven and kept going through startup wiring, fallback delivery, cache/resource validation, and repeated real-device runs.

## Passing Evidence

### Test 1

Artifact:

- `artifacts/adblock_evidence/test1/20260330T035320_R9TRC00GA2E_20x5s`

Result:

- `status = passed`
- `passed_videos = 20`
- `failed_videos = []`

Interpretation:

- the harness clicked through `20` videos using the real `next` flow
- each clip reached real playback
- each clip played for `4-5` seconds
- the stored per-video results did not record ad UI markers, successful ad requests, or an ad-caused failure

### Test 2

Artifact:

- `artifacts/adblock_evidence/test2/20260330T035846_R9TRC00GA2E_20x60s`

Result:

- `status = passed`
- `passed_videos = 20`
- `failed_videos = []`

Interpretation:

- the harness clicked through `20` videos using the same real `next` flow
- each clip stayed in real playback for `60` seconds
- the stored per-video results did not record ad-caused failures in this run

## Supporting Technical Evidence

Beyond the pass/fail summaries, the debugging trail for this pass also confirmed:

- fallback resources were present on-device with the required scriptlets
- filter list cache files were created on-device
- ad-related requests observed during YouTube playback were ending with `net::ERR_BLOCKED_BY_CLIENT`
- `adPlacements` and `playerAds` were reduced to `null` in the validated YouTube page-state checks used during this pass

These findings matter because they show the result was not just a visually lucky run. The underlying Brave-derived blocking path was active in the tested conditions.

## How To Read A Run

For any adblock evidence run, inspect in this order:

1. `summary.json`
   - overall status
   - per-video `pass` / `fail`
   - per-video page state
2. screenshots in the run folder
3. filtered app/devtools logs
4. full logcat only when a failure needs deeper diagnosis

Useful fields in each video result:

- `videoId`
- `url`
- `video.currentTime`
- `adPlacements`
- `playerAds`
- `adUi`
- `ad_request_count`
- `blocked_ad_requests`
- `successful_ad_requests`

## Debug Workflow

If a future run fails:

1. inspect the failing video entry in `summary.json`
2. check whether playback actually started or only the watch page loaded
3. check `adUi` and screenshots for visible ad markers
4. inspect blocked vs successful ad requests
5. compare with the current passing Test 1 / Test 2 artifacts before changing code

## Current Conclusion

For the conditions requested by `PROMPT_EVIDENCE_ADBLOCK_TEST_TH.txt`, this pass is successful.

The honest wording is:

- the repo now has working adblock evidence tooling
- baseline, Test 1, and Test 2 artifacts were collected
- in the passing runs on `R9TRC00GA2E`, the app passed the required `20x5s` and `20x60s` next-flow tests without recorded ad failures

Known limitation:

- this does not prove the product can never regress with future upstream Brave / YouTube behavior changes
- it proves the requested evidence runs passed in this build and test environment
