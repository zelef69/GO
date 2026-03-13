# Adblock Migration Guide

This document describes migration from the previous adblock implementation to the current engine-centered architecture.

## Summary

- Central runtime owner: `AdblockEngine`
- Explicit compiled pipeline: `parse -> normalize -> compile`
- Typed request outcomes: `allow`, `block`, `redirect`, `rewriteResponse`
- Existing call sites remain available through compatibility adapters

## What Changed

1. Request normalization is centralized in `RequestInterceptor` and consistently produces `RequestContext`.
2. Filter pipeline was split into explicit stages:
   - parser (`filters/filter_parser.dart`)
   - normalizer (`filters/rule_normalizer.dart`)
   - compiler/index builder (`filters/filter_compiler.dart`)
3. Runtime matching is split into:
   - candidate narrowing (`findCandidates`)
   - full deterministic evaluation (`evaluateCandidates`)
4. Request decisions are generated in `AdblockEngine` and now include typed redirect/rewrite actions.
5. Runtime decision policy logic moved behind engine-owned module:
   - `core/engine_request_policy.dart`
   - extracted helpers:
     - `core/engine_request_policy_cache.dart`
     - `core/engine_request_policy_query_utils.dart`
     - `core/engine_request_policy_state.dart`
   - entrypoint: `AdblockEngine.evaluateAdblockRequest(...)`
6. Cosmetic and scriptlet matching remain engine-side; injectors consume payload only.
7. Redirect/rewrite target handling now runs through dedicated resolver layer:
   - `matchers/redirect_target_resolver.dart`
8. Engine adds lightweight stats via `getEngineStats()` for cache/timing/regex/compile/payload metrics.
9. `AdblockService.getDebugSnapshot()` now exposes aggregated runtime + engine diagnostics for debug UI integration.

## Backward Compatibility

These APIs continue to work and now route through engine-owned decisions:

- `AdblockService.evaluateRequest(...)`
- `AdblockManager.evaluate(...)`
- `RequestBlocker.evaluate(...)`
- `AdblockEngineBridge` request/cosmetic methods used by integration layers

`RequestBlocker` and manager/service classes are compatibility facades. Core matching and typed decision logic must stay in engine/matcher modules.

## Adapter Scope (Thin Wrappers)

- `RequestBlocker`: forwards runtime evaluation/config/signal operations to engine runtime APIs.
- `AdblockManager`: lifecycle/config facade, delegates matching/payloads to engine.
- `AdblockService`: application-facing facade around manager and webview integration.
- `EngineAdapter`: native/fallback bridge selection only.

## Deprecated Internal Pattern

Avoid embedding adblock matching logic in UI/integration classes.

Preferred path:

1. Normalize request with `RequestInterceptor`.
2. Evaluate via `AdblockEngine`.
3. Consume typed decision/payload in runtime adapters.

## Behavior Notes

- Native bridge remains authoritative when available for explicit allow/block/redirect/rewrite outcomes.
- Compiled Dart matcher provides deterministic fallback and custom-list matching.
- Compiled exception rules short-circuit blocking actions.
- Regex rules are evaluated in fallback stages, not in the primary fast path.
