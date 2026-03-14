# Adblock Architecture

The adblock subsystem follows a browser-core style design where `AdblockEngine` is the runtime source of truth and adapters preserve legacy entry points.

## Core Components

- `lib/features/adblock/intercept/request_interceptor.dart`
  - Normalizes early request data into `RequestContext`:
    - `url`, `hostname`, `domain`, `path`, `query`
    - `resourceType`, `frameUrl`, `topLevelUrl`
    - `frameHostname`, `topLevelHostname`, `isTopLevel`
    - `method`, `headers`, `isThirdParty`

- `lib/features/adblock/core/adblock_engine.dart`
  - Central decision service.
  - Primary runtime API:
    - `evaluateRequest(RequestContext)`
    - `evaluateAdblockRequest(AdblockRequestContext)`
    - `getCosmeticPayload(PageContext)`
    - `getScriptletPayload(PageContext)`
    - `updateFilterSources()`
    - `compileFilters()`
    - `getEngineStats()`
  - Compatibility API (adapter layer):
    - `AdblockEngineBridge` methods (`evaluateRequestDetailed`, `getCosmeticResources`, etc.)

- `lib/features/adblock/config/filter_source_manager.dart`
  - Manages filter sources: built-in lists, custom lists, enable flags, metadata, and refresh behavior.

- `lib/features/adblock/filters/*`
  - `filter_parser.dart`: raw filter text -> typed rule models.
  - `rule_normalizer.dart`: canonicalizes parsed rules before compilation.
  - `rule_models.dart`: network/exception/redirect/rewrite, cosmetic, and scriptlet rule models.
  - `filter_compiler.dart`: compiled indices and rule buckets.

- `lib/features/adblock/matchers/*`
  - `request_matcher.dart`:
    - `findCandidates(context, compiledIndex)` for fast candidate narrowing.
    - `evaluateCandidates(context, candidates)` for deterministic full rule evaluation.
  - `redirect_target_resolver.dart`: resolves redirect aliases/resources and rewrite targets outside the fast matcher path.
  - `cosmetic_matcher.dart`: page-scoped cosmetic matching with domain exceptions.

- `lib/features/adblock/injection/scriptlet_engine.dart`
  - Resolves scriptlet payload by domain/page context.

- `lib/features/adblock/core/*injector.dart`
  - Injection-only runtime layer.
  - Consumes payloads from engine; no matching logic.

- `lib/features/adblock/core/request_blocker.dart`
  - Compatibility adapter only.
  - Forwards runtime evaluation/config/signal operations to engine runtime APIs.

- `lib/features/adblock/core/engine_request_policy.dart`
  - Engine-owned request policy module (legacy guardrails and heuristics).
  - Preserves behavior while keeping runtime ownership in `AdblockEngine`.
- `lib/features/adblock/core/engine_request_policy_*.dart`
  - Extracted submodules for policy cache, query utilities, and runtime state models.
  - Keeps policy methods composable and easier to tune/test independently.

## Request Flow

1. Interception layer captures outgoing request (`WebView` hooks / service worker interception).
2. `RequestInterceptor` normalizes request metadata into `RequestContext`.
3. Compatibility `RequestBlocker` forwards to `AdblockEngine.evaluateAdblockRequest(...)`.
4. Engine-owned request policy applies guardrails/safeguards and delegates matching to `AdblockEngine.evaluateRequest(...)`.
5. `AdblockEngine` runs:
   - compiled matcher (`findCandidates` -> `evaluateCandidates`) for local fallback and metrics,
   - native `adblock-rust` bridge evaluation as authoritative path when available,
   - deterministic typed decision resolution (`allow`, `block`, `redirect`, `rewriteResponse`).
6. Decision is returned through compatibility adapters to existing call sites.

When native bridge is available, native decision is authoritative. Local matcher remains as fallback when native bridge is unavailable or errors.

## Page Runtime Flow

1. On page start/finish, `WebViewAdblockIntegration` requests:
   - `AdblockManager.getCosmeticPayload(pageUri)`
   - `AdblockManager.getScriptletPayload(pageUri)`
2. Manager delegates both payloads to `AdblockEngine`.
3. `CosmeticFilterInjector` injects CSS/procedural actions from cosmetic payload.
4. `ScriptletInjector` injects scripts from scriptlet payload and toggles runtime enable state.

Cosmetic and scriptlet flows are separated end-to-end: matching is in engine/matchers, injectors only apply payloads.

## Matching and Performance

- Candidate narrowing uses prebuilt indices by:
  - hostname/domain tokens
  - URL/path tokens
  - resource type buckets
- Regex rules are kept out of the fast path whenever possible and evaluated in fallback stages.
- `AdblockEngine` maintains bounded request decision caching for repeated normalized requests.
- Parsed lists run through explicit `parse -> normalize -> compile` before runtime matching.
- Native engine snapshots are cached and reused via `Engine::serialize`/`deserialize` to reduce startup compile latency.

## Brave Flow Mapping

The runtime now mirrors Brave's core adblock lifecycle:

1. Load filter catalog + list sources + resources.
2. Build engine from rules (or deserialize cached snapshot when compatible).
3. Apply resources and tags.
4. Evaluate each request through native engine network matcher.
5. Evaluate cosmetic/scriptlet resources per page and inject in runtime layers.
6. Rebuild/reinitialize engine on list updates (no stale singleton init state).

## Observability

`AdblockEngine.getEngineStats()` exposes lightweight runtime metrics:

- request normalization time
- candidate lookup/evaluation timing
- regex fallback frequency
- decision cache hit/miss counters and hit rate
- compile duration and compiled rule counts
- cosmetic/scriptlet payload sizes

`AdblockService.getDebugSnapshot()` exposes both manager runtime counters and engine stats for debug UI/diagnostic surfaces.

## Compatibility and Migration

- Legacy APIs remain available via `AdblockManager`, `AdblockService`, and `AdblockEngineBridge`.
- Compatibility layers map legacy request/response models to typed engine decisions.
- Deprecated behavior is isolated to adapters; new code should call engine payload/decision APIs directly.
