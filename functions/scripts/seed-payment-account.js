/* eslint-disable no-console */
const fs = require("node:fs");
const path = require("node:path");

const admin = require("firebase-admin");

function parseArgs(argv) {
  const options = {
    seedFile: path.resolve(__dirname, "..", "seeds", "payment_account.seed.json"),
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
  const paymentAccount = parsed?.settings?.payment_account;
  if (!paymentAccount || typeof paymentAccount !== "object") {
    throw new Error(
      "Seed file must contain settings.payment_account object.",
    );
  }
  return paymentAccount;
}

function validatePaymentAccount(paymentAccount) {
  const requiredStringFields = [
    "bankDisplayName",
    "accountNameEn",
    "accountNameTh",
    "accountNumber",
  ];

  for (const fieldName of requiredStringFields) {
    if (
      typeof paymentAccount[fieldName] !== "string" ||
      paymentAccount[fieldName].trim().length === 0
    ) {
      throw new Error(`Payment account is missing a valid '${fieldName}'.`);
    }
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
  const paymentAccount = readSeedFile(options.seedFile);
  validatePaymentAccount(paymentAccount);
  const projectId = resolveProjectId(options.projectId);

  if (!admin.apps.length) {
    admin.initializeApp(resolveInitializeOptions(projectId, options.serviceAccountPath));
  }

  const db = admin.firestore();
  const payload = {
    ...paymentAccount,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  console.log(`Using Firebase project: ${projectId}`);
  console.log(`Preparing settings/payment_account from ${options.seedFile}`);
  console.log(JSON.stringify(paymentAccount, null, 2));

  if (options.dryRun) {
    console.log("Dry run complete. No writes were performed.");
    return;
  }

  await db.doc("settings/payment_account").set(payload, {merge: true});
  console.log("Seeded settings/payment_account");
}

main().catch((error) => {
  console.error("Failed to seed payment account.");
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
