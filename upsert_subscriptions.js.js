// upsert_subscriptions.js

const admin = require("firebase-admin");
const fs = require("fs");
const path = require("path");
const csv = require("csv-parser");

// =========================
// Firebase Admin Init
// =========================
const serviceAccount = require("./serviceAccountKey.json");

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: "go-play-720c1",
});

const db = admin.firestore();

// =========================
// Config
// =========================
const CSV_FILE_PATH = path.join(__dirname, "data.csv");
const COLLECTION_NAME = "subscriptions";

// จากข้อมูลจริงของคุณ
const EXPIRY_DATE_COLUMN_INDEX = 8;
const EMAIL_COLUMN_INDEX = 10;

// Firestore batch limit = 500 writes
// 1 row = 2 writes (main doc + log)
const MAX_ROWS_PER_BATCH = 250;

// =========================
// Helpers
// =========================
function normalizeEmail(email) {
  return String(email || "").trim().toLowerCase();
}

function isValidEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalizeEmail(email));
}

function isValidDateString(dateStr) {
  return /^\d{4}-\d{2}-\d{2}$/.test(String(dateStr || "").trim());
}

function isSkippableExpiry(expiryDate) {
  const value = String(expiryDate || "").trim();
  if (!value) return true;
  if (value.toUpperCase() === "N/A") return true;
  return false;
}

// แปลง YYYY-MM-DD → Date ตอนจบวัน
function parseYyyyMmDdToDateEndOfDay(dateStr) {
  const [year, month, day] = String(dateStr).split("-").map(Number);
  return new Date(year, month - 1, day, 23, 59, 59, 999);
}

function buildStatus(expiryDateStr) {
  const now = new Date();
  const expiry = parseYyyyMmDdToDateEndOfDay(expiryDateStr);
  return expiry >= now ? "active" : "expired";
}

// ถ้า email ซ้ำใน CSV → เอาวันที่มากสุด
function chooseLatestExpiry(existing, incoming) {
  const a = parseYyyyMmDdToDateEndOfDay(existing.expiryDate);
  const b = parseYyyyMmDdToDateEndOfDay(incoming.expiryDate);
  return b > a ? incoming : existing;
}

// =========================
// Read + Filter CSV
// =========================
async function readAndFilterCsv() {
  return new Promise((resolve, reject) => {
    const uniqueMap = new Map();
    let totalRows = 0;
    let skippedRows = 0;

    fs.createReadStream(CSV_FILE_PATH)
      .pipe(csv({ headers: false }))
      .on("data", (row) => {
        totalRows++;

        try {
          const rawExpiry = String(row[EXPIRY_DATE_COLUMN_INDEX] || "").trim();
          const rawEmail = String(row[EMAIL_COLUMN_INDEX] || "").trim();

          if (isSkippableExpiry(rawExpiry)) {
            skippedRows++;
            return;
          }

          if (!rawEmail) {
            skippedRows++;
            return;
          }

          if (!isValidDateString(rawExpiry)) {
            skippedRows++;
            return;
          }

          if (!isValidEmail(rawEmail)) {
            skippedRows++;
            return;
          }

          const email = normalizeEmail(rawEmail);
          const expiryDate = rawExpiry;

          const item = { email, expiryDate };

          if (!uniqueMap.has(email)) {
            uniqueMap.set(email, item);
          } else {
            const existing = uniqueMap.get(email);
            uniqueMap.set(email, chooseLatestExpiry(existing, item));
          }
        } catch (err) {
          skippedRows++;
        }
      })
      .on("end", () => {
        const rows = Array.from(uniqueMap.values());

        console.log("========== CSV SUMMARY ==========");
        console.log(`Total rows read      : ${totalRows}`);
        console.log(`Skipped invalid rows : ${skippedRows}`);
        console.log(`Valid unique emails  : ${rows.length}`);
        console.log("================================");

        resolve(rows);
      })
      .on("error", reject);
  });
}

// =========================
// Commit One Batch
// =========================
async function commitBatch(rows, batchNumber) {
  const batch = db.batch();

  for (const item of rows) {
    const { email, expiryDate } = item;

    const expiryDateObj = parseYyyyMmDdToDateEndOfDay(expiryDate);
    const expiryTimestamp = admin.firestore.Timestamp.fromDate(expiryDateObj);
    const status = buildStatus(expiryDate);

    // ใช้ emailLower เป็น Document ID → Upsert
    const docRef = db.collection(COLLECTION_NAME).doc(email);
    const logRef = docRef.collection("logs").doc();

    batch.set(
      docRef,
      {
        email: email,
        emailLower: email,
        expiryDate: expiryTimestamp,
        expiryDateText: expiryDate,
        status: status,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: "csv_import",
        source: "csv",
      },
      { merge: true } // สำคัญ → ถ้ามี doc อยู่แล้วจะ update แทน
    );

    batch.set(logRef, {
      action: "upsert",
      after: {
        email: email,
        expiryDateText: expiryDate,
        status: status,
        source: "csv",
      },
      changedAt: admin.firestore.FieldValue.serverTimestamp(),
      changedBy: "csv_import",
    });
  }

  await batch.commit();
  console.log(`Committed batch #${batchNumber} (${rows.length} rows)`);
}

// =========================
// Import
// =========================
async function importRowsToFirestore(rows) {
  let imported = 0;
  let batchNumber = 0;

  for (let i = 0; i < rows.length; i += MAX_ROWS_PER_BATCH) {
    const chunk = rows.slice(i, i + MAX_ROWS_PER_BATCH);
    batchNumber++;

    await commitBatch(chunk, batchNumber);

    imported += chunk.length;
    console.log(`Imported so far: ${imported}`);
  }

  return imported;
}

// =========================
// Main
// =========================
async function main() {
  try {
    console.log("START UPSERT");
    console.log(`Project ID : ${admin.app().options.projectId}`);
    console.log(`CSV path   : ${CSV_FILE_PATH}`);
    console.log(`CSV exists : ${fs.existsSync(CSV_FILE_PATH)}`);
    console.log("");

    if (!fs.existsSync(CSV_FILE_PATH)) {
      throw new Error(`CSV file not found: ${CSV_FILE_PATH}`);
    }

    const rows = await readAndFilterCsv();

    if (!rows.length) {
      console.log("No valid rows.");
      process.exit(0);
    }

    const imported = await importRowsToFirestore(rows);

    console.log("");
    console.log("========== UPSERT DONE ==========");
    console.log(`Processed rows: ${imported}`);
    console.log(`Collection    : ${COLLECTION_NAME}`);
    console.log("=================================");
    process.exit(0);
  } catch (err) {
    console.error("Import failed:");
    console.error(err);
    process.exit(1);
  }
}

main();