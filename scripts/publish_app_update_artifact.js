/* eslint-disable no-console */
const childProcess = require("node:child_process");
const crypto = require("node:crypto");
const fs = require("node:fs");
const https = require("node:https");
const os = require("node:os");
const path = require("node:path");

const FIREBASE_CLI_CLIENT_ID =
  "563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com";
const FIREBASE_CLI_CLIENT_SECRET = "j9iVZfS8kkCEFUPaAeJV0sAi";
const FIREBASE_REST_SCOPES = [
  "https://www.googleapis.com/auth/firebase",
  "https://www.googleapis.com/auth/cloud-platform",
];

function parseArgs(argv) {
  return {
    apkPath: readFlag(argv, "--apk") || "",
    projectId: readFlag(argv, "--project") || "",
    bucket: readFlag(argv, "--bucket") || "",
    seedFile:
      readFlag(argv, "--seed-file") ||
      path.resolve(__dirname, "..", "functions", "seeds", "app_update_android.seed.json"),
    outputJson:
      readFlag(argv, "--output-json") ||
      path.resolve(
        __dirname,
        "..",
        "artifacts",
        "firebase_build",
        `app_update_publish_payload_${timestampToken()}.json`,
      ),
    objectName: readFlag(argv, "--object-name") || "",
    dryRun: argv.includes("--dry-run"),
  };
}

function readFlag(argv, name) {
  const index = argv.indexOf(name);
  if (index >= 0 && argv[index + 1]) {
    return String(argv[index + 1]).trim();
  }
  return "";
}

function timestampToken() {
  const now = new Date();
  const yyyy = now.getFullYear();
  const mm = String(now.getMonth() + 1).padStart(2, "0");
  const dd = String(now.getDate()).padStart(2, "0");
  const hh = String(now.getHours()).padStart(2, "0");
  const mi = String(now.getMinutes()).padStart(2, "0");
  const ss = String(now.getSeconds()).padStart(2, "0");
  return `${yyyy}${mm}${dd}_${hh}${mi}${ss}`;
}

function resolveFirebaseToolsConfigPath() {
  const appData = process.env.APPDATA;
  const candidates = [
    appData ? path.join(appData, "configstore", "firebase-tools.json") : "",
    path.join(os.homedir(), ".config", "configstore", "firebase-tools.json"),
  ].filter(Boolean);
  return candidates.find((candidate) => fs.existsSync(candidate)) || "";
}

function loadFirebaseCliAuthState() {
  const configPath = resolveFirebaseToolsConfigPath();
  if (!configPath) {
    return { accessToken: "", refreshToken: "" };
  }
  const parsed = JSON.parse(fs.readFileSync(configPath, "utf8"));
  return {
    accessToken: (parsed?.tokens?.access_token || "").toString().trim(),
    refreshToken: (parsed?.tokens?.refresh_token || "").toString().trim(),
  };
}

function requestJson({ method, endpoint, token, body, headers = {} }) {
  return new Promise((resolve, reject) => {
    const url = new URL(endpoint);
    const req = https.request(
      {
        protocol: url.protocol,
        hostname: url.hostname,
        path: `${url.pathname}${url.search}`,
        method,
        headers: {
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
          ...headers,
        },
      },
      (res) => {
        let raw = "";
        res.on("data", (chunk) => {
          raw += chunk;
        });
        res.on("end", () => {
          const status = res.statusCode || 0;
          let json = {};
          try {
            json = raw ? JSON.parse(raw) : {};
          } catch (_) {
            json = {};
          }
          if (status >= 200 && status < 300) {
            resolve({
              status,
              headers: res.headers,
              body: json,
              raw,
            });
            return;
          }
          reject(
            new Error(
              json?.error?.message ||
                json?.error ||
                raw ||
                `HTTP ${status} ${method} ${endpoint}`,
            ),
          );
        });
      },
    );
    req.on("error", reject);
    if (body) {
      req.write(body);
    }
    req.end();
  });
}

function requestFormJson({ endpoint, body }) {
  return requestJson({
    method: "POST",
    endpoint,
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      "Content-Length": Buffer.byteLength(body),
    },
    body,
  });
}

async function refreshFirebaseCliAccessToken(refreshToken) {
  const form = new URLSearchParams({
    refresh_token: refreshToken,
    client_id: FIREBASE_CLI_CLIENT_ID,
    client_secret: FIREBASE_CLI_CLIENT_SECRET,
    grant_type: "refresh_token",
    scope: FIREBASE_REST_SCOPES.join(" "),
  });
  const response = await requestFormJson({
    endpoint: "https://www.googleapis.com/oauth2/v3/token",
    body: form.toString(),
  });
  const accessToken = (response?.body?.access_token || "").toString().trim();
  if (!accessToken) {
    throw new Error("Unable to refresh Firebase CLI access token");
  }
  return accessToken;
}

async function loadAccessToken() {
  const authState = loadFirebaseCliAuthState();
  if (authState.refreshToken) {
    return refreshFirebaseCliAccessToken(authState.refreshToken);
  }
  if (authState.accessToken) {
    return authState.accessToken;
  }
  throw new Error("No Firebase CLI auth state found. Run `firebase login` first.");
}

function resolveProjectId(explicitProjectId) {
  if (explicitProjectId) {
    return explicitProjectId;
  }
  const firebaseRcPath = path.resolve(__dirname, "..", ".firebaserc");
  if (fs.existsSync(firebaseRcPath)) {
    const parsed = JSON.parse(fs.readFileSync(firebaseRcPath, "utf8"));
    const projectId = parsed?.projects?.default;
    if (typeof projectId === "string" && projectId.trim()) {
      return projectId.trim();
    }
  }
  throw new Error("Unable to resolve Firebase project. Pass --project <projectId>.");
}

function resolveBucket(explicitBucket) {
  if (explicitBucket) {
    return explicitBucket;
  }
  const candidateFiles = [
    path.resolve(__dirname, "..", "google-services.json"),
    path.resolve(__dirname, "..", "android", "app", "google-services.json"),
  ];
  for (const file of candidateFiles) {
    if (!fs.existsSync(file)) continue;
    const parsed = JSON.parse(fs.readFileSync(file, "utf8"));
    const bucket = parsed?.project_info?.storage_bucket;
    if (typeof bucket === "string" && bucket.trim()) {
      return bucket.trim();
    }
  }
  throw new Error("Unable to resolve Firebase Storage bucket. Pass --bucket <bucket>.");
}

function readSeed(seedFile) {
  const raw = fs.readFileSync(seedFile, "utf8");
  const parsed = JSON.parse(raw);
  const manifest = parsed?.app_updates?.android;
  if (!manifest || typeof manifest !== "object") {
    throw new Error("Seed file must contain app_updates.android");
  }
  return manifest;
}

function computeSha256(filePath) {
  const hash = crypto.createHash("sha256");
  const fd = fs.openSync(filePath, "r");
  try {
    const buffer = Buffer.allocUnsafe(1024 * 1024);
    let bytesRead = 0;
    let offset = 0;
    do {
      bytesRead = fs.readSync(fd, buffer, 0, buffer.length, offset);
      if (bytesRead > 0) {
        hash.update(buffer.subarray(0, bytesRead));
        offset += bytesRead;
      }
    } while (bytesRead > 0);
  } finally {
    fs.closeSync(fd);
  }
  return hash.digest("hex");
}

function defaultObjectName(seed) {
  const sanitizedVersion = String(seed.latestVersionName || "unknown").replace(/[^0-9A-Za-z._-]+/g, "_");
  return [
    "app-updates",
    "android",
    seed.appId,
    String(seed.latestVersionCode),
    `OneTabTube-${sanitizedVersion}-${seed.latestVersionCode}.apk`,
  ].join("/");
}

async function startResumableUpload({
  token,
  bucket,
  objectName,
  fileSize,
  downloadToken,
}) {
  const metadata = {
    name: objectName,
    contentType: "application/vnd.android.package-archive",
    cacheControl: "private, max-age=0, no-transform",
    metadata: {
      firebaseStorageDownloadTokens: downloadToken,
    },
  };
  const response = await requestJson({
    method: "POST",
    endpoint: `https://storage.googleapis.com/upload/storage/v1/b/${encodeURIComponent(bucket)}/o?uploadType=resumable`,
    token,
    headers: {
      "Content-Type": "application/json; charset=UTF-8",
      "X-Upload-Content-Type": "application/vnd.android.package-archive",
      "X-Upload-Content-Length": String(fileSize),
    },
    body: JSON.stringify(metadata),
  });
  const location = (response.headers.location || "").toString().trim();
  if (!location) {
    throw new Error("Storage resumable upload did not return a session URL");
  }
  return location;
}

async function uploadFileToSession(sessionUrl, filePath, fileSize) {
  return new Promise((resolve, reject) => {
    const url = new URL(sessionUrl);
    const req = https.request(
      {
        protocol: url.protocol,
        hostname: url.hostname,
        path: `${url.pathname}${url.search}`,
        method: "PUT",
        headers: {
          "Content-Type": "application/vnd.android.package-archive",
          "Content-Length": String(fileSize),
        },
      },
      (res) => {
        let raw = "";
        res.on("data", (chunk) => {
          raw += chunk;
        });
        res.on("end", () => {
          const status = res.statusCode || 0;
          if (status >= 200 && status < 300) {
            let json = {};
            try {
              json = raw ? JSON.parse(raw) : {};
            } catch (_) {
              json = {};
            }
            resolve(json);
            return;
          }
          reject(new Error(raw || `HTTP ${status} PUT ${sessionUrl}`));
        });
      },
    );
    req.on("error", reject);
    fs.createReadStream(filePath)
      .on("error", reject)
      .pipe(req);
  });
}

async function readObjectMetadata(token, bucket, objectName) {
  const response = await requestJson({
    method: "GET",
    endpoint: `https://storage.googleapis.com/storage/v1/b/${encodeURIComponent(bucket)}/o/${encodeURIComponent(objectName)}`,
    token,
  });
  return response.body;
}

function buildDownloadUrl(bucket, objectName, downloadToken) {
  return `https://firebasestorage.googleapis.com/v0/b/${encodeURIComponent(bucket)}/o/${encodeURIComponent(objectName)}?alt=media&token=${encodeURIComponent(downloadToken)}`;
}

function ensureDirectory(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
}

function writeJson(filePath, payload) {
  ensureDirectory(filePath);
  fs.writeFileSync(filePath, JSON.stringify(payload, null, 2), { encoding: "utf8" });
}

function updatePayload(seed, apkUrl, sha256, fileSize) {
  return {
    appId: String(seed.appId),
    releaseChannel: String(seed.releaseChannel || "stable"),
    latestVersionCode: Number(seed.latestVersionCode),
    latestVersionName: String(seed.latestVersionName),
    minimumSupportedVersionCode: Number(seed.minimumSupportedVersionCode || seed.latestVersionCode),
    updaterEnabled: Boolean(seed.updaterEnabled),
    forceUpdate: Boolean(seed.forceUpdate),
    apkUrl,
    apkSha256: sha256.toLowerCase(),
    apkFileSizeBytes: Number(fileSize),
    releaseNotes: Array.isArray(seed.releaseNotes) ? seed.releaseNotes : String(seed.releaseNotes || ""),
    rolloutPercent: Number(seed.rolloutPercent || 100),
  };
}

function runFirestoreSeed(outputJson, projectId) {
  const env = {
    ...process.env,
    FIREBASE_PROJECT_ID: projectId,
    GO_PLAY_UPDATE_FIRESTORE_COLLECTION: "app_updates",
    GO_PLAY_UPDATE_FIRESTORE_DOCUMENT: "android",
    GO_PLAY_UPDATE_JSON: outputJson,
    NODE_PATH: path.resolve(__dirname, "..", "functions", "node_modules"),
  };
  const result = childProcess.spawnSync(process.execPath, [path.resolve(__dirname, "seed_firestore_update.js")], {
    cwd: path.resolve(__dirname, ".."),
    env,
    encoding: "utf8",
  });
  if (result.status !== 0) {
    throw new Error(result.stderr || result.stdout || "seed_firestore_update.js failed");
  }
  return result.stdout.trim();
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (!options.apkPath) {
    throw new Error("Pass --apk <path-to-apk>.");
  }
  const repoRoot = path.resolve(__dirname, "..");
  const apkPath = path.isAbsolute(options.apkPath)
    ? path.resolve(options.apkPath)
    : path.resolve(repoRoot, options.apkPath);
  if (!fs.existsSync(apkPath)) {
    throw new Error(`APK not found: ${apkPath}`);
  }

  const projectId = resolveProjectId(options.projectId);
  const bucket = resolveBucket(options.bucket);
  const seed = readSeed(options.seedFile);
  const fileSize = fs.statSync(apkPath).size;
  const sha256 = computeSha256(apkPath);
  const objectName = options.objectName || defaultObjectName(seed);
  const downloadToken = crypto.randomUUID();
  const downloadUrl = buildDownloadUrl(bucket, objectName, downloadToken);
  const payload = updatePayload(seed, downloadUrl, sha256, fileSize);

  console.log(`Project: ${projectId}`);
  console.log(`Bucket: ${bucket}`);
  console.log(`APK: ${apkPath}`);
  console.log(`Object: ${objectName}`);
  console.log(`SHA-256: ${sha256}`);
  console.log(`Size: ${fileSize}`);
  console.log(`Output payload: ${options.outputJson}`);

  writeJson(options.outputJson, payload);

  if (options.dryRun) {
    console.log("Dry run complete. No upload or Firestore write was performed.");
    return;
  }

  const token = await loadAccessToken();
  const sessionUrl = await startResumableUpload({
    token,
    bucket,
    objectName,
    fileSize,
    downloadToken,
  });
  await uploadFileToSession(sessionUrl, apkPath, fileSize);
  const objectMetadata = await readObjectMetadata(token, bucket, objectName);
  const firestoreOutput = runFirestoreSeed(options.outputJson, projectId);

  console.log("");
  console.log("Upload complete.");
  console.log(`Storage object: ${objectMetadata?.name || objectName}`);
  console.log(`Storage generation: ${objectMetadata?.generation || "-"}`);
  console.log(`Download URL: ${downloadUrl}`);
  console.log("");
  console.log(firestoreOutput);
}

main().catch((error) => {
  console.error(error.message || error);
  process.exitCode = 1;
});
