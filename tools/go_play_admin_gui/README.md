# GO_PLAY Admin GUI

โปรเจ็กต์นี้เป็นเครื่องมือ `Python + GUI` สำหรับทีม backend/admin ใช้ดูและจัดการ Firestore ของ GO_PLAY แบบละเอียด โดยเน้น:

- ดู `Firestore map` ภาษาไทย
- ดูภาพรวมระบบแบบ `monitor/dashboard`
- ค้นหา user และตรวจอุปกรณ์ / สิทธิ / ประวัติซื้อ
- ดู `orders / payments / manual correction`
- แก้ `products`, `settings/payment_account`, `app_updates/android`
- export report เป็น `JSON + CSV`

เครื่องมือนี้ตั้งใจให้เป็นโปรเจ็กต์แยกภายใต้ `tools/` เพื่อไม่ไปรบกวนตัวแอป GO_PLAY หลัก

## โครงสร้าง

- `main.py` ตัวเปิดโปรแกรม
- `requirements.txt` dependency ต่ำสุด
- `run_admin_gui.bat` ไฟล์เปิดใช้งานบน Windows
- `go_play_admin/schema_map.py` Firestore map ภาษาไทย
- `go_play_admin/firebase_backend.py` backend สำหรับ Firestore Admin SDK
- `go_play_admin/reporting.py` helper สำหรับ dashboard/report text
- `go_play_admin/gui_app.py` หน้าจอ GUI
- `FIRESTORE_MAP_TH.md` เอกสาร Firestore map ภาษาไทยแบบอ่านนอกโปรแกรมได้

## สิ่งที่เครื่องมือนี้อ่าน/แก้

### อ่าน/monitor

- `users/{uid}`
- `users/{uid}/devices/{sessionId}`
- `users/{uid}/entitlements/{packageId}`
- `users/{uid}/purchase_history/{paymentId}`
- `users/{uid}/package_history/{eventId}`
- `orders/{orderId}`
- `payments/{paymentId}`
- `products/{packageId}`
- `manual_correction_requests/{requestId}`
- `settings/payment_account`
- `app_updates/android`

### แก้ไขจาก GUI

- metadata subscription ของ user
- grant สิทธิแพ็กเกจจริงลง `users/{uid}/entitlements/{packageId}`
- grant สิทธิพิเศษ / admin grant ลง entitlement แบบกำหนด package id เอง
- ปิดสิทธิ entitlement ทั้งหมดของ user
- revoke ทุก device ของ user
- สถานะ `manual_correction_requests`
- ข้อมูล `products/*`
- `settings/payment_account`
- `app_updates/android`

## ติดตั้ง

```powershell
cd C:\Users\Master\Desktop\GO_PLAY\tools\go_play_admin_gui
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
```

## วิธีรัน

### แบบใช้ python ตรง

```powershell
cd C:\Users\Master\Desktop\GO_PLAY\tools\go_play_admin_gui
.venv\Scripts\activate
python main.py
```

### แบบกดไฟล์ batch

```powershell
cd C:\Users\Master\Desktop\GO_PLAY\tools\go_play_admin_gui
run_admin_gui.bat
```

## วิธีใช้งาน

1. เปิดโปรแกรม
2. เลือกไฟล์ `Service Account JSON`
3. ถ้าจำเป็นให้กรอก `Project ID`
4. กด `เชื่อม Firestore`
5. ใช้งานแต่ละแท็บ:

- `Dashboard`
- `Firestore Map`
- `Users / สิทธิ`
- `Orders / Payments / Correction`
- `Products / Settings / Update`
- `Reports / Export`
- `Explorer`

## ความหมายของปุ่มในหน้า Users / สิทธิ

- `บันทึก metadata เท่านั้น`
  - แก้เฉพาะ `users/{uid}.subscription`
  - เหมาะกับการแก้ข้อมูลบัญชี, วันหมดอายุที่ใช้แสดงผล, max devices
  - ยังไม่เปลี่ยนสิทธิใช้งานจริงของแอป
- `ให้สิทธิแพ็กเกจจริง`
  - เขียน entitlement ที่ package id ต้องมีอยู่ใน `products/*`
  - ใช้เมื่ออยากให้ user ใช้งานได้จริงตามแพ็กขายปกติ
  - ถ้าใส่ `Duration days` มากกว่า 0 ระบบจะบวกวันต่อจากวันหมดอายุเดิม/เวลาปัจจุบันให้อัตโนมัติ
  - ถ้าต้องการตั้งวันตรง ๆ ให้เว้น `Duration days` เป็น 0 แล้วกรอก `ExpireAt (ISO)`
- `ให้สิทธิพิเศษ`
  - เขียน entitlement แบบ package id อิสระ เช่น `admin_grant`
  - ใช้กับของแถม, ชดเชย, หรือ grant พิเศษ
  - กติกาเรื่อง `Duration days` และ `ExpireAt (ISO)` เหมือนกับปุ่ม grant แพ็กเกจจริง
- `ปิดสิทธิทุกแพ็กเกจจริง`
  - ปิด `active` ของ entitlement ทุกตัว
  - ใช้เมื่ออยากบล็อกการใช้งานจริงทันที

## ข้อสำคัญเรื่องวันใช้งาน

- ถ้าแก้แค่ `subscription.expireAt` หน้าบัญชีอาจเปลี่ยน แต่สิทธิใช้งานจริงอาจไม่เปลี่ยน
- สิทธิใช้งานจริงของ GO_PLAY ฝั่ง server อ่านจาก `users/{uid}/entitlements/*`
- เพราะฉะนั้น งานต่ออายุ/แก้สิทธิจริง ควรใช้ปุ่ม entitlement เป็นหลัก

## หมายเหตุสำคัญ

- ราคาแพ็กเกจหรือวันใช้งานต้องเชื่อจาก Firestore live เป็นหลัก
- seed files ใน repo ใช้เป็น reference ได้ แต่ไม่ควรถูกถือเป็น source of truth เสมอ
- `settings/payment_account` ในโปรเจ็กต์นี้เป็น `document path` ตรง ไม่ใช่ `settings/payment_account/default`
- `payments/*` ถูกปิด client read ใน rules จึงเหมาะกับ admin tool แบบนี้

## ข้อจำกัดปัจจุบัน

- GUI นี้ใช้ `Tkinter` เพื่อให้เบาและติดตั้งง่าย ไม่ได้ใช้ framework หนัก
- dashboard บางส่วนคำนวณจากการอ่านเอกสารจำนวนมาก ถ้าข้อมูลโตมากอาจต้องต่อยอดเป็น aggregated counters หรือ BigQuery ภายหลัง
- ไม่มีระบบ auth ภายในตัว GUI เอง การควบคุมสิทธิ์ขึ้นกับ service account ที่ใช้เปิด
