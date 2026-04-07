/* eslint-disable no-console */
const path = require("node:path");

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function requireBuildArtifact(relativePath) {
  const target = path.resolve(__dirname, "..", "lib", relativePath);
  try {
    return require(target);
  } catch (error) {
    throw new Error(
      `Missing compiled artifact '${target}'. Run 'npm --prefix functions run build' first.\n${error}`
    );
  }
}

function createHarness() {
  process.env.THUNDER_API_KEY = process.env.THUNDER_API_KEY || "dummy-test-key";

  const firebase = requireBuildArtifact(path.join("lib", "firebase.js"));
  const thunder = requireBuildArtifact(path.join("lib", "thunder.js"));
  const packageOrders = requireBuildArtifact("package_orders.js");
  const {admin} = firebase;

  const docs = new Map();

  function clone(value) {
    return value == null ? value : JSON.parse(JSON.stringify(value));
  }

  function makeSnapshot(ref) {
    const value = docs.get(ref.path);
    return {
      id: ref.path.split("/").pop(),
      ref,
      exists: value !== undefined,
      data() {
        return value;
      },
    };
  }

  function mergePatch(target, patch) {
    return {
      ...(target || {}),
      ...patch,
    };
  }

  function makeRef(pathValue) {
    return {
      path: pathValue,
      id: pathValue.split("/").pop(),
      collection(name) {
        const collectionPath = `${pathValue}/${name}`;
        return {
          doc(id) {
            return makeRef(`${collectionPath}/${id}`);
          },
          async get() {
            const prefix = `${collectionPath}/`;
            const snapshotDocs = [];
            for (const [docPath] of docs.entries()) {
              if (!docPath.startsWith(prefix)) {
                continue;
              }
              const remainder = docPath.slice(prefix.length);
              if (remainder.length === 0 || remainder.includes("/")) {
                continue;
              }
              snapshotDocs.push(makeSnapshot(makeRef(docPath)));
            }
            return {
              docs: snapshotDocs,
              empty: snapshotDocs.length === 0,
              size: snapshotDocs.length,
              forEach(callback) {
                snapshotDocs.forEach(callback);
              },
            };
          },
        };
      },
      async get() {
        return makeSnapshot(this);
      },
      async set(payload, options) {
        const current = docs.get(this.path);
        docs.set(
          this.path,
          options && options.merge ? mergePatch(current, payload) : payload
        );
      },
    };
  }

  firebase.db = {
    collection(name) {
      return {
        doc(id) {
          return makeRef(`${name}/${id ?? "generated"}`);
        },
      };
    },
    async runTransaction(callback) {
      const tx = {
        async get(ref) {
          return makeSnapshot(ref);
        },
        set(ref, payload, options) {
          const current = docs.get(ref.path);
          docs.set(
            ref.path,
            options && options.merge ? mergePatch(current, payload) : payload
          );
        },
        create(ref, payload) {
          if (docs.has(ref.path)) {
            throw new Error(`Document already exists at ${ref.path}`);
          }
          docs.set(ref.path, payload);
        },
      };
      return callback(tx);
    },
  };

  firebase.storage = {
    bucket() {
      return {
        name: "go-play-720c1.firebasestorage.app",
        file(storagePath) {
          return {
            async exists() {
              return [docs.has(`__storage__/${storagePath}`)];
            },
            async getMetadata() {
              const metadata = docs.get(`__storage__/${storagePath}`) || {};
              return [{
                size: `${metadata.size ?? 0}`,
                contentType: metadata.contentType ?? "",
                metadata: metadata.metadata ?? {},
              }];
            },
            async setMetadata(payload) {
              const current = docs.get(`__storage__/${storagePath}`) || {};
              docs.set(`__storage__/${storagePath}`, {
                ...current,
                metadata: payload?.metadata ?? {},
              });
              return [{}];
            },
            async download() {
              const current = docs.get(`__storage__/${storagePath}`) || {};
              return [Buffer.from(current.body ?? storagePath)];
            },
            async createResumableUpload() {
              return [`https://resumable.example/${encodeURIComponent(storagePath)}`];
            },
          };
        },
      };
    },
  };

  thunder.verifySlipByUrl = async () => ({
    amountInSlip: 599,
    isDuplicate: false,
    isAmountMatched: true,
    matchedAccount: {accountName: "GO_PLAY"},
    rawSlip: {transRef: "TRX12345"},
  });

  return {
    admin,
    docs,
    packageOrders,
    thunder,
    setDoc(pathValue, payload) {
      docs.set(pathValue, payload);
    },
    setStorage(pathValue, metadata) {
      docs.set(`__storage__/${pathValue}`, metadata);
    },
    getDoc(pathValue) {
      return clone(docs.get(pathValue));
    },
  };
}

async function smokeCreatePackageOrder() {
  const harness = createHarness();
  harness.setDoc("products/pkg_03", {
    name: "Premium 30 Days",
    price: 599,
    currency: "THB",
    durationDays: 30,
    active: true,
  });

  const result = await harness.packageOrders.createPackageOrder.run({
    auth: {uid: "smoke-user"},
    app: {appId: "debug-app"},
    data: {packageId: "pkg_03"},
  });

  assert(result.orderId, "createPackageOrder should return orderId");
  assert(result.expectedAmount === 599, "createPackageOrder should read amount from products/pkg_03");
  assert(
    result.storagePath === `slips/smoke-user/${result.orderId}.jpg`,
    "createPackageOrder should return canonical slip path"
  );
  assert(
    typeof result.uploadUrl === "string" &&
      result.uploadUrl.startsWith("https://resumable.example/"),
    "createPackageOrder should return a resumable upload session URL"
  );

  const storedOrder = harness.getDoc(`orders/${result.orderId}`);
  assert(storedOrder, "createPackageOrder should persist an order");
  assert(storedOrder.uid === "smoke-user", "stored order should belong to caller");
  assert(storedOrder.packageId === "pkg_03", "stored order should preserve packageId");
  assert(storedOrder.expectedAmount === 599, "stored order should persist trusted amount");

  return {
    orderId: result.orderId,
    storagePath: result.storagePath,
    uploadUrl: result.uploadUrl,
    expectedAmount: result.expectedAmount,
  };
}

async function smokeVerifyPackageSlipPaidFlow() {
  const harness = createHarness();
  const now = new Date();
  const expiresAt = new Date(now.getTime() + 30 * 60 * 1000);

  harness.setDoc("orders/order_paid_flow", {
    uid: "smoke-user",
    packageId: "pkg_03",
    expectedAmount: 599,
    currency: "THB",
    durationDays: 30,
    status: "PENDING",
    createdAt: harness.admin.firestore.Timestamp.fromDate(now),
    expiresAt: harness.admin.firestore.Timestamp.fromDate(expiresAt),
    slipPath: null,
    paymentRef: null,
  });
  harness.setStorage("slips/smoke-user/order_paid_flow.jpg", {
    size: 123456,
    contentType: "image/jpeg",
  });

  const result = await harness.packageOrders.verifyPackageSlip.run({
    auth: {uid: "smoke-user"},
    app: {appId: "debug-app"},
    data: {
      orderId: "order_paid_flow",
      storagePath: "slips/smoke-user/order_paid_flow.jpg",
    },
  });

  assert(result.status === "PAID", "verifyPackageSlip should mark the order as PAID");
  assert(result.paymentRef === "TRX12345", "verifyPackageSlip should persist Thunder transRef");
  assert(result.entitlement?.active === true, "verifyPackageSlip should return an active entitlement");

  const payment = harness.getDoc("payments/TRX12345");
  const order = harness.getDoc("orders/order_paid_flow");
  const entitlement = harness.getDoc("users/smoke-user/entitlements/pkg_03");
  const purchaseHistory = harness.getDoc("users/smoke-user/purchase_history/TRX12345");
  const packageHistory = harness.getDoc("users/smoke-user/package_history/payment_TRX12345");

  assert(payment?.orderId === "order_paid_flow", "payment doc should reference the paid order");
  assert(order?.status === "PAID", "order doc should be updated to PAID");
  assert(order?.paymentRef === "TRX12345", "order doc should persist paymentRef");
  assert(entitlement?.active === true, "entitlement doc should be active");
  assert(purchaseHistory?.paymentRef === "TRX12345", "purchase history should be written");
  assert(packageHistory?.eventType === "PURCHASE", "package history should record a purchase event");

  return {
    paymentRef: payment.transRef,
    orderStatus: order.status,
    entitlementActive: entitlement.active,
    purchaseHistoryStatus: purchaseHistory.status,
    packageHistoryEventType: packageHistory.eventType,
  };
}

async function smokeVerifyPackageSlipAmountMismatch() {
  const harness = createHarness();
  const now = new Date();
  const expiresAt = new Date(now.getTime() + 30 * 60 * 1000);

  harness.thunder.verifySlipByUrl = async () => ({
    amountInSlip: 500,
    isDuplicate: false,
    isAmountMatched: false,
    matchedAccount: {accountName: "GO_PLAY"},
    rawSlip: {transRef: "TRX_MISMATCH"},
  });

  harness.setDoc("orders/order_mismatch", {
    uid: "smoke-user",
    packageId: "pkg_03",
    expectedAmount: 599,
    currency: "THB",
    durationDays: 30,
    status: "PENDING",
    createdAt: harness.admin.firestore.Timestamp.fromDate(now),
    expiresAt: harness.admin.firestore.Timestamp.fromDate(expiresAt),
    slipPath: null,
    paymentRef: null,
  });
  harness.setStorage("slips/smoke-user/order_mismatch.jpg", {
    size: 234567,
    contentType: "image/jpeg",
  });

  let thrown = null;
  try {
    await harness.packageOrders.verifyPackageSlip.run({
      auth: {uid: "smoke-user"},
      app: {appId: "debug-app"},
      data: {
        orderId: "order_mismatch",
        storagePath: "slips/smoke-user/order_mismatch.jpg",
      },
    });
  } catch (error) {
    thrown = error;
  }

  assert(thrown, "verifyPackageSlip amount mismatch should throw");
  assert(thrown.code === "failed-precondition", "amount mismatch should map to failed-precondition");
  assert(thrown.details?.code === "AMOUNT_MISMATCH", "amount mismatch should expose AMOUNT_MISMATCH detail");

  const order = harness.getDoc("orders/order_mismatch");
  assert(order?.lastVerifyCode === "AMOUNT_MISMATCH", "order should persist amount mismatch state");
  assert(order?.slipPath === "slips/smoke-user/order_mismatch.jpg", "order should persist attempted slip path");

  return {
    errorCode: thrown.code,
    detailCode: thrown.details?.code,
    storedLastVerifyCode: order.lastVerifyCode,
  };
}

async function smokeManualCorrectionFlow() {
  const harness = createHarness();
  const now = new Date();
  const existingExpiry = new Date(now.getTime() + 10 * 24 * 60 * 60 * 1000);

  harness.setDoc("users/target-user", {
    email: "target@example.com",
    displayName: "Target User",
  });
  harness.setDoc("users/target-user/entitlements/pkg_03", {
    active: true,
    packageId: "pkg_03",
    durationDays: 30,
    activatedAt: harness.admin.firestore.Timestamp.fromDate(now),
    expiresAt: harness.admin.firestore.Timestamp.fromDate(existingExpiry),
    updatedAt: harness.admin.firestore.Timestamp.fromDate(now),
  });
  harness.setDoc("manual_correction_requests/request_1", {
    uid: "target-user",
    packageId: "pkg_03",
    status: "OPEN",
  });

  const result = await harness.packageOrders.applyManualPackageCorrection.run({
    auth: {uid: "admin-user", token: {admin: true}},
    data: {
      uid: "target-user",
      packageId: "pkg_03",
      daysDelta: 5,
      note: "Manual support extension",
      requestId: "request_1",
    },
  });

  const entitlement = harness.getDoc("users/target-user/entitlements/pkg_03");
  const packageHistory = harness.getDoc(result.historyPath);
  const requestDoc = harness.getDoc("manual_correction_requests/request_1");

  assert(result.status === "APPLIED", "manual correction should report APPLIED");
  assert(entitlement?.lastCorrectionBy === "admin-user", "manual correction should update entitlement audit fields");
  assert(packageHistory?.eventType === "MANUAL_CORRECTION", "manual correction should create package history");
  assert(requestDoc?.status === "APPLIED", "manual correction request should be marked as applied");

  return {
    status: result.status,
    historyEventType: packageHistory.eventType,
    requestStatus: requestDoc.status,
    activeAfter: entitlement.active,
  };
}

async function smokePackageAccessStateFlow() {
  const harness = createHarness();
  const now = new Date();
  const futureExpiry = new Date(now.getTime() + 2 * 24 * 60 * 60 * 1000);
  const pastExpiry = new Date(now.getTime() - 2 * 24 * 60 * 60 * 1000);

  harness.setDoc("users/access-user/entitlements/pkg_03", {
    active: true,
    packageId: "pkg_03",
    expiresAt: harness.admin.firestore.Timestamp.fromDate(futureExpiry),
  });

  const activeResult = await harness.packageOrders.getPackageAccessState.run({
    auth: {uid: "access-user"},
    app: {appId: "debug-app"},
    data: {},
  });

  assert(activeResult.allowed === true, "active package should be allowed");
  assert(activeResult.status === "ACTIVE", "active package should return ACTIVE");
  assert(activeResult.packageId === "pkg_03", "active package should keep packageId");

  harness.setDoc("users/expired-user/entitlements/pkg_03", {
    active: true,
    packageId: "pkg_03",
    expiresAt: harness.admin.firestore.Timestamp.fromDate(pastExpiry),
  });

  const expiredResult = await harness.packageOrders.getPackageAccessState.run({
    auth: {uid: "expired-user"},
    app: {appId: "debug-app"},
    data: {},
  });

  assert(expiredResult.allowed === false, "expired package should be blocked");
  assert(expiredResult.status === "EXPIRED", "expired package should return EXPIRED");
  assert(
    typeof expiredResult.remainingDays === "number" && expiredResult.remainingDays < 0,
    "expired package should return negative remainingDays"
  );

  const missingResult = await harness.packageOrders.getPackageAccessState.run({
    auth: {uid: "missing-user"},
    app: {appId: "debug-app"},
    data: {},
  });

  assert(missingResult.allowed === false, "missing package should be blocked");
  assert(
    missingResult.status === "NO_ACTIVE_PACKAGE",
    "missing package should return NO_ACTIVE_PACKAGE"
  );

  return {
    activeStatus: activeResult.status,
    expiredStatus: expiredResult.status,
    expiredRemainingDays: expiredResult.remainingDays,
    missingStatus: missingResult.status,
  };
}

async function main() {
  const summary = {
    createPackageOrder: await smokeCreatePackageOrder(),
    verifyPackageSlipPaidFlow: await smokeVerifyPackageSlipPaidFlow(),
    verifyPackageSlipAmountMismatch: await smokeVerifyPackageSlipAmountMismatch(),
    manualCorrectionFlow:
      await smokeManualCorrectionFlow(),
    packageAccessStateFlow:
      await smokePackageAccessStateFlow(),
  };

  console.log("Payment smoke passed.");
  console.log(JSON.stringify(summary, null, 2));
}

main().catch((error) => {
  console.error("Payment smoke failed.");
  console.error(error);
  process.exitCode = 1;
});
