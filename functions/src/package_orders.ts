import {createHash, randomUUID} from "node:crypto";
import {logger} from "firebase-functions";
import {defineSecret} from "firebase-functions/params";
import {
  CallableRequest,
  HttpsError,
  onCall,
} from "firebase-functions/v2/https";
import {admin, db, storage} from "./lib/firebase";
import {ThunderApiError, verifySlipByUrl} from "./lib/thunder";

const thunderApiKey = defineSecret("THUNDER_API_KEY");

const ORDER_STATUS_PENDING = "PENDING";
const ORDER_STATUS_PAID = "PAID";
const ORDER_STATUS_EXPIRED = "EXPIRED";
const ORDER_TTL_MINUTES = 30;
const SLIP_MAX_BYTES = 5 * 1024 * 1024;
const MATCH_ACCOUNT_ENABLED = true;
const CHECK_DUPLICATE_ENABLED = true;
const ORDER_PATH_PREFIX = "orders";
const PAYMENT_PATH_PREFIX = "payments";
const PRODUCT_PATH_PREFIX = "products";
const SLIP_PATH_PREFIX = "slips";
const MANUAL_CORRECTION_REQUEST_PATH_PREFIX = "manual_correction_requests";
const USER_COLLECTION_PATH_PREFIX = "users";
const PURCHASE_HISTORY_PATH_PREFIX = "purchase_history";
const PACKAGE_HISTORY_PATH_PREFIX = "package_history";
const ALLOWED_IMAGE_MIME = /^image\/(jpeg|jpg|png|webp|heic|heif)$/i;
const DAY_IN_MS = 24 * 60 * 60 * 1000;

type OrderStatus =
  | typeof ORDER_STATUS_PENDING
  | typeof ORDER_STATUS_PAID
  | typeof ORDER_STATUS_EXPIRED;

interface ProductData {
  name: string;
  price: number;
  currency: string;
  durationDays: number;
  active: boolean;
}

interface OrderData {
  uid: string;
  packageId: string;
  expectedAmount: number;
  currency: string;
  durationDays: number;
  status: OrderStatus;
  createdAt: FirebaseFirestore.Timestamp;
  expiresAt: FirebaseFirestore.Timestamp;
  slipPath: string | null;
  slipSha256: string | null;
  paymentRef: string | null;
  lastVerifyCode: string | null;
  lastVerifyMessage: string | null;
  lastVerificationAt?: FirebaseFirestore.Timestamp;
  paidAt?: FirebaseFirestore.Timestamp;
}

interface PaymentData {
  uid: string;
  orderId: string;
  packageId: string;
  expectedAmount: number;
  amountInSlip: number;
  currency: string;
  durationDays: number;
  transRef: string;
  storagePath: string;
  slipSha256: string;
  createdAt: FirebaseFirestore.Timestamp;
  thunderRaw: Record<string, unknown>;
}

interface SlipInspection {
  contentType: string;
  downloadUrl: string;
  size: number;
  slipSha256: string;
}

interface EntitlementData {
  active: boolean;
  packageId: string;
  sourceOrderId: string;
  paymentRef: string;
  durationDays: number;
  activatedAt: FirebaseFirestore.Timestamp;
  expiresAt: FirebaseFirestore.Timestamp;
  updatedAt: FirebaseFirestore.Timestamp;
}

interface PurchaseHistoryData {
  uid: string;
  packageId: string;
  orderId: string;
  paymentRef: string;
  status: "PAID";
  expectedAmount: number;
  amountInSlip: number;
  currency: string;
  durationDays: number;
  source: string;
  storagePath: string;
  slipSha256: string;
  paidAt: FirebaseFirestore.Timestamp;
  entitlementExpiresAt: FirebaseFirestore.Timestamp;
}

interface PackageHistoryData {
  uid: string;
  packageId: string;
  eventType: string;
  source: string;
  orderId: string | null;
  paymentRef: string | null;
  daysDelta: number;
  note: string;
  beforeExpiresAt: FirebaseFirestore.Timestamp;
  afterExpiresAt: FirebaseFirestore.Timestamp;
  activeAfter: boolean;
  createdAt: FirebaseFirestore.Timestamp;
  createdBy: string;
}

interface ManualCorrectionRequestData {
  uid: string;
  email: string;
  packageId: string;
  orderId: string | null;
  paymentRef: string | null;
  note: string;
  status: string;
  createdAt: FirebaseFirestore.Timestamp;
  updatedAt: FirebaseFirestore.Timestamp;
}

interface VerifyInput {
  orderId: string;
  storagePath: string;
}

interface ManualCorrectionRequestInput {
  packageId: string;
  note: string;
  orderId: string | null;
  paymentRef: string | null;
}

interface ManualPackageCorrectionInput {
  uid: string;
  packageId: string;
  daysDelta: number;
  note: string;
  requestId: string | null;
}

interface PackageAccessState {
  allowed: boolean;
  status: "ACTIVE" | "EXPIRED" | "NO_ACTIVE_PACKAGE";
  packageId: string | null;
  remainingDays: number;
  expiresAt: string | null;
  message: string;
}

interface PackageAccessCandidate {
  packageId: string;
  expiresAt: Date;
  remainingDays: number;
}

function asRecord(value: unknown): Record<string, unknown> {
  if (typeof value === "object" && value !== null) {
    return value as Record<string, unknown>;
  }
  return {};
}

function asTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asNumber(value: unknown, fallback = 0): number {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function asBoolean(value: unknown, fallback = false): boolean {
  return typeof value === "boolean" ? value : fallback;
}

function toTimestamp(value: unknown, fieldName: string): FirebaseFirestore.Timestamp {
  if (value instanceof admin.firestore.Timestamp) {
    return value;
  }
  throw new HttpsError(
    "data-loss",
    `Document is missing a valid ${fieldName} timestamp.`
  );
}

function toDate(value: unknown): Date | null {
  if (value instanceof admin.firestore.Timestamp) {
    return value.toDate();
  }
  if (value instanceof Date) {
    return value;
  }
  return null;
}

function addDays(base: Date, days: number): Date {
  return new Date(base.getTime() + days * 24 * 60 * 60 * 1000);
}

function addMinutes(base: Date, minutes: number): Date {
  return new Date(base.getTime() + minutes * 60 * 1000);
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
  if (error instanceof ThunderApiError) {
    return {
      errorName: error.name,
      errorCode: error.code,
      errorMessage: error.message,
      httpStatus: error.httpStatus,
      rawBody: error.rawBody,
    };
  }
  if (error instanceof Error) {
    return {
      errorName: error.name,
      errorMessage: error.message,
      errorStack: error.stack,
    };
  }
  return {errorValue: String(error)};
}

function getUid(request: CallableRequest<unknown>): string {
  const uid = request.auth?.uid ?? "";
  if (uid.length === 0) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  return uid;
}

function requireAdmin(request: CallableRequest<unknown>): string {
  const uid = getUid(request);
  if (request.auth?.token?.admin === true) {
    return uid;
  }
  throw new HttpsError("permission-denied", "Admin role required.");
}

function requireAppCheck(request: CallableRequest<unknown>): void {
  if (request.app == null) {
    throw new HttpsError(
      "failed-precondition",
      "App Check token is required."
    );
  }
}

function getPackageId(data: unknown): string {
  const packageId = asTrimmedString(asRecord(data)["packageId"]);
  if (packageId.length === 0) {
    throw new HttpsError("invalid-argument", "packageId is required.");
  }
  return packageId;
}

function getVerifyInput(data: unknown): VerifyInput {
  const payload = asRecord(data);
  const orderId = asTrimmedString(payload["orderId"]);
  const storagePath = asTrimmedString(payload["storagePath"]);
  if (orderId.length === 0) {
    throw new HttpsError("invalid-argument", "orderId is required.");
  }
  if (storagePath.length === 0) {
    throw new HttpsError("invalid-argument", "storagePath is required.");
  }
  return {orderId, storagePath};
}

function getManualCorrectionRequestInput(
  data: unknown
): ManualCorrectionRequestInput {
  const payload = asRecord(data);
  const packageId = asTrimmedString(payload["packageId"]);
  const note = asTrimmedString(payload["note"]);
  const orderId = asTrimmedString(payload["orderId"]) || null;
  const paymentRef = asTrimmedString(payload["paymentRef"]) || null;
  if (packageId.length === 0) {
    throw new HttpsError("invalid-argument", "packageId is required.");
  }
  if (note.length === 0) {
    throw new HttpsError("invalid-argument", "note is required.");
  }
  return {packageId, note, orderId, paymentRef};
}

function getManualPackageCorrectionInput(
  data: unknown
): ManualPackageCorrectionInput {
  const payload = asRecord(data);
  const uid = asTrimmedString(payload["uid"]);
  const packageId = asTrimmedString(payload["packageId"]);
  const note = asTrimmedString(payload["note"]);
  const requestId = asTrimmedString(payload["requestId"]) || null;
  const rawDaysDelta = asNumber(payload["daysDelta"]);
  const daysDelta = rawDaysDelta < 0 ? Math.ceil(rawDaysDelta) : Math.floor(rawDaysDelta);

  if (uid.length === 0) {
    throw new HttpsError("invalid-argument", "uid is required.");
  }
  if (packageId.length === 0) {
    throw new HttpsError("invalid-argument", "packageId is required.");
  }
  if (daysDelta === 0) {
    throw new HttpsError("invalid-argument", "daysDelta must not be 0.");
  }
  if (note.length === 0) {
    throw new HttpsError("invalid-argument", "note is required.");
  }

  return {uid, packageId, daysDelta, note, requestId};
}

function normalizeOrderStatus(value: unknown): OrderStatus {
  const status = asTrimmedString(value).toUpperCase();
  if (status === ORDER_STATUS_PAID) {
    return ORDER_STATUS_PAID;
  }
  if (status === ORDER_STATUS_EXPIRED) {
    return ORDER_STATUS_EXPIRED;
  }
  return ORDER_STATUS_PENDING;
}

function parseProduct(snapshot: FirebaseFirestore.DocumentSnapshot): ProductData {
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "Package not found.");
  }
  const data = asRecord(snapshot.data());
  const name = asTrimmedString(data["name"]);
  const price = asNumber(data["price"]);
  const currency = asTrimmedString(data["currency"]) || "THB";
  const durationDays = Math.floor(asNumber(data["durationDays"]));
  const active = asBoolean(data["active"]);

  if (name.length === 0 || price <= 0 || durationDays <= 0) {
    throw new HttpsError(
      "failed-precondition",
      "Package configuration is invalid."
    );
  }
  if (!active) {
    throw new HttpsError(
      "failed-precondition",
      "Package is not available for purchase."
    );
  }

  return {name, price, currency, durationDays, active};
}

function parseOrder(snapshot: FirebaseFirestore.DocumentSnapshot): OrderData {
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "Order not found.");
  }
  const data = asRecord(snapshot.data());
  const uid = asTrimmedString(data["uid"]);
  const packageId = asTrimmedString(data["packageId"]);
  const expectedAmount = asNumber(data["expectedAmount"]);
  const currency = asTrimmedString(data["currency"]) || "THB";
  const durationDays = Math.floor(asNumber(data["durationDays"]));
  const status = normalizeOrderStatus(data["status"]);

  if (
    uid.length === 0 ||
    packageId.length === 0 ||
    expectedAmount <= 0 ||
    durationDays <= 0
  ) {
    throw new HttpsError(
      "data-loss",
      "Order document is missing required fields."
    );
  }

  return {
    uid,
    packageId,
    expectedAmount,
    currency,
    durationDays,
    status,
    createdAt: toTimestamp(data["createdAt"], "createdAt"),
    expiresAt: toTimestamp(data["expiresAt"], "expiresAt"),
    slipPath: asTrimmedString(data["slipPath"]) || null,
    slipSha256: asTrimmedString(data["slipSha256"]) || null,
    paymentRef: asTrimmedString(data["paymentRef"]) || null,
    lastVerifyCode: asTrimmedString(data["lastVerifyCode"]) || null,
    lastVerifyMessage: asTrimmedString(data["lastVerifyMessage"]) || null,
    lastVerificationAt: data["lastVerificationAt"] instanceof admin.firestore.Timestamp ?
      data["lastVerificationAt"] :
      undefined,
    paidAt: data["paidAt"] instanceof admin.firestore.Timestamp ?
      data["paidAt"] :
      undefined,
  };
}

function parsePayment(snapshot: FirebaseFirestore.DocumentSnapshot): PaymentData {
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "Payment not found.");
  }
  const data = asRecord(snapshot.data());
  return {
    uid: asTrimmedString(data["uid"]),
    orderId: asTrimmedString(data["orderId"]),
    packageId: asTrimmedString(data["packageId"]),
    expectedAmount: asNumber(data["expectedAmount"]),
    amountInSlip: asNumber(data["amountInSlip"]),
    currency: asTrimmedString(data["currency"]) || "THB",
    durationDays: Math.floor(asNumber(data["durationDays"])),
    transRef: asTrimmedString(data["transRef"]),
    storagePath: asTrimmedString(data["storagePath"]),
    slipSha256: asTrimmedString(data["slipSha256"]),
    createdAt: toTimestamp(data["createdAt"], "createdAt"),
    thunderRaw: asRecord(data["thunderRaw"]),
  };
}

function buildOrderPath(orderId: string): string {
  return `${ORDER_PATH_PREFIX}/${orderId}`;
}

function buildPaymentPath(transRef: string): string {
  return `${PAYMENT_PATH_PREFIX}/${transRef}`;
}

function buildPurchaseHistoryPath(uid: string, paymentRef: string): string {
  return `${USER_COLLECTION_PATH_PREFIX}/${uid}/${PURCHASE_HISTORY_PATH_PREFIX}/${paymentRef}`;
}

function buildPackageHistoryPrefix(uid: string): string {
  return `${USER_COLLECTION_PATH_PREFIX}/${uid}/${PACKAGE_HISTORY_PATH_PREFIX}`;
}

function getUserProfileFromAuth(request: CallableRequest<unknown>): {
  email: string;
} {
  const token = asRecord(request.auth?.token);
  return {
    email: asTrimmedString(token["email"]),
  };
}

function getThunderApiKey(): string {
  const apiKey =
    (process.env.THUNDER_API_KEY ?? "").trim() ||
    thunderApiKey.value().trim();
  if (apiKey.length === 0) {
    throw new HttpsError(
      "failed-precondition",
      "THUNDER_API_KEY secret is not configured."
    );
  }
  return apiKey;
}

function buildPackageAccessState(params: {
  allowed: boolean;
  status: "ACTIVE" | "EXPIRED" | "NO_ACTIVE_PACKAGE";
  packageId: string | null;
  remainingDays: number;
  expiresAt: Date | null;
  message: string;
}): PackageAccessState {
  return {
    allowed: params.allowed,
    status: params.status,
    packageId: params.packageId,
    remainingDays: params.remainingDays,
    expiresAt: params.expiresAt?.toISOString() ?? null,
    message: params.message,
  };
}

function isOrderExpired(order: OrderData, now: Date): boolean {
  return order.expiresAt.toDate().getTime() <= now.getTime();
}

function assertOrderOwner(order: OrderData, uid: string): void {
  if (order.uid !== uid) {
    throw new HttpsError("permission-denied", "This order belongs to another user.");
  }
}

function assertStoragePathForOrder(
  uid: string,
  orderId: string,
  storagePath: string
): void {
  const escapedUid = uid.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const escapedOrderId = orderId.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const pattern = new RegExp(
    `^${SLIP_PATH_PREFIX}/${escapedUid}/${escapedOrderId}(?:\\.[a-zA-Z0-9]+)?$`
  );
  if (!pattern.test(storagePath)) {
    throw new HttpsError(
      "invalid-argument",
      "storagePath must point to the caller's slip file for this order."
    );
  }
}

function buildFirebaseStorageDownloadUrl(
  bucketName: string,
  storagePath: string,
  token: string
): string {
  const encodedObjectPath = encodeURIComponent(storagePath);
  const encodedToken = encodeURIComponent(token);
  return (
    `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encodedObjectPath}` +
    `?alt=media&token=${encodedToken}`
  );
}

async function inspectSlip(storagePath: string): Promise<SlipInspection> {
  const bucket = storage.bucket();
  const file = bucket.file(storagePath);
  const [exists] = await file.exists();
  if (!exists) {
    throw new HttpsError("not-found", "Slip file not found in storage.");
  }

  const [metadata] = await file.getMetadata();
  const size = Number.parseInt(`${metadata.size ?? "0"}`, 10);
  const contentType = `${metadata.contentType ?? ""}`;
  if (!ALLOWED_IMAGE_MIME.test(contentType)) {
    throw new HttpsError(
      "failed-precondition",
      "Slip file must be an image."
    );
  }
  if (!Number.isFinite(size) || size <= 0 || size > SLIP_MAX_BYTES) {
    throw new HttpsError(
      "failed-precondition",
      "Slip file size is invalid."
    );
  }

  const [fileBuffer] = await file.download();
  const slipSha256 = createHash("sha256")
    .update(fileBuffer)
    .digest("hex");

  const metadataRecord = asRecord(metadata.metadata);
  let token = asTrimmedString(metadataRecord["firebaseStorageDownloadTokens"]);
  if (token.includes(",")) {
    token = token.split(",")[0].trim();
  }

  if (token.length === 0) {
    token = randomUUID();
    if (typeof file.setMetadata === "function") {
      const nextMetadata = {
        ...metadataRecord,
        firebaseStorageDownloadTokens: token,
      };
      await file.setMetadata({metadata: nextMetadata});
    }
  }

  return {
    contentType,
    downloadUrl: buildFirebaseStorageDownloadUrl(bucket.name, storagePath, token),
    size,
    slipSha256,
  };
}

async function getSlipUploadSessionUrl(storagePath: string): Promise<string> {
  const bucket = storage.bucket();
  const file = bucket.file(storagePath);
  const downloadToken = randomUUID();
  const [sessionUrl] = await file.createResumableUpload({
    metadata: {
      contentType: "image/jpeg",
      metadata: {
        firebaseStorageDownloadTokens: downloadToken,
      },
    },
  });
  return sessionUrl;
}

async function updateOrderVerificationState(
  orderRef: FirebaseFirestore.DocumentReference,
  patch: Record<string, unknown>
): Promise<void> {
  await orderRef.set(
    {
      ...patch,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      lastVerificationAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge: true}
  );
}

function buildPaidResponse(params: {
  orderId: string;
  order: OrderData;
  payment: PaymentData;
  entitlementExpiresAt: Date | null;
  alreadyProcessed: boolean;
}) {
  return {
    status: ORDER_STATUS_PAID,
    orderId: params.orderId,
    packageId: params.order.packageId,
    paymentRef: params.payment.transRef,
    expectedAmount: params.order.expectedAmount,
    amountInSlip: params.payment.amountInSlip,
    currency: params.order.currency,
    durationDays: params.order.durationDays,
    storagePath: params.payment.storagePath,
    alreadyProcessed: params.alreadyProcessed,
    entitlement: {
      packageId: params.order.packageId,
      active: true,
      expiresAt: params.entitlementExpiresAt?.toISOString() ?? null,
    },
  };
}

function mapThunderError(error: ThunderApiError): HttpsError {
  if (error.code === "SLIP_PENDING") {
    return new HttpsError(
      "aborted",
      "Slip verification is pending. Please retry shortly.",
      {
        code: "SLIP_PENDING",
        retryable: true,
        providerCode: error.code,
        providerMessage: error.message,
      }
    );
  }

  if (error.code === "DUPLICATE_SLIP") {
    return new HttpsError(
      "already-exists",
      "Slip has already been used.",
      {
        code: "DUPLICATE_SLIP",
        providerCode: error.code,
        providerMessage: error.message,
      }
    );
  }

  if (error.code === "AMOUNT_NOT_MATCH" || error.code === "AMOUNT_MISMATCH") {
    return new HttpsError(
      "failed-precondition",
      "Slip amount does not match the selected package.",
      {
        code: "AMOUNT_MISMATCH",
        providerCode: error.code,
        providerMessage: error.message,
      }
    );
  }

  if (error.code === "ACCOUNT_NOT_MATCH") {
    return new HttpsError(
      "failed-precondition",
      "Slip receiver account does not match the configured account.",
      {
        code: "ACCOUNT_NOT_MATCH",
        providerCode: error.code,
        providerMessage: error.message,
      }
    );
  }

  return new HttpsError(
    "unavailable",
    "Slip verification service is unavailable.",
    {
      code: "THUNDER_UNAVAILABLE",
      providerCode: error.code,
      providerMessage: error.message,
      httpStatus: error.httpStatus,
    }
  );
}

export const createPackageOrder = onCall(
  {enforceAppCheck: true},
  async (request) => {
    requireAppCheck(request);
    const uid = getUid(request);
    const packageId = getPackageId(request.data);
    const productRef = db.collection(PRODUCT_PATH_PREFIX).doc(packageId);

    try {
      const product = parseProduct(await productRef.get());
      const now = new Date();
      const orderRef = db.collection(ORDER_PATH_PREFIX).doc();
      const orderData: OrderData = {
        uid,
        packageId,
        expectedAmount: product.price,
        currency: product.currency,
        durationDays: product.durationDays,
        status: ORDER_STATUS_PENDING,
        createdAt: admin.firestore.Timestamp.fromDate(now),
        expiresAt: admin.firestore.Timestamp.fromDate(
          addMinutes(now, ORDER_TTL_MINUTES)
        ),
        slipPath: null,
        slipSha256: null,
        paymentRef: null,
        lastVerifyCode: null,
        lastVerifyMessage: null,
      };
      const storagePath = `${SLIP_PATH_PREFIX}/${uid}/${orderRef.id}.jpg`;
      const uploadUrl = await getSlipUploadSessionUrl(storagePath);

      await orderRef.set({
        ...orderData,
        productName: product.name,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return {
        orderId: orderRef.id,
        expectedAmount: orderData.expectedAmount,
        currency: orderData.currency,
        durationDays: orderData.durationDays,
        expiresAt: orderData.expiresAt.toDate().toISOString(),
        storagePath,
        uploadUrl,
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      logger.error("createPackageOrder failed", {
        uid,
        packageId,
        ...serializeError(error),
      });
      throw new HttpsError("internal", "Unable to create package order.");
    }
  }
);

export const getPackageAccessState = onCall(
  {enforceAppCheck: true},
  async (request) => {
    requireAppCheck(request);
    const uid = getUid(request);

    try {
      const now = new Date();
      const entitlementsSnap = await db
        .collection(USER_COLLECTION_PATH_PREFIX)
        .doc(uid)
        .collection("entitlements")
        .get();

      let bestActive: PackageAccessCandidate | null = null;
      let bestExpired: PackageAccessCandidate | null = null;

      for (const doc of entitlementsSnap.docs) {
        const data = asRecord(doc.data());
        const packageId = asTrimmedString(data["packageId"]) || doc.id;
        const active = asBoolean(data["active"], false);
        const expiresAt = toDate(data["expiresAt"]);
        if (packageId.length === 0 || expiresAt == null) {
          continue;
        }

        const remainingDays = Math.floor(
          (expiresAt.getTime() - now.getTime()) / DAY_IN_MS
        );

        if (active && remainingDays >= 0) {
          if (bestActive == null || expiresAt.getTime() > bestActive.expiresAt.getTime()) {
            bestActive = {packageId, expiresAt, remainingDays};
          }
          continue;
        }

        if (remainingDays < 0) {
          if (bestExpired == null || expiresAt.getTime() > bestExpired.expiresAt.getTime()) {
            bestExpired = {packageId, expiresAt, remainingDays};
          }
        }
      }

      const activeCandidate = bestActive;
      if (activeCandidate != null) {
        return buildPackageAccessState({
          allowed: true,
          status: "ACTIVE",
          packageId: activeCandidate.packageId,
          remainingDays: activeCandidate.remainingDays,
          expiresAt: activeCandidate.expiresAt,
          message: "ใช้งานแพ็กเกจได้ตามปกติ",
        });
      }

      const expiredCandidate = bestExpired;
      if (expiredCandidate != null) {
        return buildPackageAccessState({
          allowed: false,
          status: "EXPIRED",
          packageId: expiredCandidate.packageId,
          remainingDays: expiredCandidate.remainingDays,
          expiresAt: expiredCandidate.expiresAt,
          message: "แพ็กเกจหมดอายุแล้ว กรุณาเปิดหน้าบัญชีเพื่อต่ออายุ",
        });
      }

      return buildPackageAccessState({
        allowed: false,
        status: "NO_ACTIVE_PACKAGE",
        packageId: null,
        remainingDays: -1,
        expiresAt: null,
        message: "ยังไม่มีแพ็กเกจที่ใช้งานอยู่ กรุณาเปิดหน้าบัญชีเพื่อซื้อแพ็กเกจ",
      });
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      logger.error("getPackageAccessState failed", {
        uid,
        ...serializeError(error),
      });
      throw new HttpsError("internal", "Unable to resolve package access.");
    }
  }
);

export const verifyPackageSlip = onCall(
  {
    enforceAppCheck: true,
    secrets: [thunderApiKey],
  },
  async (request) => {
    requireAppCheck(request);
    const uid = getUid(request);
    const {orderId, storagePath} = getVerifyInput(request.data);
    const orderRef = db.collection(ORDER_PATH_PREFIX).doc(orderId);
    let order: OrderData | null = null;
    let slipInspection: SlipInspection | null = null;

    try {
      order = parseOrder(await orderRef.get());
      assertOrderOwner(order, uid);
      assertStoragePathForOrder(uid, orderId, storagePath);

      const now = new Date();
      if (order.status === ORDER_STATUS_PAID && order.paymentRef != null) {
        const paymentSnap = await db.collection(PAYMENT_PATH_PREFIX)
          .doc(order.paymentRef)
          .get();
        const payment = parsePayment(paymentSnap);
        const entitlementSnap = await db
          .collection("users")
          .doc(uid)
          .collection("entitlements")
          .doc(order.packageId)
          .get();
        const entitlementExpiresAt = toDate(entitlementSnap.data()?.["expiresAt"] ?? null);
        return buildPaidResponse({
          orderId,
          order,
          payment,
          entitlementExpiresAt,
          alreadyProcessed: true,
        });
      }

      if (order.status !== ORDER_STATUS_PENDING) {
        throw new HttpsError(
          "failed-precondition",
          "Order is not pending anymore.",
          {code: "ORDER_NOT_PENDING", status: order.status}
        );
      }

      if (isOrderExpired(order, now)) {
        await updateOrderVerificationState(orderRef, {
          status: ORDER_STATUS_EXPIRED,
          slipPath: storagePath,
          lastVerifyCode: "ORDER_EXPIRED",
          lastVerifyMessage: "Order expired before slip verification.",
        });
        throw new HttpsError(
          "deadline-exceeded",
          "Order has expired. Please create a new order.",
          {code: "ORDER_EXPIRED"}
        );
      }

      slipInspection = await inspectSlip(storagePath);
      const verifiedSlip = slipInspection;

      const thunderResult = await verifySlipByUrl(getThunderApiKey(), {
        url: verifiedSlip.downloadUrl,
        remark: orderId,
        matchAmount: order.expectedAmount,
        checkDuplicate: CHECK_DUPLICATE_ENABLED,
        matchAccount: MATCH_ACCOUNT_ENABLED,
      });

      if (CHECK_DUPLICATE_ENABLED && thunderResult.isDuplicate) {
        await updateOrderVerificationState(orderRef, {
          slipPath: storagePath,
          slipSha256: verifiedSlip.slipSha256,
          lastVerifyCode: "DUPLICATE_SLIP",
          lastVerifyMessage: "Slip was already used.",
          thunderStatus: "DUPLICATE_SLIP",
        });
        throw new HttpsError(
          "already-exists",
          "Slip has already been used.",
          {
            code: "DUPLICATE_SLIP",
            retryable: false,
            checkDuplicate: CHECK_DUPLICATE_ENABLED,
          }
        );
      }

      if (thunderResult.isAmountMatched === false) {
        await updateOrderVerificationState(orderRef, {
          slipPath: storagePath,
          slipSha256: verifiedSlip.slipSha256,
          lastVerifyCode: "AMOUNT_MISMATCH",
          lastVerifyMessage: "Slip amount does not match the selected package.",
          thunderStatus: "AMOUNT_MISMATCH",
        });
        throw new HttpsError(
          "failed-precondition",
          "Slip amount does not match the selected package.",
          {
            code: "AMOUNT_MISMATCH",
            expectedAmount: order.expectedAmount,
            amountInSlip: thunderResult.amountInSlip,
            matchAmount: order.expectedAmount,
          }
        );
      }

      if (MATCH_ACCOUNT_ENABLED && thunderResult.matchedAccount == null) {
        await updateOrderVerificationState(orderRef, {
          slipPath: storagePath,
          slipSha256: verifiedSlip.slipSha256,
          lastVerifyCode: "ACCOUNT_NOT_MATCH",
          lastVerifyMessage: "Slip receiver account did not match the configured account.",
          thunderStatus: "ACCOUNT_NOT_MATCH",
        });
        throw new HttpsError(
          "failed-precondition",
          "Slip receiver account does not match the configured account.",
          {
            code: "ACCOUNT_NOT_MATCH",
            matchAccount: MATCH_ACCOUNT_ENABLED,
          }
        );
      }

      const transRef = asTrimmedString(thunderResult.rawSlip["transRef"]);
      if (transRef.length === 0 || transRef.includes("/")) {
        throw new HttpsError(
          "failed-precondition",
          "Verified slip is missing a valid transaction reference.",
          {code: "MISSING_TRANS_REF"}
        );
      }

      const paymentRef = db.collection(PAYMENT_PATH_PREFIX).doc(transRef);
      const userRef = db.collection(USER_COLLECTION_PATH_PREFIX).doc(uid);
      const entitlementRef = db
        .collection(USER_COLLECTION_PATH_PREFIX)
        .doc(uid)
        .collection("entitlements")
        .doc(order.packageId);
      const purchaseHistoryRef = userRef
        .collection(PURCHASE_HISTORY_PATH_PREFIX)
        .doc(transRef);
      const packageHistoryRef = userRef
        .collection(PACKAGE_HISTORY_PATH_PREFIX)
        .doc(`payment_${transRef}`);

      const finalizeResult = await db.runTransaction(async (tx) => {
        const freshOrder = parseOrder(await tx.get(orderRef));
        assertOrderOwner(freshOrder, uid);

        if (freshOrder.status === ORDER_STATUS_PAID && freshOrder.paymentRef != null) {
          const paidPayment = parsePayment(
            await tx.get(db.collection(PAYMENT_PATH_PREFIX).doc(freshOrder.paymentRef))
          );
          const entitlementSnap = await tx.get(entitlementRef);
          const entitlementExpiresAt =
            toDate(entitlementSnap.data()?.["expiresAt"] ?? null);
          return buildPaidResponse({
            orderId,
            order: freshOrder,
            payment: paidPayment,
            entitlementExpiresAt,
            alreadyProcessed: true,
          });
        }

        if (freshOrder.status !== ORDER_STATUS_PENDING) {
          throw new HttpsError(
            "failed-precondition",
            "Order is not pending anymore.",
            {code: "ORDER_NOT_PENDING", status: freshOrder.status}
          );
        }

        if (isOrderExpired(freshOrder, now)) {
          tx.set(orderRef, {
            status: ORDER_STATUS_EXPIRED,
            slipPath: storagePath,
            slipSha256: verifiedSlip.slipSha256,
            updatedAt: admin.firestore.Timestamp.fromDate(now),
            lastVerifyCode: "ORDER_EXPIRED",
            lastVerifyMessage: "Order expired before payment finalization.",
            lastVerificationAt: admin.firestore.Timestamp.fromDate(now),
          }, {merge: true});
          throw new HttpsError(
            "deadline-exceeded",
            "Order has expired. Please create a new order.",
            {code: "ORDER_EXPIRED"}
          );
        }

        const existingPaymentSnap = await tx.get(paymentRef);
        if (existingPaymentSnap.exists) {
          const existingPayment = parsePayment(existingPaymentSnap);
          if (freshOrder.paymentRef === existingPayment.transRef &&
              existingPayment.orderId === orderId &&
              existingPayment.uid === uid) {
            const entitlementSnap = await tx.get(entitlementRef);
            const entitlementExpiresAt =
              toDate(entitlementSnap.data()?.["expiresAt"] ?? null);
            return buildPaidResponse({
              orderId,
              order: freshOrder,
              payment: existingPayment,
              entitlementExpiresAt,
              alreadyProcessed: true,
            });
          }
          throw new HttpsError(
            "already-exists",
            "Slip transaction reference has already been used.",
            {
              code: "DUPLICATE_SLIP",
              paymentPath: buildPaymentPath(transRef),
            }
          );
        }

        const entitlementSnap = await tx.get(entitlementRef);
        const existingEntitlement = asRecord(entitlementSnap.data());
        const existingExpiry = toDate(existingEntitlement["expiresAt"]);
        const entitlementBase =
          existingExpiry != null && existingExpiry.getTime() > now.getTime() ?
            existingExpiry :
            now;
        const entitlementExpiry = addDays(
          entitlementBase,
          freshOrder.durationDays
        );

        const paymentData: PaymentData = {
          uid,
          orderId,
          packageId: freshOrder.packageId,
          expectedAmount: freshOrder.expectedAmount,
          amountInSlip: thunderResult.amountInSlip,
          currency: freshOrder.currency,
          durationDays: freshOrder.durationDays,
          transRef,
          storagePath,
          slipSha256: verifiedSlip.slipSha256,
          createdAt: admin.firestore.Timestamp.fromDate(now),
          thunderRaw: thunderResult.rawSlip as Record<string, unknown>,
        };

        tx.create(paymentRef, paymentData);

        const entitlementData: EntitlementData = {
          active: true,
          packageId: freshOrder.packageId,
          sourceOrderId: orderId,
          paymentRef: transRef,
          durationDays: freshOrder.durationDays,
          activatedAt: admin.firestore.Timestamp.fromDate(now),
          expiresAt: admin.firestore.Timestamp.fromDate(entitlementExpiry),
          updatedAt: admin.firestore.Timestamp.fromDate(now),
        };

        const purchaseHistoryData: PurchaseHistoryData = {
          uid,
          packageId: freshOrder.packageId,
          orderId,
          paymentRef: transRef,
          status: "PAID",
          expectedAmount: freshOrder.expectedAmount,
          amountInSlip: thunderResult.amountInSlip,
          currency: freshOrder.currency,
          durationDays: freshOrder.durationDays,
          source: "thunder_slip",
          storagePath,
          slipSha256: verifiedSlip.slipSha256,
          paidAt: admin.firestore.Timestamp.fromDate(now),
          entitlementExpiresAt: admin.firestore.Timestamp.fromDate(entitlementExpiry),
        };

        const packageHistoryData: PackageHistoryData = {
          uid,
          packageId: freshOrder.packageId,
          eventType: "PURCHASE",
          source: "thunder_slip",
          orderId,
          paymentRef: transRef,
          daysDelta: freshOrder.durationDays,
          note: "Payment verified successfully.",
          beforeExpiresAt: admin.firestore.Timestamp.fromDate(entitlementBase),
          afterExpiresAt: admin.firestore.Timestamp.fromDate(entitlementExpiry),
          activeAfter: true,
          createdAt: admin.firestore.Timestamp.fromDate(now),
          createdBy: "system_payment",
        };

        tx.set(entitlementRef, entitlementData, {merge: true});
        tx.set(purchaseHistoryRef, purchaseHistoryData, {merge: true});
        tx.set(packageHistoryRef, packageHistoryData, {merge: true});
        tx.set(orderRef, {
          status: ORDER_STATUS_PAID,
          slipPath: storagePath,
          slipSha256: verifiedSlip.slipSha256,
          paymentRef: transRef,
          paidAt: admin.firestore.Timestamp.fromDate(now),
          updatedAt: admin.firestore.Timestamp.fromDate(now),
          lastVerificationAt: admin.firestore.Timestamp.fromDate(now),
          lastVerifyCode: ORDER_STATUS_PAID,
          lastVerifyMessage: "Slip verified successfully.",
          thunderStatus: ORDER_STATUS_PAID,
        }, {merge: true});

        return buildPaidResponse({
          orderId,
          order: freshOrder,
          payment: paymentData,
          entitlementExpiresAt: entitlementExpiry,
          alreadyProcessed: false,
        });
      });

      return {
        ...finalizeResult,
        matchAmount: order.expectedAmount,
        checkDuplicate: CHECK_DUPLICATE_ENABLED,
        matchAccount: MATCH_ACCOUNT_ENABLED,
      };
    } catch (error) {
      if (error instanceof ThunderApiError) {
        const mappedError = mapThunderError(error);
        const mappedDetails = asRecord(mappedError.details);
        await updateOrderVerificationState(orderRef, {
          slipPath: storagePath,
          slipSha256: slipInspection?.slipSha256 ?? null,
          lastVerifyCode: asTrimmedString(mappedDetails["code"]) || error.code,
          lastVerifyMessage: mappedError.message,
          thunderStatus: error.code,
        }).catch((updateError) => {
          logger.error("verifyPackageSlip failed to persist Thunder error state", {
            orderId,
            storagePath,
            ...serializeError(updateError),
          });
        });
        throw mappedError;
      }
      if (error instanceof HttpsError) {
        throw error;
      }
      logger.error("verifyPackageSlip failed", {
        uid,
        orderId,
        storagePath,
        ...serializeError(error),
      });
      throw new HttpsError("internal", "Unable to verify bank slip.");
    }
  }
);

export const submitManualCorrectionRequest = onCall(
  {enforceAppCheck: true},
  async (request) => {
    requireAppCheck(request);
    const uid = getUid(request);
    const input = getManualCorrectionRequestInput(request.data);
    const profile = getUserProfileFromAuth(request);

    try {
      const requestRef = db.collection(MANUAL_CORRECTION_REQUEST_PATH_PREFIX).doc();
      const now = new Date();
      const requestData: ManualCorrectionRequestData = {
        uid,
        email: profile.email,
        packageId: input.packageId,
        orderId: input.orderId,
        paymentRef: input.paymentRef,
        note: input.note,
        status: "OPEN",
        createdAt: admin.firestore.Timestamp.fromDate(now),
        updatedAt: admin.firestore.Timestamp.fromDate(now),
      };

      await requestRef.set({
        ...requestData,
        createdBy: uid,
        updatedBy: uid,
      });

      return {
        requestId: requestRef.id,
        status: requestData.status,
        packageId: requestData.packageId,
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      logger.error("submitManualCorrectionRequest failed", {
        uid,
        packageId: input.packageId,
        ...serializeError(error),
      });
      throw new HttpsError("internal", "Unable to submit a correction request.");
    }
  }
);

export const applyManualPackageCorrection = onCall(
  async (request) => {
    const adminUid = requireAdmin(request);
    const input = getManualPackageCorrectionInput(request.data);
    const userRef = db.collection(USER_COLLECTION_PATH_PREFIX).doc(input.uid);
    const entitlementRef = userRef.collection("entitlements").doc(input.packageId);
    const packageHistoryRef = userRef.collection(PACKAGE_HISTORY_PATH_PREFIX).doc();
    const requestRef = input.requestId == null ?
      null :
      db.collection(MANUAL_CORRECTION_REQUEST_PATH_PREFIX).doc(input.requestId);

    try {
      const result = await db.runTransaction(async (tx) => {
        const userSnap = await tx.get(userRef);
        if (!userSnap.exists) {
          throw new HttpsError("not-found", "Target user does not exist.");
        }

        const now = new Date();
        const entitlementSnap = await tx.get(entitlementRef);
        const entitlementData = asRecord(entitlementSnap.data());
        const existingExpiry = toDate(entitlementData["expiresAt"]) ?? now;
        const existingActive = asBoolean(entitlementData["active"], false);
        const baseExpiry =
          existingActive && existingExpiry.getTime() > now.getTime() ?
            existingExpiry :
            now;
        const nextExpiry = addDays(baseExpiry, input.daysDelta);
        const activeAfter = nextExpiry.getTime() > now.getTime();
        const activatedAt =
          toDate(entitlementData["activatedAt"]) ?? now;
        const durationDays = Math.max(0, Math.floor(asNumber(entitlementData["durationDays"])));

        tx.set(entitlementRef, {
          active: activeAfter,
          packageId: input.packageId,
          sourceOrderId: asTrimmedString(entitlementData["sourceOrderId"]),
          paymentRef: asTrimmedString(entitlementData["paymentRef"]),
          durationDays,
          activatedAt: admin.firestore.Timestamp.fromDate(activatedAt),
          expiresAt: admin.firestore.Timestamp.fromDate(nextExpiry),
          updatedAt: admin.firestore.Timestamp.fromDate(now),
          lastCorrectionAt: admin.firestore.Timestamp.fromDate(now),
          lastCorrectionBy: adminUid,
          lastCorrectionNote: input.note,
          lastCorrectionDaysDelta: input.daysDelta,
        }, {merge: true});

        const packageHistoryData: PackageHistoryData = {
          uid: input.uid,
          packageId: input.packageId,
          eventType: "MANUAL_CORRECTION",
          source: "admin_manual",
          orderId: null,
          paymentRef: null,
          daysDelta: input.daysDelta,
          note: input.note,
          beforeExpiresAt: admin.firestore.Timestamp.fromDate(existingExpiry),
          afterExpiresAt: admin.firestore.Timestamp.fromDate(nextExpiry),
          activeAfter,
          createdAt: admin.firestore.Timestamp.fromDate(now),
          createdBy: adminUid,
        };
        tx.set(packageHistoryRef, packageHistoryData);

        if (requestRef != null) {
          tx.set(requestRef, {
            status: "APPLIED",
            updatedAt: admin.firestore.Timestamp.fromDate(now),
            resolvedAt: admin.firestore.Timestamp.fromDate(now),
            resolvedBy: adminUid,
            resolutionNote: input.note,
            appliedDaysDelta: input.daysDelta,
          }, {merge: true});
        }

        return {
          packageId: input.packageId,
          daysDelta: input.daysDelta,
          activeAfter,
          beforeExpiresAt: existingExpiry.toISOString(),
          afterExpiresAt: nextExpiry.toISOString(),
          historyPath: `${buildPackageHistoryPrefix(input.uid)}/${packageHistoryRef.id}`,
          requestId: input.requestId,
        };
      });

      return {
        status: "APPLIED",
        ...result,
      };
    } catch (error) {
      if (error instanceof HttpsError) {
        throw error;
      }
      logger.error("applyManualPackageCorrection failed", {
        adminUid,
        targetUid: input.uid,
        packageId: input.packageId,
        ...serializeError(error),
      });
      throw new HttpsError("internal", "Unable to apply package correction.");
    }
  }
);
