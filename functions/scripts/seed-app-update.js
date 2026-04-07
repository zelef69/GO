/* eslint-disable no-console */
const fs = require("node:fs");
const path = require("node:path");

const admin = require("firebase-admin");

function parseArgs(argv) {
  const options = {
    seedFile: path.resolve(__dirname, "..", "seeds", "app_update_android.seed.json"),
    dryRun: false,
    projectId: "",
    serviceAccountPath: "",
  };

  for (let i = 0; i < argv.length; i += 1) {
    const value = argv[i];
    if (value === "--dry-run") {
      options.dryRun = true;
      continue;
    }
    if (value === "--seed-file" && argv[i + 1]) {
      options.seedFile = path.resolve(argv[i + 1]);
      i += 1;
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

function readSeedFile(seedFile) {
  const raw = fs.readFileSync(seedFile, "utf8");
  const parsed = JSON.parse(raw);
  const appUpdate = parsed?.app_updates?.android;
  if (!appUpdate || typeof appUpdate !== "object") {
    throw new Error("Seed file must contain app_updates.android object.");
  }
  return appUpdate;
}

function validateAppUpdate(appUpdate) {
  const requiredStringFields = [
    "appId",
    "releaseChannel",
    "latestVersionName",
    "apkUrl",
    "apkSha256",
  ];

  for (const fieldName of requiredStringFields) {
    if (
      typeof appUpdate[fieldName] !== "string" ||
      appUpdate[fieldName].trim().length === 0
    ) {
      throw new Error(`App update config is missing a valid '${fieldName}'.`);
    }
  }

  const requiredNumberFields = [
    "latestVersionCode",
    "minimumSupportedVersionCode",
    "apkFileSizeBytes",
    "rolloutPercent",
  ];

  for (const fieldName of requiredNumberFields) {
    if (typeof appUpdate[fieldName] !== "number" || Number.isNaN(appUpdate[fieldName])) {
      throw new Error(`App update config is missing a valid '${fieldName}'.`);
    }
  }

  if (typeof appUpdate.updaterEnabled !== "boolean") {
    throw new Error("App update config is missing a valid 'updaterEnabled'.");
  }

  if (typeof appUpdate.forceUpdate !== "boolean") {
    throw new Error("App update config is missing a valid 'forceUpdate'.");
  }

  if (
    appUpdate.apkSha256.trim().length !== 64 ||
    !/^[a-fA-F0-9]{64}$/.test(appUpdate.apkSha256.trim())
  ) {
    throw new Error("App update config must contain a 64-char hex 'apkSha256'.");
  }

  if (
    appUpdate.releaseNotes !== undefined &&
    !(
      typeof appUpdate.releaseNotes === "string" ||
      (Array.isArray(appUpdate.releaseNotes) &&
        appUpdate.releaseNotes.every((item) => typeof item === "string"))
    )
  ) {
    throw new Error(
      "App update config 'releaseNotes' must be a string or an array of strings.",
    );
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

function normalizePayload(appUpdate) {
  const payload = {
    appId: String(appUpdate.appId).trim(),
    releaseChannel: String(appUpdate.releaseChannel).trim(),
    latestVersionCode: Number(appUpdate.latestVersionCode),
    latestVersionName: String(appUpdate.latestVersionName).trim(),
    minimumSupportedVersionCode: Number(appUpdate.minimumSupportedVersionCode),
    updaterEnabled: Boolean(appUpdate.updaterEnabled),
    forceUpdate: Boolean(appUpdate.forceUpdate),
    apkUrl: String(appUpdate.apkUrl).trim(),
    apkSha256: String(appUpdate.apkSha256).trim().toLowerCase(),
    apkFileSizeBytes: Number(appUpdate.apkFileSizeBytes),
    rolloutPercent: Number(appUpdate.rolloutPercent),
  };

  if (Array.isArray(appUpdate.releaseNotes)) {
    payload.releaseNotes = appUpdate.releaseNotes.map((item) => String(item).trim());
  } else if (typeof appUpdate.releaseNotes === "string") {
    payload.releaseNotes = appUpdate.releaseNotes.trim();
  } else {
    payload.releaseNotes = "";
  }

  return payload;
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const appUpdate = readSeedFile(options.seedFile);
  validateAppUpdate(appUpdate);
  const payload = normalizePayload(appUpdate);
  const projectId = resolveProjectId(options.projectId);

  if (!admin.apps.length) {
    admin.initializeApp(resolveInitializeOptions(projectId, options.serviceAccountPath));
  }

  const db = admin.firestore();
  const writePayload = {
    ...payload,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  console.log(`Using Firebase project: ${projectId}`);
  console.log(`Preparing app_updates/android from ${options.seedFile}`);
  console.log(JSON.stringify(payload, null, 2));

  if (options.dryRun) {
    console.log("Dry run complete. No writes were performed.");
    return;
  }

  await db.doc("app_updates/android").set(writePayload, {merge: true});
  console.log("Seeded app_updates/android");
}

main().catch((error) => {
  console.error("Failed to seed app update metadata.");
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
