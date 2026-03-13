# Firestore Update Document

ใช้ไฟล์ `app_updates_android.template.json` เป็น template สำหรับสร้างเอกสาร:

- Collection: `app_updates`
- Document: `android`

## ขั้นตอนใช้งาน

1. เปิด Firebase Console -> Firestore -> collection `app_updates`
2. สร้าง/แก้ document id `android`
3. คัดลอก fields จากไฟล์ template ลงใน document
4. เปลี่ยนค่า `apkUrl`, `apkSha256`, `latestVersionCode`, `latestVersionName` ทุกครั้งที่ปล่อยเวอร์ชันใหม่

หรือใช้คำสั่ง seed อัตโนมัติจากไฟล์ template:

```bash
node scripts/seed_firestore_update.js
```

## ตัวแปรตอนรันแอป

```bash
flutter run \
  --dart-define=GO_PLAY_UPDATE_SOURCE=firestore \
  --dart-define=GO_PLAY_UPDATE_FIRESTORE_COLLECTION=app_updates \
  --dart-define=GO_PLAY_UPDATE_FIRESTORE_DOCUMENT=android \
  --dart-define=GO_PLAY_UPDATE_APP_ID=com.example.go_play
```

## หมายเหตุ

- `apkSha256` ต้องเป็น hex 64 ตัวอักษร
- `publishedAt` แนะนำใช้ ISO8601 (UTC) เช่น `2026-03-13T09:00:00Z`
