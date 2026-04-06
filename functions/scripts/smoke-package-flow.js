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
        return {
          doc(id) {
            return makeRef(`${pathValue}/${name}/${id}`);
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
  harness.setDoc("products/pkg_599", {
    name: "Premium 30 Days",
    price: 599,
    currency: "THB",
    durationDays: 30,
    active: true,
  });

  const result = await harness.packageOrders.createPackageOrder.run({
    auth: {uid: "smoke-user"},
    app: {appId: "debug-app"},
    data: {packageId: "pkg_599"},
  });

  assert(result.orderId, "createPackageOrder should return orderId");
  assert(result.expectedAmount === 599, "createPackageOrder should read amount from products/pkg_599");
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
  assert(storedOrder.packageId === "pkg_599", "stored order should preserve packageId");
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
    packageId: "pkg_599",
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
  const entitlement = harness.getDoc("users/smoke-user/entitlements/pkg_599");
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
    packageId: "pkg_599",
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

async function smokeVerifyPackageSlipCachedFailureShortCircuit() {
  const harness = createHarness();
  const now = new Date();
  const expiresAt = new Date(now.getTime() + 30 * 60 * 1000);
  const lastVerificationAt = new Date(now.getTime() - 5 * 1000);
  let thunderCallCount = 0;

  harness.thunder.verifySlipByUrl = async () => {
    thunderCallCount += 1;
    return {
      amountInSlip: 500,
      isDuplicate: false,
      isAmountMatched: false,
      matchedAccount: {accountName: "GO_PLAY"},
      rawSlip: {transRef: "TRX_SHOULD_NOT_RUN"},
    };
  };

  harness.setDoc("orders/order_cached_mismatch", {
    uid: "smoke-user",
    packageId: "pkg_599",
    expectedAmount: 599,
    currency: "THB",
    durationDays: 30,
    status: "PENDING",
    createdAt: harness.admin.firestore.Timestamp.fromDate(now),
    expiresAt: harness.admin.firestore.Timestamp.fromDate(expiresAt),
    slipPath: "slips/smoke-user/order_cached_mismatch.jpg",
    paymentRef: null,
    lastVerifyCode: "AMOUNT_MISMATCH",
    lastVerifyMessage: "Slip amount does not match the selected package.",
    lastVerificationAt: harness.admin.firestore.Timestamp.fromDate(lastVerificationAt),
  });
  harness.setStorage("slips/smoke-user/order_cached_mismatch.jpg", {
    size: 111111,
    contentType: "image/jpeg",
  });

  let thrown = null;
  try {
    await harness.packageOrders.verifyPackageSlip.run({
      auth: {uid: "smoke-user"},
      app: {appId: "debug-app"},
      data: {
        orderId: "order_cached_mismatch",
        storagePath: "slips/smoke-user/order_cached_mismatch.jpg",
      },
    });
  } catch (error) {
    thrown = error;
  }

  assert(thrown, "cached mismatch retry should throw");
  assert(thrown.code === "failed-precondition", "cached mismatch should keep failed-precondition");
  assert(thrown.details?.code === "AMOUNT_MISMATCH", "cached mismatch should keep AMOUNT_MISMATCH");
  assert(thrown.details?.cached === true, "cached mismatch should be marked as cached");
  assert(thunderCallCount === 0, "cached mismatch should not call Thunder again");

  return {
    errorCode: thrown.code,
    detailCode: thrown.details?.code,
    cached: thrown.details?.cached,
    thunderCallCount,
  };
}

async function smokeVerifyPackageSlipCrossOrderHashShortCircuit() {
  const harness = createHarness();
  const now = new Date();
  const expiresAt = new Date(now.getTime() + 30 * 60 * 1000);
  let thunderCallCount = 0;

  harness.thunder.verifySlipByUrl = async () => {
    thunderCallCount += 1;
    return {
      amountInSlip: 30,
      isDuplicate: false,
      isAmountMatched: true,
      matchedAccount: {accountName: "GO_PLAY"},
      rawSlip: {transRef: "TRX_HASH_CACHE"},
    };
  };

  harness.setDoc("orders/order_hash_first", {
    uid: "smoke-user",
    packageId: "pkg_599",
    expectedAmount: 30,
    currency: "THB",
    durationDays: 30,
    status: "PENDING",
    createdAt: harness.admin.firestore.Timestamp.fromDate(now),
    expiresAt: harness.admin.firestore.Timestamp.fromDate(expiresAt),
    slipPath: null,
    paymentRef: null,
  });
  harness.setDoc("orders/order_hash_second", {
    uid: "smoke-user",
    packageId: "pkg_599",
    expectedAmount: 30,
    currency: "THB",
    durationDays: 30,
    status: "PENDING",
    createdAt: harness.admin.firestore.Timestamp.fromDate(now),
    expiresAt: harness.admin.firestore.Timestamp.fromDate(expiresAt),
    slipPath: null,
    paymentRef: null,
  });
  harness.setStorage("slips/smoke-user/order_hash_first.jpg", {
    size: 100000,
    contentType: "image/jpeg",
    body: "same-slip-binary",
  });
  harness.setStorage("slips/smoke-user/order_hash_second.jpg", {
    size: 100000,
    contentType: "image/jpeg",
    body: "same-slip-binary",
  });

  const firstResult = await harness.packageOrders.verifyPackageSlip.run({
    auth: {uid: "smoke-user"},
    app: {appId: "debug-app"},
    data: {
      orderId: "order_hash_first",
      storagePath: "slips/smoke-user/order_hash_first.jpg",
    },
  });

  let thrown = null;
  try {
    await harness.packageOrders.verifyPackageSlip.run({
      auth: {uid: "smoke-user"},
      app: {appId: "debug-app"},
      data: {
        orderId: "order_hash_second",
        storagePath: "slips/smoke-user/order_hash_second.jpg",
      },
    });
  } catch (error) {
    thrown = error;
  }

  assert(firstResult.status === "PAID", "first hash-cache verification should succeed");
  assert(thrown, "second verification with the same slip hash should throw");
  assert(thrown.code === "already-exists", "same slip hash should map to already-exists");
  assert(thrown.details?.code === "DUPLICATE_SLIP", "same slip hash should surface DUPLICATE_SLIP");
  assert(thrown.details?.cached === true, "same slip hash should be served from cache");
  assert(thunderCallCount === 1, "same slip hash across a new order should not call Thunder again");

  const secondOrder = harness.getDoc("orders/order_hash_second");
  assert(secondOrder?.lastVerifyCode === "PAID", "second order should inherit cached paid slip state");
  assert(typeof secondOrder?.slipSha256 === "string", "second order should persist the slip hash");

  return {
    firstStatus: firstResult.status,
    secondErrorCode: thrown.code,
    secondDetailCode: thrown.details?.code,
    cached: thrown.details?.cached,
    thunderCallCount,
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
  harness.setDoc("users/target-user/entitlements/pkg_599", {
    active: true,
    packageId: "pkg_599",
    durationDays: 30,
    activatedAt: harness.admin.firestore.Timestamp.fromDate(now),
    expiresAt: harness.admin.firestore.Timestamp.fromDate(existingExpiry),
    updatedAt: harness.admin.firestore.Timestamp.fromDate(now),
  });
  harness.setDoc("manual_correction_requests/request_1", {
    uid: "target-user",
    packageId: "pkg_599",
    status: "OPEN",
  });

  const result = await harness.packageOrders.applyManualPackageCorrection.run({
    auth: {uid: "admin-user", token: {admin: true}},
    data: {
      uid: "target-user",
      packageId: "pkg_599",
      daysDelta: 5,
      note: "Manual support extension",
      requestId: "request_1",
    },
  });

  const entitlement = harness.getDoc("users/target-user/entitlements/pkg_599");
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

async function main() {
  const summary = {
    createPackageOrder: await smokeCreatePackageOrder(),
    verifyPackageSlipPaidFlow: await smokeVerifyPackageSlipPaidFlow(),
    verifyPackageSlipAmountMismatch: await smokeVerifyPackageSlipAmountMismatch(),
    verifyPackageSlipCachedFailureShortCircuit:
      await smokeVerifyPackageSlipCachedFailureShortCircuit(),
    verifyPackageSlipCrossOrderHashShortCircuit:
      await smokeVerifyPackageSlipCrossOrderHashShortCircuit(),
    manualCorrectionFlow:
      await smokeManualCorrectionFlow(),
  };

  console.log("Payment smoke passed.");
  console.log(JSON.stringify(summary, null, 2));
}

main().catch((error) => {
  console.error("Payment smoke failed.");
  console.error(error);
  process.exitCode = 1;
});
