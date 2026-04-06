/* eslint-disable no-console */
const fs = require("node:fs");
const path = require("node:path");

const admin = require("firebase-admin");

function parseArgs(argv) {
  const options = {
    seedFile: path.resolve(__dirname, "..", "seeds", "products.seed.json"),
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
  if (!parsed || typeof parsed !== "object" || !parsed.products) {
    throw new Error("Seed file must contain a top-level 'products' object.");
  }
  return parsed.products;
}

function validateProduct(productId, product) {
  if (!product || typeof product !== "object") {
    throw new Error(`Product '${productId}' must be an object.`);
  }
  if (typeof product.name !== "string" || product.name.trim().length === 0) {
    throw new Error(`Product '${productId}' is missing a valid 'name'.`);
  }
  if (typeof product.price !== "number" || !Number.isFinite(product.price) || product.price <= 0) {
    throw new Error(`Product '${productId}' is missing a valid positive 'price'.`);
  }
  if (typeof product.currency !== "string" || product.currency.trim().length === 0) {
    throw new Error(`Product '${productId}' is missing a valid 'currency'.`);
  }
  if (
    typeof product.durationDays !== "number" ||
    !Number.isFinite(product.durationDays) ||
    product.durationDays <= 0
  ) {
    throw new Error(`Product '${productId}' is missing a valid positive 'durationDays'.`);
  }
  if (typeof product.active !== "boolean") {
    throw new Error(`Product '${productId}' is missing a valid boolean 'active'.`);
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
  const products = readSeedFile(options.seedFile);
  const projectId = resolveProjectId(options.projectId);

  if (!admin.apps.length) {
    admin.initializeApp(resolveInitializeOptions(projectId, options.serviceAccountPath));
  }

  const db = admin.firestore();
  const batch = db.batch();
  const entries = Object.entries(products);

  if (entries.length === 0) {
    throw new Error("Seed file contains no products.");
  }

  console.log(`Using Firebase project: ${projectId}`);
  console.log(`Seeding ${entries.length} product(s) from ${options.seedFile}`);
  for (const [productId, product] of entries) {
    validateProduct(productId, product);
    const ref = db.collection("products").doc(productId);
    const payload = {
      ...product,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    console.log(`- products/${productId}`, JSON.stringify(product));
    if (!options.dryRun) {
      batch.set(ref, payload, {merge: true});
    }
  }

  if (options.dryRun) {
    console.log("Dry run complete. No writes were performed.");
    return;
  }

  await batch.commit();
  console.log("Seed commit complete.");
}

main().catch((error) => {
  console.error("Failed to seed products.");
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
