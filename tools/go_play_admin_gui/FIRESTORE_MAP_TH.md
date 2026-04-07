# GO_PLAY Firestore Map

เอกสารนี้สรุป path สำคัญของ Firestore สำหรับระบบ GO_PLAY ในภาษาไทย เพื่อใช้คู่กับเครื่องมือ admin GUI

## users/{uid}

- โปรไฟล์หลักของผู้ใช้ + subscription ปัจจุบัน + สถิติ active device
- Field เด่น:
  - `email`
  - `displayName`
  - `subscription.plan`
  - `subscription.status`
  - `subscription.expireAt`
  - `subscription.maxDevices`
  - `subscription.version`
  - `stats.activeDeviceCount`
- หมายเหตุสำคัญ:
  - path นี้เหมาะกับข้อมูลบัญชี / metadata
  - การแก้ `subscription.expireAt` อย่างเดียว ไม่ควรถูกตีความว่าเปิดสิทธิใช้งานจริงเสมอ

## users/{uid}/devices/{sessionId}

- รายการ session/device ที่ผูกกับ user
- ใช้กับ:
  - registerDeviceSession
  - validateDeviceSession
  - heartbeatDeviceSession
  - logoutDeviceSession
  - force logout all devices

## users/{uid}/entitlements/{packageId}

- สิทธิใช้งานของแพ็กเกจแต่ละตัว
- ใช้เช็กว่า user ยังใช้งาน YouTube ได้หรือไม่
- ในระบบปัจจุบัน `getPackageAccessState` อ่านจาก collection นี้เป็นหลัก
- ถ้าต้องการต่ออายุ, grant, block, หรือชดเชยสิทธิจริง ให้แก้ที่นี่

## users/{uid}/purchase_history/{paymentId}

- ประวัติซื้อของ user ที่ verify สำเร็จแล้ว

## users/{uid}/package_history/{eventId}

- audit trail ของการซื้อ, trial, manual correction
- ควรบันทึก event จาก admin tool เมื่อมีการ grant / deactivate entitlement

## orders/{orderId}

- คำสั่งซื้อก่อน verify สลิป
- สถานะหลัก:
  - `PENDING`
  - `PAID`
  - `EXPIRED`

## payments/{paymentId}

- หลักฐานธุรกรรมหลัง verify ผ่าน
- มี `thunderRaw` เก็บ payload ดิบ

## products/{packageId}

- แหล่งความจริงของแพ็กเกจ
- ตัวอย่าง id ที่ใช้อยู่:
  - `pkg_01`
  - `pkg_02`
  - `pkg_03`

## manual_correction_requests/{requestId}

- คำขอให้ admin ตรวจ/แก้เอง

## settings/payment_account

- ข้อมูลบัญชีรับโอนที่แอปใช้แสดง
- สำคัญ:
  - เป็น `document path` เดี่ยว
  - ไม่ใช่ `settings/payment_account/default`

## app_updates/android

- metadata ระบบอัปเดตแอป
- ใช้โดย setup app และ updater flow
