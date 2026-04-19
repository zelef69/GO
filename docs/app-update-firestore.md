# App Update Firestore Map

เอกสารนี้อธิบาย source data ที่หน้า `Account -> อัปเดตแอป` ใช้อ่านจริงใน OneTabTube Android build ปัจจุบัน

## Firestore path

- document: `app_updates/android`

หน้า `Account` จะอ่าน document นี้ผ่าน Firebase Auth + App Check token แล้วสรุปผลในบล็อก:
- เวอร์ชันที่ใช้งานอยู่
- เวอร์ชันล่าสุด
- รายละเอียดอัปเดต
- สถานะปุ่มอัปเดต

## Supported fields

โค้ดฝั่งแอปรองรับ field ชุดนี้:

- `appId`
- `releaseChannel`
- `latestVersionCode`
- `latestVersionName`
- `minimumSupportedVersionCode`
- `updaterEnabled`
- `forceUpdate`
- `apkUrl`
- `apkSha256`
- `apkFileSizeBytes`
- `releaseNotes`
- `rolloutPercent`

`releaseNotes` ใช้ได้ทั้ง:
- string เดียว
- array ของ string

## Seed data in repo

- seed JSON: [app_update_android.seed.json](C:/Users/Master/Desktop/GO_PLAY/functions/seeds/app_update_android.seed.json)
- seed script: [seed-app-update.js](C:/Users/Master/Desktop/GO_PLAY/functions/scripts/seed-app-update.js)

ค่าตั้งต้นใน seed ตอนนี้อ้างอิง APK baseline ล่าสุดที่ติดตั้งอยู่บนเครื่อง:
- package: `com.onetabtube.browser_default`
- versionCode: `429000005`
- versionName: `1.90.1`
- SHA-256: `5dacfc43d6286ff8778c448ebda3b8f5d64fe2c10944ba3ad864abac8c184b4e`
- file size: `511846166`

หมายเหตุ:
- `apkUrl` ใน seed ตั้งเป็น placeholder เพื่อให้ schema ครบและหน้าแอปอ่านค่าได้
- ก่อนเปิดปล่อยอัปเดตจริง ต้องเปลี่ยน `apkUrl` ให้เป็น HTTPS URL ที่ดาวน์โหลด APK ได้จริง

## Dry run metadata only

```bash
npm --prefix functions run seed:app-update:dry -- --project go-play-720c1
```

## Write metadata to Firestore

```bash
npm --prefix functions run seed:app-update -- --project go-play-720c1
```

ถ้าเครื่องไม่มี ADC ให้ใช้ service account JSON:

```bash
npm --prefix functions run seed:app-update -- --project go-play-720c1 --service-account path/to/service-account.json
```

## Publish a real APK and update Firestore in one step

ถ้าต้องการปิดงาน updater metadata ให้พร้อมใช้งานจริง ให้ใช้คำสั่ง publish ซึ่งจะทำ 3 อย่างติดกัน:
- คำนวณ `SHA-256` และ file size จาก APK ที่ระบุ
- อัปโหลด APK ไป Firebase Storage
- เขียน `app_updates/android` ให้ชี้ `apkUrl` จริงพร้อม hash และขนาดไฟล์

ตัวอย่างใช้ APK baseline ที่ดึงจากเครื่อง:

```bash
npm --prefix functions run publish:app-update -- --project go-play-720c1 --apk \\wsl.localhost\Ubuntu\home\master\src_ext4\out\android_Release_arm64_multiabi\apks\OneTabTube.apk
```

ถ้าต้องการตรวจเฉย ๆ ว่าจะเขียน payload อะไรโดยยังไม่ upload:

```bash
npm --prefix functions run publish:app-update:dry -- --project go-play-720c1 --apk \\wsl.localhost\Ubuntu\home\master\src_ext4\out\android_Release_arm64\apks\OneTabTube.apk
```

ค่า default ของ publish flow ตอนนี้:
- bucket จะอ่านจาก `google-services.json`
- object path จะเป็นแนว:
  - `app-updates/android/<appId>/<versionCode>/OneTabTube-<versionName>-<versionCode>.apk`
- Firestore doc ปลายทางยังเป็น:
  - `app_updates/android`

## Expected UI behavior

ถ้า `app_updates/android` ยังไม่มี:
- หน้า Account จะแสดง `ยังไม่พบข้อมูลอัปเดตใน Firestore`

ถ้ามี document และ `latestVersionCode` เท่ากับเวอร์ชันที่ติดตั้ง:
- หน้า Account จะแสดงสถานะแนว `แอปเป็นเวอร์ชันล่าสุดแล้ว`

ถ้ามี document และ `latestVersionCode` มากกว่าเวอร์ชันที่ติดตั้ง:
- ปุ่มจะเปลี่ยนเป็นแนว `อัปเดตแอป`
- ระบบจะเริ่มเตรียมไฟล์อัปเดตตาม `apkUrl`, `apkSha256`, `apkFileSizeBytes`

## Safety notes

- อย่าเปิด `updaterEnabled=true` พร้อม bump `latestVersionCode` ถ้า `apkUrl` ยังไม่ใช่ไฟล์จริง
- อย่าเปลี่ยน `appId` ให้ไม่ตรงกับ package ที่ติดตั้งอยู่
- อย่าใช้ SHA-256 หรือ file size ที่ไม่ตรงกับ APK จริง เพราะตัว verifier จะ reject ก่อน install

## Current live closure status

Updater metadata batch ล่าสุดถูกปิดแล้วในโปรเจกต์ `go-play-720c1` ด้วย release baseline `429000010` ที่ยืนยันตรงกันทั้ง build artifact และ APK ที่ติดตั้งบนอุปกรณ์:

- artifact: `\\wsl.localhost\Ubuntu\home\master\src_ext4\out\android_Release_arm64_multiabi\apks\OneTabTube.apk`
- device proof: `artifacts/runtime_logs/device_stable_baseline_429000010_20260419.apk`
- package: `com.onetabtube.browser_default`
- versionCode: `429000010`
- versionName: `1.90.3`
- packaged ABIs: `arm64-v8a`, `armeabi-v7a`
- SHA-256: `0041f78f354ea9787087d2a5324a0ada3ee08ffb8cd8c1d3bdae0999839f647f`
- file size: `298165045`

หลักฐานอ้างอิง:

- build log: `artifacts/android_build/release_build_multiabi_429000010_20260419.log`
- publish log: `artifacts/firebase_build/publish_app_update_live_20260419_202318_429000010.log`
- publish payload: `artifacts/firebase_build/app_update_publish_payload_20260419_202318_429000010.json`
- Firestore readback: `artifacts/firebase_build/app_update_firestore_readback_20260419_429000010.json`
- Storage HEAD check: `artifacts/firebase_build/app_update_storage_head_20260419_429000010.txt`

สิ่งที่ถือว่า verify แล้ว:

- `app_updates/android` มี `apkUrl` จริง ไม่ใช่ placeholder
- URL ของ APK ตอบ `HTTP 200`
- `apkSha256` และ `apkFileSizeBytes` ตรงกับ build artifact
- APK ที่ติดตั้งบนอุปกรณ์ตรงกับ build artifact โดย hash เดียวกัน

สิ่งที่ยังอยู่นอก scope ของ metadata batch:

- true download/install flow จากเครื่องที่ยังติดตั้งเวอร์ชันเก่ากว่า `429000010` และต้องเห็น `429000010` เป็นอัปเดตใหม่
