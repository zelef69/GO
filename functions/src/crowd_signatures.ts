import * as admin from "firebase-admin";
import {createHash} from "crypto";
import {gzipSync} from "zlib";
import {logger} from "firebase-functions";
import {
  CallableRequest,
  HttpsError,
  onCall,
} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore();
const storageBucket = admin.storage().bucket();

const crowdMetaDoc = db.collection("crowd_meta").doc("current");
const adCandidatesCollection = db.collection("ad_candidates");
const adSignaturesCollection = db.collection("ad_signatures");
const adCandidateReportsCollection = db.collection("ad_candidate_reports");
const crowdSnapshotHistoryCollection = db.collection("crowd_snapshot_history");
const crowdRateLimitCollection = db.collection("crowd_rate_limits");

const PROJECT_SALT = process.env.GCLOUD_PROJECT ?? "go_play";
const MAX_CANDIDATES_PER_SUBMIT = 30;
const MAX_SUBMITS_PER_MINUTE = 80;
const MAX_EVENTS_PER_UID_PER_DAY = 1500;
const CANDIDATE_TTL_DAYS = 30;
const ACTIVE_SIGNATURE_TTL_DAYS = 45;

const RESOURCE_TYPES = new Set<string>([
  "script",
  "xmlhttprequest",
  "media",
  "image",
  "subdocument",
  "stylesheet",
  "other",
]);

const BASE_REASON_ALLOWLIST = new Set<string>([
  "googlevideo_ad_query_hard",
  "pagead_interaction_guard",
  "heuristic_matcher",
  "engine_match",
  "third_party_tracker",
]);

const MARKER_ALLOWLIST = new Set<string>([
  "oad",
  "ads_payload",
  "adformat",
  "ad_type",
  "ad_preroll",
  "dclk_video_ads",
  "ad3_module",
  "videoadid",
  "adtag",
  "ad_tag",
  "ad_debug",
  "adsid",
  "ad_host_tier",
  "ad_flags",
  "ad_cpn",
  "adid",
  "ad_mt",
  "ad_eurl",
  "ad_url",
  "adurl",
  "ad_break",
  "ad_break_id",
  "adpod",
  "ad_pod",
  "ad_campaign",
  "ad_cid",
  "ad_placement",
  "adplacement",
  "ad_source",
  "adserver",
  "ad_server",
  "ad_slot",
  "adslot",
  "adslotname",
  "adcontext",
  "ad_context",
  "adcontexturl",
  "ad_context_url",
  "adunit",
  "ad_unit",
  "preroll",
  "midroll",
  "postroll",
  "label",
  "ctier",
  "ai",
  "cid",
  "sigh",
  "adk",
  "svpuc",
  "sabr",
  "rqh",
]);

const HOST_SUFFIX_ALLOWLIST: string[] = [
  ".googlevideo.com",
  ".youtube.com",
  ".doubleclick.net",
  ".googlesyndication.com",
  ".googleadservices.com",
];

type CandidateState = "learning" | "candidate" | "active" | "quarantined" | "expired";

interface SanitizedCandidate {
  clientEventId: number | null;
  sigHash: string;
  resourceType: string;
  hostPattern: string;
  pathPattern: string;
  sourceHost: string;
  markerKeys: string[];
  requireAdSignal: boolean;
  baseReason: string;
  confidence: number;
  score: number;
  createdAtMs: number;
}

function ensureAuthenticated(request: CallableRequest<unknown>): string {
  const uid = request.auth?.uid ?? "";
  if (uid.length === 0) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  return uid;
}

function ensureAdmin(request: CallableRequest<unknown>): string {
  const uid = ensureAuthenticated(request);
  if (request.auth?.token?.admin === true) {
    return uid;
  }
  throw new HttpsError("permission-denied", "Admin role required.");
}

function asRecord(value: unknown): Record<string, unknown> {
  if (typeof value === "object" && value !== null) {
    return value as Record<string, unknown>;
  }
  return {};
}

function asString(value: unknown, fallback = ""): string {
  if (typeof value !== "string") {
    return fallback;
  }
  return value.trim();
}

function asInt(value: unknown, fallback = 0): number {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.trunc(value);
  }
  if (typeof value === "string") {
    const parsed = Number.parseInt(value.trim(), 10);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }
  return fallback;
}

function asDouble(value: unknown, fallback = 0): number {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === "string") {
    const parsed = Number.parseFloat(value.trim());
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }
  return fallback;
}

function normalizeHostPattern(raw: string): string {
  const normalized = raw.trim().toLowerCase();
  if (normalized.length === 0) {
    return "";
  }
  if (normalized.startsWith("*.")) {
    const suffix = normalized.slice(1);
    if (suffix.length <= 2) {
      return "";
    }
    return `*${suffix}`;
  }
  if (normalized === "googlevideo.com" || normalized.endsWith(".googlevideo.com")) {
    return "*.googlevideo.com";
  }
  if (normalized === "youtube.com" || normalized.endsWith(".youtube.com")) {
    return "*.youtube.com";
  }
  if (normalized === "doubleclick.net" || normalized.endsWith(".doubleclick.net")) {
    return "*.doubleclick.net";
  }
  if (
    normalized === "googlesyndication.com" ||
    normalized.endsWith(".googlesyndication.com")
  ) {
    return "*.googlesyndication.com";
  }
  if (
    normalized === "googleadservices.com" ||
    normalized.endsWith(".googleadservices.com")
  ) {
    return "*.googleadservices.com";
  }
  return normalized;
}

function normalizeSourceHost(raw: string): string {
  const normalized = raw.trim().toLowerCase();
  if (normalized.length === 0) {
    return "";
  }
  if (normalized === "youtube.com" || normalized.endsWith(".youtube.com")) {
    return "*.youtube.com";
  }
  return normalized;
}

function normalizePathPattern(raw: string): string {
  const normalized = raw.trim().toLowerCase();
  if (normalized.length === 0) {
    return "/";
  }
  return normalized.slice(0, 180);
}

function normalizeMarkerKeys(raw: unknown): string[] {
  const values = Array.isArray(raw) ? raw : [];
  const keys = new Set<string>();
  for (const value of values) {
    const key = String(value ?? "").trim().toLowerCase();
    if (key.length === 0) {
      continue;
    }
    if (MARKER_ALLOWLIST.has(key) || (key.startsWith("ad") && key.length <= 36)) {
      keys.add(key);
    }
    if (keys.size >= 24) {
      break;
    }
  }
  return [...keys].sort();
}

function isAllowedHostPattern(pattern: string): boolean {
  if (pattern.length === 0) {
    return false;
  }
  const normalized = pattern.startsWith("*.") ? pattern.slice(1) : pattern;
  return HOST_SUFFIX_ALLOWLIST.some((suffix) => normalized.endsWith(suffix));
}

function boolValue(value: unknown): boolean {
  if (typeof value === "boolean") {
    return value;
  }
  if (typeof value === "number") {
    return value !== 0;
  }
  if (typeof value === "string") {
    const normalized = value.trim().toLowerCase();
    return normalized === "1" || normalized === "true";
  }
  return false;
}

function canonicalHash(candidate: {
  resourceType: string;
  hostPattern: string;
  pathPattern: string;
  sourceHost: string;
  markerKeys: string[];
  requireAdSignal: boolean;
  baseReason: string;
}): string {
  const canonical = JSON.stringify({
    resourceType: candidate.resourceType,
    hostPattern: candidate.hostPattern,
    pathPattern: candidate.pathPattern,
    sourceHost: candidate.sourceHost,
    markerKeys: [...candidate.markerKeys].sort(),
    requireAdSignal: candidate.requireAdSignal,
    baseReason: candidate.baseReason,
  });
  return createHash("sha256").update(canonical, "utf8").digest("hex");
}

function sanitizeCandidate(raw: unknown, nowMs: number): SanitizedCandidate | null {
  const input = asRecord(raw);

  const resourceType = asString(input.resourceType).toLowerCase();
  if (!RESOURCE_TYPES.has(resourceType)) {
    return null;
  }

  const baseReason = asString(input.baseReason).toLowerCase();
  if (!BASE_REASON_ALLOWLIST.has(baseReason)) {
    return null;
  }

  const hostPattern = normalizeHostPattern(asString(input.hostPattern));
  if (!isAllowedHostPattern(hostPattern)) {
    return null;
  }

  const pathPattern = normalizePathPattern(asString(input.pathPattern));
  const sourceHost = normalizeSourceHost(asString(input.sourceHost));
  const markerKeys = normalizeMarkerKeys(input.markerKeys);
  if (markerKeys.length === 0) {
    return null;
  }

  const requireAdSignal = boolValue(input.requireAdSignal);
  const confidenceRaw = asDouble(input.confidence, 0);
  const confidence = Math.max(0, Math.min(1, confidenceRaw));
  const scoreRaw = asDouble(input.score, 0);
  const score = Math.max(0, Math.min(100, scoreRaw));
  if (confidence < 0.72 || score < 60) {
    return null;
  }

  const createdAtMsRaw = asInt(input.createdAtMs, nowMs);
  const createdAtMs = createdAtMsRaw > 0 ? createdAtMsRaw : nowMs;
  const clientEventIdRaw = asInt(input.clientEventId, -1);
  const clientEventId = clientEventIdRaw >= 0 ? clientEventIdRaw : null;

  const sigHash = canonicalHash({
    resourceType,
    hostPattern,
    pathPattern,
    sourceHost,
    markerKeys,
    requireAdSignal,
    baseReason,
  });

  return {
    clientEventId,
    sigHash,
    resourceType,
    hostPattern,
    pathPattern,
    sourceHost,
    markerKeys,
    requireAdSignal,
    baseReason,
    confidence,
    score,
    createdAtMs,
  };
}

function uidHash(uid: string): string {
  return createHash("sha256")
    .update(`${uid}:${PROJECT_SALT}`, "utf8")
    .digest("hex")
    .slice(0, 24);
}

function dayToken(timestampMs: number): string {
  const date = new Date(timestampMs);
  const year = date.getUTCFullYear();
  const month = String(date.getUTCMonth() + 1).padStart(2, "0");
  const day = String(date.getUTCDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function toInt(value: unknown): number {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.trunc(value);
  }
  if (typeof value === "string") {
    const parsed = Number.parseInt(value, 10);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }
  return 0;
}

function toNumber(value: unknown): number {
  if (typeof value === "number" && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === "string") {
    const parsed = Number.parseFloat(value);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }
  return 0;
}

function asStringArray(raw: unknown): string[] {
  if (!Array.isArray(raw)) {
    return [];
  }
  return raw
    .map((value) => String(value ?? "").trim())
    .filter((value) => value.length > 0);
}

async function enforceRateLimit(uid: string, nowMs: number): Promise<void> {
  const ref = crowdRateLimitCollection.doc(uid);
  const nowDay = dayToken(nowMs);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? asRecord(snap.data()) : {};
    const windowStartMs = toInt(data.windowStartMs);
    const countInWindow = toInt(data.countInWindow);
    const dayCounterDay = asString(data.dayCounterDay);
    const dayCounter = toInt(data.dayCounter);

    const isSameWindow =
      windowStartMs > 0 && nowMs - windowStartMs < 60 * 1000;
    const nextCountInWindow = isSameWindow ? countInWindow + 1 : 1;
    if (nextCountInWindow > MAX_SUBMITS_PER_MINUTE) {
      throw new HttpsError(
        "resource-exhausted",
        "Rate limit exceeded. Please retry later."
      );
    }

    const nextDayCounter = dayCounterDay === nowDay ? dayCounter + 1 : 1;
    if (nextDayCounter > MAX_EVENTS_PER_UID_PER_DAY) {
      throw new HttpsError(
        "resource-exhausted",
        "Daily submission limit exceeded."
      );
    }

    tx.set(
      ref,
      {
        uidHash: uidHash(uid),
        windowStartMs: isSameWindow ? windowStartMs : nowMs,
        countInWindow: nextCountInWindow,
        dayCounterDay: nowDay,
        dayCounter: nextDayCounter,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );
  });
}

function confidencePenalty(candidate: SanitizedCandidate): number {
  let penalty = 0;
  if (!candidate.requireAdSignal && candidate.baseReason === "engine_match") {
    penalty += 1;
  }
  if (candidate.markerKeys.length <= 1) {
    penalty += 1;
  }
  if (candidate.pathPattern === "/") {
    penalty += 1;
  }
  return penalty;
}

export const submitAdCandidate = onCall(async (request) => {
  const uid = ensureAuthenticated(request);
  const nowMs = Date.now();
  await enforceRateLimit(uid, nowMs);

  const payload = asRecord(request.data);
  const rawCandidates = Array.isArray(payload.candidates) ? payload.candidates : [];
  if (rawCandidates.length === 0) {
    return {
      acceptedCount: 0,
      rejectedCount: 0,
      acceptedIds: [] as number[],
      rejectedIds: [] as number[],
    };
  }
  if (rawCandidates.length > MAX_CANDIDATES_PER_SUBMIT) {
    throw new HttpsError("invalid-argument", "Too many candidates.");
  }

  const acceptedIds: number[] = [];
  const rejectedIds: number[] = [];
  let acceptedCount = 0;
  let rejectedCount = 0;
  const reporterHash = uidHash(uid);
  const nowDay = dayToken(nowMs);

  for (const rawCandidate of rawCandidates) {
    const sanitized = sanitizeCandidate(rawCandidate, nowMs);
    if (sanitized == null) {
      rejectedCount += 1;
      const rawMap = asRecord(rawCandidate);
      const localId = asInt(rawMap.clientEventId, -1);
      if (localId >= 0) {
        rejectedIds.push(localId);
      }
      continue;
    }

    const candidateRef = adCandidatesCollection.doc(sanitized.sigHash);
    const reportRef = adCandidateReportsCollection.doc();

    try {
      await db.runTransaction(async (tx) => {
        const candidateSnap = await tx.get(candidateRef);
        const existing = candidateSnap.exists ? asRecord(candidateSnap.data()) : {};

        const existingReporterHashes = new Set<string>(
          asStringArray(existing.reporterHashes).slice(0, 80)
        );
        const existingDayTokens = new Set<string>(
          asStringArray(existing.dayTokens).slice(0, 30)
        );

        existingReporterHashes.add(reporterHash);
        existingDayTokens.add(nowDay);

        const previousEvidence = toInt(existing.evidenceCount);
        const nextEvidence = previousEvidence + 1;
        const previousScore = toNumber(existing.avgScore);
        const previousConfidence = toNumber(existing.avgConfidence);
        const nextAvgScore =
          previousEvidence <= 0 ?
            sanitized.score :
            (previousScore * previousEvidence + sanitized.score) / nextEvidence;
        const nextAvgConfidence =
          previousEvidence <= 0 ?
            sanitized.confidence :
            (previousConfidence * previousEvidence + sanitized.confidence) / nextEvidence;
        const falsePositiveCount = toInt(existing.falsePositiveCount);
        const suspiciousScore =
          toInt(existing.suspiciousScore) + confidencePenalty(sanitized);

        const existingState = asString(existing.state, "candidate").toLowerCase();
        const nextState: CandidateState =
          existingState === "quarantined" ? "quarantined" : "candidate";

        tx.set(
          candidateRef,
          {
            sigHash: sanitized.sigHash,
            resourceType: sanitized.resourceType,
            hostPattern: sanitized.hostPattern,
            pathPattern: sanitized.pathPattern,
            sourceHost: sanitized.sourceHost,
            markerKeys: sanitized.markerKeys,
            requireAdSignal: sanitized.requireAdSignal,
            baseReason: sanitized.baseReason,
            state: nextState,
            quarantined: nextState === "quarantined",
            evidenceCount: nextEvidence,
            falsePositiveCount,
            suspiciousScore,
            reporterHashes: [...existingReporterHashes].slice(0, 80),
            dayTokens: [...existingDayTokens].slice(-30),
            uniqueReporterCount: existingReporterHashes.size,
            activeDayCount: existingDayTokens.size,
            avgScore: nextAvgScore,
            avgConfidence: nextAvgConfidence,
            firstSeenAtMs:
              toInt(existing.firstSeenAtMs) > 0 ?
                toInt(existing.firstSeenAtMs) :
                sanitized.createdAtMs,
            lastSeenAtMs: nowMs,
            expireAtMs: nowMs + CANDIDATE_TTL_DAYS * 24 * 60 * 60 * 1000,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          {merge: true}
        );

        tx.set(reportRef, {
          sigHash: sanitized.sigHash,
          reporterUidHash: reporterHash,
          clientEventId: sanitized.clientEventId,
          candidate: {
            resourceType: sanitized.resourceType,
            hostPattern: sanitized.hostPattern,
            pathPattern: sanitized.pathPattern,
            sourceHost: sanitized.sourceHost,
            markerKeys: sanitized.markerKeys,
            requireAdSignal: sanitized.requireAdSignal,
            baseReason: sanitized.baseReason,
            confidence: sanitized.confidence,
            score: sanitized.score,
          },
          accepted: true,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          createdAtMs: nowMs,
        });
      });

      acceptedCount += 1;
      if (sanitized.clientEventId != null) {
        acceptedIds.push(sanitized.clientEventId);
      }
    } catch (error) {
      rejectedCount += 1;
      if (sanitized.clientEventId != null) {
        rejectedIds.push(sanitized.clientEventId);
      }
      logger.warn("submitAdCandidate transaction failed", {
        uidHash: reporterHash,
        sigHash: sanitized.sigHash,
        error,
      });
    }
  }

  return {
    acceptedCount,
    rejectedCount,
    acceptedIds,
    rejectedIds,
  };
});

export const fetchSignatureManifest = onCall(async (request) => {
  ensureAuthenticated(request);
  const payload = asRecord(request.data);
  const currentVersion = Math.max(0, asInt(payload.currentVersion, 0));
  const metaSnap = await crowdMetaDoc.get();
  if (!metaSnap.exists) {
    return {
      upToDate: true,
      version: 0,
      checksum: "",
      storagePath: "",
      downloadUrl: "",
      createdAtMs: 0,
      signatureCount: 0,
    };
  }

  const meta = asRecord(metaSnap.data());
  const version = Math.max(0, toInt(meta.version));
  const checksum = asString(meta.checksum);
  const storagePath = asString(meta.storagePath);
  const signatureCount = Math.max(0, toInt(meta.signatureCount));
  const createdAtMs = Math.max(0, toInt(meta.createdAtMs));

  if (version <= 0 || storagePath.length === 0 || version <= currentVersion) {
    return {
      upToDate: true,
      version,
      checksum,
      storagePath,
      downloadUrl: "",
      createdAtMs,
      signatureCount,
    };
  }

  let downloadUrl = "";
  try {
    const file = storageBucket.file(storagePath);
    const [signedUrl] = await file.getSignedUrl({
      action: "read",
      expires: Date.now() + 15 * 60 * 1000,
      version: "v4",
    });
    downloadUrl = signedUrl;
  } catch (error) {
    logger.error("fetchSignatureManifest signed URL failed", {error, storagePath});
    throw new HttpsError("internal", "Unable to prepare snapshot URL.");
  }

  return {
    upToDate: false,
    version,
    checksum,
    storagePath,
    downloadUrl,
    createdAtMs,
    signatureCount,
  };
});

export const aggregateCandidates = onSchedule("every 15 minutes", async () => {
  const nowMs = Date.now();
  const querySnap = await adCandidatesCollection
    .where("state", "in", ["candidate", "learning"])
    .orderBy("updatedAt", "asc")
    .limit(450)
    .get();

  if (querySnap.empty) {
    return;
  }

  const batch = db.batch();
  let promotedCount = 0;
  let quarantinedCount = 0;
  let expiredCount = 0;

  for (const doc of querySnap.docs) {
    const data = asRecord(doc.data());
    const state = asString(data.state, "candidate").toLowerCase();
    if (state !== "candidate" && state !== "learning") {
      continue;
    }

    const sigHash = asString(data.sigHash, doc.id);
    const evidenceCount = Math.max(0, toInt(data.evidenceCount));
    const uniqueReporterCount = Math.max(0, toInt(data.uniqueReporterCount));
    const activeDayCount = Math.max(0, toInt(data.activeDayCount));
    const falsePositiveCount = Math.max(0, toInt(data.falsePositiveCount));
    const suspiciousScore = Math.max(0, toInt(data.suspiciousScore));
    const avgConfidence = Math.max(0, Math.min(1, toNumber(data.avgConfidence)));
    const avgScore = Math.max(0, Math.min(100, toNumber(data.avgScore)));
    const firstSeenAtMs = Math.max(0, toInt(data.firstSeenAtMs));
    const lastSeenAtMs = Math.max(0, toInt(data.lastSeenAtMs));
    const ageMs = firstSeenAtMs > 0 ? nowMs - firstSeenAtMs : 0;

    const shouldQuarantine =
      falsePositiveCount >= 3 || suspiciousScore >= 8 || avgConfidence < 0.7;
    const shouldPromote =
      !shouldQuarantine &&
      evidenceCount >= 12 &&
      uniqueReporterCount >= 3 &&
      activeDayCount >= 2 &&
      avgConfidence >= 0.86 &&
      avgScore >= 82;
    const shouldExpire =
      !shouldPromote &&
      ageMs > CANDIDATE_TTL_DAYS * 24 * 60 * 60 * 1000 &&
      evidenceCount < 6;

    if (shouldPromote) {
      const expireAtMs = nowMs + ACTIVE_SIGNATURE_TTL_DAYS * 24 * 60 * 60 * 1000;
      batch.set(
        adSignaturesCollection.doc(sigHash),
        {
          sigHash,
          hostPattern: asString(data.hostPattern),
          pathPattern: asString(data.pathPattern),
          resourceType: asString(data.resourceType),
          sourceHost: asString(data.sourceHost),
          markerKeys: normalizeMarkerKeys(data.markerKeys),
          requireAdSignal: boolValue(data.requireAdSignal),
          state: "active",
          source: "cloud",
          score: avgScore,
          confidence: avgConfidence,
          seenCount: evidenceCount,
          falsePositiveCount,
          firstSeenAtMs,
          lastSeenAtMs,
          expireAtMs,
          updatedAtMs: nowMs,
          lastReason: asString(data.baseReason),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
      batch.set(
        doc.ref,
        {
          state: "active",
          quarantined: false,
          promotedAtMs: nowMs,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
      promotedCount += 1;
      continue;
    }

    if (shouldQuarantine) {
      batch.set(
        doc.ref,
        {
          state: "quarantined",
          quarantined: true,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
      batch.set(
        adSignaturesCollection.doc(sigHash),
        {
          state: "quarantined",
          quarantined: true,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
      quarantinedCount += 1;
      continue;
    }

    if (shouldExpire) {
      batch.set(
        doc.ref,
        {
          state: "expired",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
      expiredCount += 1;
    }
  }

  if (promotedCount > 0 || quarantinedCount > 0 || expiredCount > 0) {
    await batch.commit();
    await crowdMetaDoc.set(
      {
        aggregateLastRunAt: admin.firestore.FieldValue.serverTimestamp(),
        aggregateLastRunMs: nowMs,
        aggregateStats: {
          promotedCount,
          quarantinedCount,
          expiredCount,
        },
      },
      {merge: true}
    );
  }
});

async function publishSnapshotInternal(trigger: string, actor: string): Promise<{
  version: number;
  checksum: string;
  storagePath: string;
  signatureCount: number;
}> {
  const nowMs = Date.now();
  const signaturesSnap = await adSignaturesCollection
    .where("state", "==", "active")
    .orderBy("updatedAt", "desc")
    .limit(6000)
    .get();

  const signatureDocs = signaturesSnap.docs.map((doc) => asRecord(doc.data()));
  const signatures = signatureDocs.map((entry) => {
    const markerKeys = normalizeMarkerKeys(entry.markerKeys);
    return {
      sigHash: asString(entry.sigHash),
      hostPattern: asString(entry.hostPattern),
      pathPattern: asString(entry.pathPattern),
      resourceType: asString(entry.resourceType),
      sourceHost: asString(entry.sourceHost),
      markerKeys,
      requireAdSignal: boolValue(entry.requireAdSignal),
      state: "active",
      source: "cloud",
      score: Math.max(0, Math.min(100, toNumber(entry.score))),
      confidence: Math.max(0, Math.min(1, toNumber(entry.confidence))),
      seenCount: Math.max(0, toInt(entry.seenCount)),
      falsePositiveCount: Math.max(0, toInt(entry.falsePositiveCount)),
      firstSeenAtMs: Math.max(0, toInt(entry.firstSeenAtMs)),
      lastSeenAtMs: Math.max(0, toInt(entry.lastSeenAtMs)),
      expireAtMs: Math.max(0, toInt(entry.expireAtMs)),
      updatedAtMs: nowMs,
      lastReason: asString(entry.lastReason),
    };
  });

  signatures.sort((left, right) => right.score - left.score);
  const payloadChecksum = createHash("sha256")
    .update(JSON.stringify(signatures), "utf8")
    .digest("hex");

  const metaSnap = await crowdMetaDoc.get();
  const meta = metaSnap.exists ? asRecord(metaSnap.data()) : {};
  const previousVersion = Math.max(0, toInt(meta.version));
  const version = previousVersion + 1;
  const storagePath = `crowd-signatures/snapshots/v${version}.json.gz`;

  const snapshot = {
    version,
    createdAt: new Date(nowMs).toISOString(),
    createdAtMs: nowMs,
    checksum: payloadChecksum,
    signatures,
  };

  const snapshotBytes = Buffer.from(JSON.stringify(snapshot), "utf8");
  const checksum = createHash("sha256").update(snapshotBytes).digest("hex");
  const compressed = gzipSync(snapshotBytes);

  const file = storageBucket.file(storagePath);
  await file.save(compressed, {
    resumable: false,
    contentType: "application/json",
    metadata: {
      contentEncoding: "gzip",
      metadata: {
        checksum,
        payloadChecksum,
      },
      cacheControl: "public,max-age=300",
    },
  });

  await crowdMetaDoc.set(
    {
      version,
      checksum,
      payloadChecksum,
      storagePath,
      signatureCount: signatures.length,
      createdAtMs: nowMs,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedBy: actor,
      updateTrigger: trigger,
    },
    {merge: true}
  );

  await crowdSnapshotHistoryCollection.doc(`v${version}`).set({
    version,
    checksum,
    payloadChecksum,
    storagePath,
    signatureCount: signatures.length,
    createdAtMs: nowMs,
    createdBy: actor,
    createdFrom: trigger,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {
    version,
    checksum,
    storagePath,
    signatureCount: signatures.length,
  };
}

export const publishSignatureSnapshotScheduled = onSchedule(
  "every 60 minutes",
  async () => {
    try {
      const result = await publishSnapshotInternal(
        "scheduled",
        "system_scheduler"
      );
      logger.info("publishSignatureSnapshotScheduled success", result);
    } catch (error) {
      logger.error("publishSignatureSnapshotScheduled failed", {error});
      throw error;
    }
  }
);

export const publishSignatureSnapshot = onCall(async (request) => {
  const adminUid = ensureAdmin(request);
  const result = await publishSnapshotInternal("admin_call", adminUid);
  return {
    resultCode: "OK",
    ...result,
  };
});

export const quarantineSignature = onCall(async (request) => {
  const adminUid = ensureAdmin(request);
  const payload = asRecord(request.data);
  const sigHash = asString(payload.sigHash).toLowerCase();
  const note = asString(payload.note);
  if (sigHash.length !== 64) {
    throw new HttpsError("invalid-argument", "Invalid sigHash.");
  }

  await adSignaturesCollection.doc(sigHash).set(
    {
      state: "quarantined",
      quarantined: true,
      quarantineReason: note.length > 0 ? note : "admin_quarantine",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAtMs: Date.now(),
    },
    {merge: true}
  );

  await adCandidatesCollection.doc(sigHash).set(
    {
      state: "quarantined",
      quarantined: true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedBy: adminUid,
    },
    {merge: true}
  );

  await adCandidateReportsCollection.add({
    sigHash,
    action: "quarantine_signature",
    note,
    createdBy: adminUid,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {resultCode: "OK", sigHash};
});

export const rollbackSnapshot = onCall(async (request) => {
  const adminUid = ensureAdmin(request);
  const payload = asRecord(request.data);
  let targetVersion = Math.max(0, asInt(payload.version, 0));

  if (targetVersion <= 0) {
    const historySnap = await crowdSnapshotHistoryCollection
      .orderBy("version", "desc")
      .limit(2)
      .get();
    if (historySnap.size < 2) {
      throw new HttpsError("failed-precondition", "No snapshot to rollback.");
    }
    targetVersion = Math.max(0, toInt(historySnap.docs[1].data().version));
  }

  if (targetVersion <= 0) {
    throw new HttpsError("failed-precondition", "Invalid rollback version.");
  }

  const targetDoc = await crowdSnapshotHistoryCollection.doc(`v${targetVersion}`).get();
  if (!targetDoc.exists) {
    throw new HttpsError("not-found", "Target snapshot version not found.");
  }

  const target = asRecord(targetDoc.data());
  const storagePath = asString(target.storagePath);
  const checksum = asString(target.checksum);
  if (storagePath.length === 0 || checksum.length === 0) {
    throw new HttpsError("failed-precondition", "Target snapshot is invalid.");
  }

  await crowdMetaDoc.set(
    {
      version: Math.max(0, toInt(target.version)),
      checksum,
      payloadChecksum: asString(target.payloadChecksum),
      storagePath,
      signatureCount: Math.max(0, toInt(target.signatureCount)),
      createdAtMs: Math.max(0, toInt(target.createdAtMs)),
      rollbackAt: admin.firestore.FieldValue.serverTimestamp(),
      rollbackBy: adminUid,
      rollbackFrom: "admin_call",
    },
    {merge: true}
  );

  await adCandidateReportsCollection.add({
    action: "rollback_snapshot",
    rollbackToVersion: targetVersion,
    createdBy: adminUid,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {
    resultCode: "OK",
    version: Math.max(0, toInt(target.version)),
    checksum,
    storagePath,
  };
});
