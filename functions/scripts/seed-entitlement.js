/* eslint-disable no-console */
const fs = require("node:fs");
const path = require("node:path");

const admin = require("firebase-admin");

function parseArgs(argv) {
  const options = {
    uid: "",
    packageId: "pkg_599",
    days: 30,
    active: true,
    dryRun: false,
    projectId: "",
    serviceAccountPath: "",
  };

  for (let i = 0; i < argv.length; i += 1) {
    const value = argv[i];
    if (value === "--uid" && argv[i + 1]) {
      options.uid = String(argv[i + 1]).trim();
      i += 1;
      continue;
    }
    if (value === "--package-id" && argv[i + 1]) {
      options.packageId = String(argv[i + 1]).trim();
      i += 1;
      continue;
    }
    if (value === "--days" && argv[i + 1]) {
      options.days = Number(argv[i + 1]);
      i += 1;
      continue;
    }
    if (value === "--inactive") {
      options.active = false;
      continue;
    }
    if (value === "--dry-run") {
      options.dryRun = true;
      continue;
    }
    if (value === "--project" && argv[i + 1]) {
      options.projectId = String(argv[i + 1]).trim();
      i += 1;
      continue;
    }
    if (value === "--service-account" && argv[i + 1]) {
      options.serviceAccountPath = String(argv[i + 1]).trim();
      i += 1;
      continue;
    }
  }

  return options;
}

function validateOptions(options) {
  if (!options.uid) {
    throw new Error("Missing required --uid <firebase_uid>.");
  }
  if (!options.packageId) {
    throw new Error("Missing required --package-id <packageId>.");
  }
  if (!Number.isFinite(options.days) || options.days < 0) {
    throw new Error("--days must be a number >= 0.");
  }
}

function resolveProjectId(explicitProjectId) {
  if (explicitProjectId) {
    return explicitProjectId;
  }

  if (process.env.GCLOUD_PROJECT) {
    return process.env.GCLOUD_PROJECT;
  }

  if (process.env.GOOGLE_CLOUD_PROJECT) {
    return process.env.GOOGLE_CLOUD_PROJECT;
  }

  const firebaseRcPath = path.resolve(__dirname, "..", "..", ".firebaserc");
  if (fs.existsSync(firebaseRcPath)) {
    const parsed = JSON.parse(fs.readFileSync(firebaseRcPath, "utf8"));
    const defaultProject = parsed?.projects?.default;
    if (typeof defaultProject === "string" && defaultProject.trim()) {
      return defaultProject.trim();
    }
  }

  throw new Error(
    "Unable to resolve Firebase project. Pass --project <projectId> or set GCLOUD_PROJECT.",
  );
}

function resolveInitializeOptions(projectId, serviceAccountPath) {
  if (serviceAccountPath) {
    const resolvedPath = path.resolve(serviceAccountPath);
    const serviceAccount = JSON.parse(fs.readFileSync(resolvedPath, "utf8"));
    return {
      projectId,
      credential: admin.credential.cert(serviceAccount),
    };
  }

  return {projectId};
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  validateOptions(options);
  const projectId = resolveProjectId(options.projectId);

  if (!admin.apps.length) {
    admin.initializeApp(resolveInitializeOptions(projectId, options.serviceAccountPath));
  }

  const db = admin.firestore();
  const now = admin.firestore.Timestamp.now();
  const expiresAt = admin.firestore.Timestamp.fromMillis(
    Date.now() + options.days * 24 * 60 * 60 * 1000,
  );

  const entitlementPath = `users/${options.uid}/entitlements/${options.packageId}`;
  const payload = {
    packageId: options.packageId,
    active: options.active,
    source: "manual-seed",
    startedAt: now,
    expiresAt,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  console.log(`Using Firebase project: ${projectId}`);
  console.log(`Preparing entitlement seed for ${entitlementPath}`);
  console.log(JSON.stringify({
    ...payload,
    startedAt: now.toDate().toISOString(),
    expiresAt: expiresAt.toDate().toISOString(),
    updatedAt: "<serverTimestamp>",
  }, null, 2));

  if (options.dryRun) {
    console.log("Dry run complete. No writes were performed.");
    return;
  }

  await db.doc(entitlementPath).set(payload, {merge: true});
  console.log(`Seeded ${entitlementPath}`);
}

main().catch((error) => {
  console.error("Failed to seed entitlement.");
  console.error(error);
  if (String(error?.message || "").includes("Could not load the default credentials")) {
    console.error("");
    console.error("Admin SDK could not find Application Default Credentials.");
    console.error("Use one of these options before rerunning:");
    console.error(
      "1. Install Google Cloud SDK and run: gcloud auth application-default login",
    );
    console.error(
      "2. Or pass a service account JSON explicitly: --service-account path/to/service-account.json",
    );
  }
  process.exitCode = 1;
});
