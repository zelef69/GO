const fs = require('fs');
const https = require('https');
const os = require('os');
const path = require('path');
const admin = require('firebase-admin');

const projectId = process.env.FIREBASE_PROJECT_ID || 'go-play-720c1';
const collection =
  process.env.GO_PLAY_UPDATE_FIRESTORE_COLLECTION || 'app_updates';
const documentId = process.env.GO_PLAY_UPDATE_FIRESTORE_DOCUMENT || 'android';
const jsonPath =
  process.env.GO_PLAY_UPDATE_JSON ||
  path.resolve(
    process.cwd(),
    'update',
    'firestore',
    'app_updates_android.template.json',
  );
const firestoreDatabase = '(default)';

function initializeAdmin() {
  if (admin.apps.length > 0) {
    return;
  }
  const serviceAccountPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (serviceAccountPath && fs.existsSync(serviceAccountPath)) {
    const serviceAccount = require(path.resolve(serviceAccountPath));
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
      projectId,
    });
    return;
  }
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId,
  });
}

function resolveFirebaseToolsConfigPath() {
  const appData = process.env.APPDATA;
  const candidates = [
    appData ? path.join(appData, 'configstore', 'firebase-tools.json') : '',
    path.join(os.homedir(), '.config', 'configstore', 'firebase-tools.json'),
  ].filter(Boolean);
  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) {
      return candidate;
    }
  }
  return '';
}

function loadFirebaseCliAccessToken() {
  const configPath = resolveFirebaseToolsConfigPath();
  if (!configPath) {
    return '';
  }
  try {
    const parsed = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    const token = (parsed?.tokens?.access_token || '').toString().trim();
    return token;
  } catch (_) {
    return '';
  }
}

function toFirestoreValue(value) {
  if (value === null || value === undefined) {
    return {nullValue: null};
  }
  if (typeof value === 'boolean') {
    return {booleanValue: value};
  }
  if (typeof value === 'number') {
    return Number.isInteger(value)
      ? {integerValue: value.toString()}
      : {doubleValue: value};
  }
  if (typeof value === 'string') {
    return {stringValue: value};
  }
  if (Array.isArray(value)) {
    return {
      arrayValue: {
        values: value.map((entry) => toFirestoreValue(entry)),
      },
    };
  }
  if (typeof value === 'object') {
    return {
      mapValue: {
        fields: toFirestoreFields(value),
      },
    };
  }
  return {stringValue: String(value)};
}

function toFirestoreFields(map) {
  const fields = {};
  for (const [key, value] of Object.entries(map)) {
    fields[key] = toFirestoreValue(value);
  }
  return fields;
}

function firestoreDocPath() {
  return `${collection}/${documentId}`
    .split('/')
    .map((segment) => encodeURIComponent(segment))
    .join('/');
}

function requestJson({method, endpoint, token, body}) {
  return new Promise((resolve, reject) => {
    const url = new URL(endpoint);
    const req = https.request(
      {
        protocol: url.protocol,
        hostname: url.hostname,
        path: `${url.pathname}${url.search}`,
        method,
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
      },
      (res) => {
        let raw = '';
        res.on('data', (chunk) => {
          raw += chunk;
        });
        res.on('end', () => {
          const status = res.statusCode || 0;
          let json = {};
          try {
            json = raw ? JSON.parse(raw) : {};
          } catch (_) {
            json = {};
          }
          if (status >= 200 && status < 300) {
            resolve(json);
            return;
          }
          const message =
            json?.error?.message ||
            raw ||
            `HTTP ${status} ${method} ${endpoint}`;
          reject(new Error(message));
        });
      },
    );
    req.on('error', reject);
    if (body) {
      req.write(body);
    }
    req.end();
  });
}

async function writeWithRestToken(payload, token) {
  const endpoint = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/${firestoreDatabase}/documents/${firestoreDocPath()}`;
  await requestJson({
    method: 'PATCH',
    endpoint,
    token,
    body: JSON.stringify({fields: toFirestoreFields(payload)}),
  });
}

async function verifyWithRestToken() {
  const token = loadFirebaseCliAccessToken();
  if (!token) {
    throw new Error(
      'No Firebase CLI access token found for verification (firebase login required)',
    );
  }
  const endpoint = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/${firestoreDatabase}/documents/${firestoreDocPath()}`;
  const data = await requestJson({
    method: 'GET',
    endpoint,
    token,
  });
  return {
    name: data?.name || `${collection}/${documentId}`,
    updateTime: data?.updateTime || '-',
  };
}

async function main() {
  if (!fs.existsSync(jsonPath)) {
    throw new Error(`Update JSON not found: ${jsonPath}`);
  }
  const raw = fs.readFileSync(jsonPath, 'utf8');
  const payload = JSON.parse(raw);

  let usedMethod = 'admin';
  try {
    initializeAdmin();
    const db = admin.firestore();
    await db.collection(collection).doc(documentId).set(payload, {merge: true});
  } catch (error) {
    const token = loadFirebaseCliAccessToken();
    if (!token) {
      throw new Error(
        `Admin SDK write failed: ${
          error?.message || String(error)
        } and no Firebase CLI token fallback found`,
      );
    }
    await writeWithRestToken(payload, token);
    usedMethod = 'rest-cli-token';
  }

  const verified = await verifyWithRestToken();

  console.log(
    `Seeded update document to ${collection}/${documentId} on project ${projectId} via ${usedMethod}`,
  );
  console.log(
    `Verified document: ${verified.name} (updateTime=${verified.updateTime})`,
  );
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
