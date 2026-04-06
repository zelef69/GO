import {
  HttpsError,
  CallableRequest,
  onCall,
} from "firebase-functions/v2/https";
import {setGlobalOptions} from "firebase-functions/v2";
import {logger} from "firebase-functions";
import {admin, db} from "./lib/firebase";

setGlobalOptions({maxInstances: 20});
const usersCollection = db.collection("users");

const DEFAULT_PLAN = "default";
const DEFAULT_MAX_DEVICES = 10;

type SubscriptionStatus = "active" | "expired" | "blocked";
type ValidationCode =
  | "OK"
  | "EXPIRED"
  | "BLOCKED"
  | "DEVICE_REVOKED"
  | "VERSION_MISMATCH"
  | "SESSION_NOT_FOUND";

interface SubscriptionState {
  plan: string;
  status: SubscriptionStatus;
  startAt: Date;
  expireAt: Date;
  maxDevices: number;
  extraDays: number;
  version: number;
}

function asRecord(value: unknown): Record<string, unknown> {
  if (typeof value == "object" && value != null) {
    return value as Record<string, unknown>;
  }
  return {};
}

function asTrimmedString(value: unknown, fallback = ""): string {
  if (typeof value != "string") {
    return fallback;
  }
  return value.trim();
}

function asPositiveInt(value: unknown, fallback: number): number {
  if (typeof value == "number" && Number.isFinite(value)) {
    const integerValue = Math.floor(value);
    return integerValue > 0 ? integerValue : fallback;
  }
  if (typeof value == "string") {
    const parsed = Number.parseInt(value.trim(), 10);
    if (Number.isFinite(parsed) && parsed > 0) {
      return parsed;
    }
  }
  return fallback;
}

function asNonNegativeInt(value: unknown, fallback = 0): number {
  if (typeof value == "number" && Number.isFinite(value)) {
    const integerValue = Math.floor(value);
    return integerValue >= 0 ? integerValue : fallback;
  }
  if (typeof value == "string") {
    const parsed = Number.parseInt(value.trim(), 10);
    if (Number.isFinite(parsed) && parsed >= 0) {
      return parsed;
    }
  }
  return fallback;
}

function toDate(value: unknown): Date | null {
  if (value instanceof admin.firestore.Timestamp) {
    return value.toDate();
  }
  if (value instanceof Date) {
    return value;
  }
  if (typeof value == "string") {
    const parsed = new Date(value);
    if (!Number.isNaN(parsed.getTime())) {
      return parsed;
    }
  }
  return null;
}

function addDays(base: Date, days: number): Date {
  return new Date(base.getTime() + days * 24 * 60 * 60 * 1000);
}

function serializeError(error: unknown): Record<string, unknown> {
  if (error instanceof HttpsError) {
    return {
      errorName: error.name,
      errorCode: error.code,
      errorMessage: error.message,
      errorDetails: error.details,
    };
  }
  if (error instanceof Error) {
    return {
      errorName: error.name,
      errorMessage: error.message,
      errorStack: error.stack,
    };
  }
  const asMap = asRecord(error);
  if (Object.keys(asMap).length > 0) {
    return {error: asMap};
  }
  return {errorValue: String(error)};
}

function appError(
  code: string,
  message: string,
  extraDetails: Record<string, unknown> = {}
): HttpsError {
  return new HttpsError("failed-precondition", message, {
    code,
    ...extraDetails,
  });
}

function getUid(request: CallableRequest<unknown>): string {
  const uid = request.auth?.uid ?? "";
  if (uid.length == 0) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  return uid;
}

function requireAdmin(request: CallableRequest<unknown>): string {
  const uid = getUid(request);
  if (request.auth?.token?.admin == true) {
    return uid;
  }
  throw new HttpsError("permission-denied", "Admin role required.");
}

function normalizeSubscriptionStatus(
  rawStatus: string,
  expireAt: Date,
  now: Date
): SubscriptionStatus {
  const normalized = rawStatus.toLowerCase();
  if (normalized == "blocked") {
    return "blocked";
  }
  if (!(expireAt.getTime() > now.getTime())) {
    return "expired";
  }
  if (normalized == "expired") {
    return "expired";
  }
  return "active";
}

function readSubscriptionState(
  userData: Record<string, unknown>,
  now: Date
): SubscriptionState {
  const subscriptionData = asRecord(userData["subscription"]);
  const startAt =
    toDate(subscriptionData["startAt"]) ??
    toDate(userData["createdAt"]) ??
    now;
  const expireAt = toDate(subscriptionData["expireAt"]) ?? startAt;
  const rawStatus = asTrimmedString(subscriptionData["status"], "active");
  const status = normalizeSubscriptionStatus(rawStatus, expireAt, now);
  return {
    plan: asTrimmedString(subscriptionData["plan"], DEFAULT_PLAN),
    status,
    startAt,
    expireAt,
    maxDevices: asPositiveInt(
      subscriptionData["maxDevices"],
      DEFAULT_MAX_DEVICES
    ),
    extraDays: asNonNegativeInt(subscriptionData["extraDays"], 0),
    version: asPositiveInt(subscriptionData["version"], 1),
  };
}

function userProfileFromAuth(request: CallableRequest<unknown>): {
  email: string;
  displayName: string;
  photoURL: string;
} {
  const token = asRecord(request.auth?.token);
  return {
    email: asTrimmedString(token["email"], ""),
    displayName: asTrimmedString(token["name"], ""),
    photoURL: asTrimmedString(token["picture"], ""),
  };
}

async function upsertUserProfileAndDefaults(
  tx: FirebaseFirestore.Transaction,
  uid: string,
  profile: {email: string; displayName: string; photoURL: string},
  now: Date
): Promise<{
  ref: FirebaseFirestore.DocumentReference<FirebaseFirestore.DocumentData>;
  data: Record<string, unknown>;
  subscription: SubscriptionState;
}> {
  const userRef = usersCollection.doc(uid);
  const userSnap = await tx.get(userRef);

  if (!userSnap.exists) {
    const createdAt = now;
    const initialExpireAt = createdAt;
    tx.set(
      userRef,
      {
        email: profile.email,
        displayName: profile.displayName,
        photoURL: profile.photoURL,
        subscription: {
          plan: DEFAULT_PLAN,
          status: "active",
          startAt: admin.firestore.Timestamp.fromDate(createdAt),
          expireAt: admin.firestore.Timestamp.fromDate(initialExpireAt),
          maxDevices: DEFAULT_MAX_DEVICES,
          extraDays: 0,
          version: 1,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedBy: "system_init",
        },
        stats: {
          activeDeviceCount: 0,
        },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );
    return {
      ref: userRef,
      data: {
        email: profile.email,
        displayName: profile.displayName,
        photoURL: profile.photoURL,
        subscription: {
          plan: DEFAULT_PLAN,
          status: "active",
          startAt: now,
          expireAt: initialExpireAt,
          maxDevices: DEFAULT_MAX_DEVICES,
          extraDays: 0,
          version: 1,
        },
        stats: {
          activeDeviceCount: 0,
        },
      },
      subscription: {
        plan: DEFAULT_PLAN,
        status: "active",
        startAt: createdAt,
        expireAt: initialExpireAt,
        maxDevices: DEFAULT_MAX_DEVICES,
        extraDays: 0,
        version: 1,
      },
    };
  }

  const currentData = asRecord(userSnap.data());
  const subscription = readSubscriptionState(currentData, now);
  tx.set(
    userRef,
    {
      email: profile.email,
      displayName: profile.displayName,
      photoURL: profile.photoURL,
      subscription: {
        plan: subscription.plan,
        startAt: admin.firestore.Timestamp.fromDate(subscription.startAt),
        expireAt: admin.firestore.Timestamp.fromDate(subscription.expireAt),
        maxDevices: subscription.maxDevices,
        extraDays: subscription.extraDays,
        version: subscription.version,
        status: subscription.status,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge: true}
  );
  return {
    ref: userRef,
    data: currentData,
    subscription,
  };
}

function getDevicePayload(data: unknown): {
  sessionId: string;
  deviceId: string;
  deviceName: string;
  platform: string;
  model: string;
  appVersion: string;
} {
  const payload = asRecord(data);
  return {
    sessionId: asTrimmedString(payload["sessionId"]),
    deviceId: asTrimmedString(payload["deviceId"]),
    deviceName: asTrimmedString(payload["deviceName"], "unknown-device"),
    platform: asTrimmedString(payload["platform"], "unknown-platform"),
    model: asTrimmedString(payload["model"], "unknown-model"),
    appVersion: asTrimmedString(payload["appVersion"], "unknown"),
  };
}

export const registerDeviceSession = onCall(async (request) => {
  const uid = getUid(request);
  const payload = getDevicePayload(request.data);
  if (payload.deviceId.length == 0) {
    throw new HttpsError("invalid-argument", "deviceId is required.");
  }

  const profile = userProfileFromAuth(request);
  try {
    const result = await db.runTransaction(async (tx) => {
      const now = new Date();
      const userRef = usersCollection.doc(uid);
      const userSnap = await tx.get(userRef);

      const isNewUser = !userSnap.exists;
      const subscription = isNewUser ?
        {
          plan: DEFAULT_PLAN,
          status: "active" as SubscriptionStatus,
          startAt: now,
          expireAt: now,
          maxDevices: DEFAULT_MAX_DEVICES,
          extraDays: 0,
          version: 1,
        } :
        readSubscriptionState(asRecord(userSnap.data()), now);

      if (subscription.status == "blocked") {
        throw appError("BLOCKED", "Subscription is blocked.");
      }

      const devicesRef = userRef.collection("devices");
      const sameDeviceQuery = devicesRef.where("deviceId", "==", payload.deviceId).limit(1);
      const sameDeviceSnap = await tx.get(sameDeviceQuery);

      const activeQuery = devicesRef
        .where("isActive", "==", true)
        .where("revoked", "==", false);
      const activeSnap = await tx.get(activeQuery);
      let nextActiveCount = activeSnap.size;

      let targetSessionRef: FirebaseFirestore.DocumentReference;
      if (!sameDeviceSnap.empty) {
        targetSessionRef = sameDeviceSnap.docs[0].ref;
        const existingData = asRecord(sameDeviceSnap.docs[0].data());
        const wasActive =
          existingData["isActive"] == true && existingData["revoked"] != true;
        if (!wasActive) {
          if (nextActiveCount >= subscription.maxDevices) {
            throw appError(
              "DEVICE_LIMIT_EXCEEDED",
              "Maximum active devices reached.",
              {maxDevices: subscription.maxDevices}
            );
          }
          nextActiveCount += 1;
        }
      } else {
        if (nextActiveCount >= subscription.maxDevices) {
          throw appError(
            "DEVICE_LIMIT_EXCEEDED",
            "Maximum active devices reached.",
            {maxDevices: subscription.maxDevices}
          );
        }
        targetSessionRef = devicesRef.doc();
        nextActiveCount += 1;
      }

      tx.set(
        targetSessionRef,
        {
          deviceId: payload.deviceId,
          deviceName: payload.deviceName,
          platform: payload.platform,
          model: payload.model,
          appVersion: payload.appVersion,
          loginAt: admin.firestore.FieldValue.serverTimestamp(),
          lastSeenAt: admin.firestore.FieldValue.serverTimestamp(),
          isActive: true,
          revoked: false,
          sessionVersion: subscription.version,
          expireAtSnapshot: admin.firestore.Timestamp.fromDate(
            subscription.expireAt
          ),
        },
        {merge: true}
      );

      tx.set(
        userRef,
        {
          email: profile.email,
          displayName: profile.displayName,
          photoURL: profile.photoURL,
          subscription: {
            plan: subscription.plan,
            status: subscription.status,
            startAt: admin.firestore.Timestamp.fromDate(subscription.startAt),
            expireAt: admin.firestore.Timestamp.fromDate(subscription.expireAt),
            maxDevices: subscription.maxDevices,
            extraDays: subscription.extraDays,
            version: subscription.version,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedBy: uid,
          },
          stats: {
            activeDeviceCount: nextActiveCount,
          },
          ...(isNewUser ?
            {createdAt: admin.firestore.FieldValue.serverTimestamp()} :
            {}),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );

      return {
        sessionId: targetSessionRef.id,
        expireAt: subscription.expireAt.toISOString(),
        maxDevices: subscription.maxDevices,
        version: subscription.version,
      };
    });

    return {
      resultCode: "OK",
      ...result,
    };
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    logger.error("registerDeviceSession failed", {
      uid,
      ...serializeError(error),
    });
    throw new HttpsError("internal", "Unable to register device session.");
  }
});

export const validateDeviceSession = onCall(async (request) => {
  const uid = getUid(request);
  const payload = getDevicePayload(request.data);
  if (payload.sessionId.length == 0 || payload.deviceId.length == 0) {
    throw new HttpsError(
      "invalid-argument",
      "sessionId and deviceId are required."
    );
  }

  try {
    const now = new Date();
    const userRef = usersCollection.doc(uid);
    const userSnap = await userRef.get();
    if (!userSnap.exists) {
      return {resultCode: "SESSION_NOT_FOUND"};
    }
    const userData = asRecord(userSnap.data());
    const subscription = readSubscriptionState(userData, now);

    if (subscription.status == "blocked") {
      return {
        resultCode: "BLOCKED",
        expireAt: subscription.expireAt.toISOString(),
      };
    }

    const sessionRef = userRef.collection("devices").doc(payload.sessionId);
    const sessionSnap = await sessionRef.get();
    if (!sessionSnap.exists) {
      return {resultCode: "SESSION_NOT_FOUND"};
    }
    const sessionData = asRecord(sessionSnap.data());
    if (asTrimmedString(sessionData["deviceId"]) != payload.deviceId) {
      return {resultCode: "SESSION_NOT_FOUND"};
    }
    if (sessionData["revoked"] == true || sessionData["isActive"] != true) {
      return {resultCode: "DEVICE_REVOKED"};
    }

    const sessionVersion = asPositiveInt(sessionData["sessionVersion"], 1);
    if (sessionVersion != subscription.version) {
      return {resultCode: "VERSION_MISMATCH"};
    }

    return {
      resultCode: "OK",
      expireAt: subscription.expireAt.toISOString(),
      version: subscription.version,
      sessionId: payload.sessionId,
    };
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    logger.error("validateDeviceSession failed", {uid, ...serializeError(error)});
    throw new HttpsError("internal", "Unable to validate session.");
  }
});

export const heartbeatDeviceSession = onCall(async (request) => {
  const uid = getUid(request);
  const payload = getDevicePayload(request.data);
  if (payload.sessionId.length == 0 || payload.deviceId.length == 0) {
    throw new HttpsError(
      "invalid-argument",
      "sessionId and deviceId are required."
    );
  }

  try {
    await db.runTransaction(async (tx) => {
      const now = new Date();
      const userRef = usersCollection.doc(uid);
      const userSnap = await tx.get(userRef);
      if (!userSnap.exists) {
        throw appError("SESSION_NOT_FOUND", "User not found.");
      }
      const subscription = readSubscriptionState(asRecord(userSnap.data()), now);
      if (subscription.status == "blocked") {
        throw appError("BLOCKED", "Subscription is blocked.");
      }

      const sessionRef = userRef.collection("devices").doc(payload.sessionId);
      const sessionSnap = await tx.get(sessionRef);
      if (!sessionSnap.exists) {
        throw appError("SESSION_NOT_FOUND", "Session not found.");
      }
      const sessionData = asRecord(sessionSnap.data());
      if (asTrimmedString(sessionData["deviceId"]) != payload.deviceId) {
        throw appError("SESSION_NOT_FOUND", "Session not found.");
      }
      if (sessionData["revoked"] == true || sessionData["isActive"] != true) {
        throw appError("DEVICE_REVOKED", "Session is revoked.");
      }

      tx.set(
        sessionRef,
        {
          lastSeenAt: admin.firestore.FieldValue.serverTimestamp(),
          appVersion: payload.appVersion,
          model: payload.model,
          platform: payload.platform,
        },
        {merge: true}
      );
    });

    return {resultCode: "OK"};
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    logger.error("heartbeatDeviceSession failed", {
      uid,
      ...serializeError(error),
    });
    throw new HttpsError("internal", "Unable to update heartbeat.");
  }
});

export const logoutDeviceSession = onCall(async (request) => {
  const uid = getUid(request);
  const payload = getDevicePayload(request.data);
  if (payload.sessionId.length == 0) {
    throw new HttpsError("invalid-argument", "sessionId is required.");
  }

  try {
    await db.runTransaction(async (tx) => {
      const userRef = usersCollection.doc(uid);
      const sessionRef = userRef.collection("devices").doc(payload.sessionId);
      const sessionSnap = await tx.get(sessionRef);

      let wasActive = false;
      if (sessionSnap.exists) {
        const sessionData = asRecord(sessionSnap.data());
        if (
          payload.deviceId.length > 0 &&
          asTrimmedString(sessionData["deviceId"]) != payload.deviceId
        ) {
          throw appError("SESSION_NOT_FOUND", "Session not found.");
        }
        wasActive =
          sessionData["isActive"] == true && sessionData["revoked"] != true;
      }

      const activeQuery = userRef
        .collection("devices")
        .where("isActive", "==", true)
        .where("revoked", "==", false);
      const activeSnap = await tx.get(activeQuery);
      let nextActiveCount = activeSnap.size;
      if (wasActive) {
        nextActiveCount -= 1;
      }
      if (nextActiveCount < 0) {
        nextActiveCount = 0;
      }

      if (sessionSnap.exists) {
        tx.set(
          sessionRef,
          {
            isActive: false,
            revoked: true,
            lastSeenAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          {merge: true}
        );
      }

      tx.set(
        userRef,
        {
          stats: {
            activeDeviceCount: nextActiveCount,
          },
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
    });

    return {resultCode: "OK"};
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    logger.error("logoutDeviceSession failed", {uid, ...serializeError(error)});
    throw new HttpsError("internal", "Unable to logout session.");
  }
});

export const addSubscriptionDays = onCall(async (request) => {
  const adminUid = requireAdmin(request);
  const payload = asRecord(request.data);
  const targetUid = asTrimmedString(payload["uid"]);
  const days = asPositiveInt(payload["days"], 0);
  const note = asTrimmedString(payload["note"]);

  if (targetUid.length == 0) {
    throw new HttpsError("invalid-argument", "uid is required.");
  }
  if (days <= 0) {
    throw new HttpsError("invalid-argument", "days must be greater than 0.");
  }

  try {
    const result = await db.runTransaction(async (tx) => {
      const now = new Date();
      const userRef = usersCollection.doc(targetUid);
      const userSnap = await tx.get(userRef);
      if (!userSnap.exists) {
        throw new HttpsError("not-found", "Target user does not exist.");
      }

      const subscription = readSubscriptionState(asRecord(userSnap.data()), now);
      const beforeExpireAt = subscription.expireAt;
      const base = beforeExpireAt.getTime() > now.getTime() ? beforeExpireAt : now;
      const afterExpireAt = addDays(base, days);
      const nextExtraDays = subscription.extraDays + days;

      tx.set(
        userRef,
        {
          subscription: {
            status: "active",
            expireAt: admin.firestore.Timestamp.fromDate(afterExpireAt),
            extraDays: nextExtraDays,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedBy: adminUid,
          },
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );

      const logRef = userRef.collection("logs").doc();
      tx.set(logRef, {
        action: "add_subscription_days",
        days,
        note,
        beforeExpireAt: admin.firestore.Timestamp.fromDate(beforeExpireAt),
        afterExpireAt: admin.firestore.Timestamp.fromDate(afterExpireAt),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        createdBy: adminUid,
      });

      return {
        expireAt: afterExpireAt.toISOString(),
        extraDays: nextExtraDays,
      };
    });

    return {
      resultCode: "OK",
      ...result,
    };
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    logger.error("addSubscriptionDays failed", {
      adminUid,
      targetUid,
      ...serializeError(error),
    });
    throw new HttpsError("internal", "Unable to add subscription days.");
  }
});

export const forceLogoutAllDevices = onCall(async (request) => {
  const adminUid = requireAdmin(request);
  const payload = asRecord(request.data);
  const targetUid = asTrimmedString(payload["uid"]);
  const note = asTrimmedString(payload["note"]);

  if (targetUid.length == 0) {
    throw new HttpsError("invalid-argument", "uid is required.");
  }

  try {
    const result = await db.runTransaction(async (tx) => {
      const now = new Date();
      const userRef = usersCollection.doc(targetUid);
      const userSnap = await tx.get(userRef);
      if (!userSnap.exists) {
        throw new HttpsError("not-found", "Target user does not exist.");
      }

      const subscription = readSubscriptionState(asRecord(userSnap.data()), now);
      const nextVersion = subscription.version + 1;

      tx.set(
        userRef,
        {
          subscription: {
            version: nextVersion,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedBy: adminUid,
          },
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );

      const logRef = userRef.collection("logs").doc();
      tx.set(logRef, {
        action: "force_logout_all_devices",
        days: 0,
        note,
        beforeExpireAt: admin.firestore.Timestamp.fromDate(subscription.expireAt),
        afterExpireAt: admin.firestore.Timestamp.fromDate(subscription.expireAt),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        createdBy: adminUid,
      });

      return {version: nextVersion};
    });

    return {
      resultCode: "OK",
      ...result,
    };
  } catch (error) {
    if (error instanceof HttpsError) {
      throw error;
    }
    logger.error("forceLogoutAllDevices failed", {
      adminUid,
      targetUid,
      ...serializeError(error),
    });
    throw new HttpsError("internal", "Unable to force logout devices.");
  }
});

export const VALIDATION_CODES: ValidationCode[] = [
  "OK",
  "EXPIRED",
  "BLOCKED",
  "DEVICE_REVOKED",
  "VERSION_MISMATCH",
  "SESSION_NOT_FOUND",
];

export {
  submitAdCandidate,
  fetchSignatureManifest,
  aggregateCandidates,
  publishSignatureSnapshot,
  publishSignatureSnapshotScheduled,
  quarantineSignature,
  rollbackSnapshot,
} from "./crowd_signatures";

export {
  createPackageOrder,
  submitManualCorrectionRequest,
  applyManualPackageCorrection,
  verifyPackageSlip,
} from "./package_orders";
