from __future__ import annotations

from dataclasses import dataclass, field
from typing import Iterable, List


@dataclass(frozen=True)
class FirestoreField:
    name: str
    field_type: str
    description: str


@dataclass(frozen=True)
class FirestoreNode:
    path: str
    title: str
    purpose: str
    read_rule: str
    write_rule: str
    notes: str
    fields: List[FirestoreField] = field(default_factory=list)


FIRESTORE_SCHEMA_MAP: List[FirestoreNode] = [
    FirestoreNode(
        path="users/{uid}",
        title="โปรไฟล์ผู้ใช้หลัก",
        purpose="เก็บข้อมูลโปรไฟล์, subscription ปัจจุบัน, และสถิติ active device ของผู้ใช้แต่ละคน",
        read_rule="เจ้าของบัญชีอ่านได้เอง",
        write_rule="client เขียนได้เฉพาะ profile update ตาม rules; subscription สำคัญมาจาก server/admin",
        notes=(
            "เป็น root หลักของระบบสมาชิก GO_PLAY. หน้า Account, การล็อกเครื่อง, "
            "การตรวจอายุแพ็กเกจ และ trial 14 วันล้วนผูกกับ document นี้"
        ),
        fields=[
            FirestoreField("email", "string", "อีเมลที่ล็อกอินอยู่"),
            FirestoreField("displayName", "string", "ชื่อที่แสดงจาก Google/Firebase Auth"),
            FirestoreField("photoURL", "string", "รูปโปรไฟล์"),
            FirestoreField("createdAt", "timestamp", "เวลาสร้าง user"),
            FirestoreField("updatedAt", "timestamp", "เวลาอัปเดตล่าสุด"),
            FirestoreField("subscription.plan", "string", "แพ็กเกจปัจจุบัน เช่น trial_14d, pkg_01"),
            FirestoreField("subscription.status", "string", "active / expired / blocked"),
            FirestoreField("subscription.startAt", "timestamp", "วันเริ่มต้นสถานะแพ็กเกจ"),
            FirestoreField("subscription.expireAt", "timestamp", "วันหมดอายุที่แอปควรเช็กจาก server"),
            FirestoreField("subscription.maxDevices", "int", "จำนวนอุปกรณ์สูงสุดที่ใช้พร้อมกันได้"),
            FirestoreField("subscription.extraDays", "int", "จำนวนวันที่เติมเพิ่มจาก correction/admin"),
            FirestoreField("subscription.version", "int", "เลข version สำหรับ force logout ทุกอุปกรณ์"),
            FirestoreField("subscription.updatedAt", "timestamp", "เวลาปรับ subscription ล่าสุด"),
            FirestoreField("subscription.updatedBy", "string", "ผู้แก้ เช่น system_init, uid admin"),
            FirestoreField("stats.activeDeviceCount", "int", "จำนวน device docs ที่ active อยู่"),
        ],
    ),
    FirestoreNode(
        path="users/{uid}/devices/{sessionId}",
        title="รายการอุปกรณ์ที่ผูกกับบัญชี",
        purpose="ใช้ควบคุม limit 10 อุปกรณ์, heartbeat, revoke session และ validateDeviceSession",
        read_rule="เจ้าของบัญชีอ่านได้เอง",
        write_rule="client ห้ามเขียนตรง; server functions เป็นผู้สร้าง/อัปเดต",
        notes="ถ้า sessionVersion ไม่ตรงกับ subscription.version แปลว่าควรถูกบังคับออกจากระบบ",
        fields=[
            FirestoreField("deviceId", "string", "รหัสเครื่องฝั่งแอป"),
            FirestoreField("deviceName", "string", "ชื่อเครื่องที่แสดง"),
            FirestoreField("platform", "string", "android / อื่น ๆ"),
            FirestoreField("model", "string", "รุ่นอุปกรณ์"),
            FirestoreField("appVersion", "string", "เวอร์ชันแอปล่าสุดที่เครื่องรายงาน"),
            FirestoreField("loginAt", "timestamp", "เวลาล็อกอิน/สร้าง session"),
            FirestoreField("lastSeenAt", "timestamp", "heartbeat ล่าสุด"),
            FirestoreField("isActive", "bool", "ยัง active อยู่หรือไม่"),
            FirestoreField("revoked", "bool", "ถูก revoke หรือ logout แล้วหรือยัง"),
            FirestoreField("sessionVersion", "int", "snapshot ของ subscription.version ตอนลงทะเบียน"),
            FirestoreField("expireAtSnapshot", "timestamp", "snapshot วันหมดอายุตอนลงทะเบียน"),
        ],
    ),
    FirestoreNode(
        path="users/{uid}/entitlements/{packageId}",
        title="สิทธิใช้งานแพ็กเกจ",
        purpose="ใช้ตัดสินว่าผู้ใช้มีแพ็กเกจไหน active อยู่ และหมดอายุเมื่อไร",
        read_rule="เจ้าของบัญชีอ่านได้เอง",
        write_rule="client ห้ามเขียนตรง",
        notes="แพ็กเกจ trial และแพ็กเกจที่ชำระเงินแล้วจะมาสะสม/ต่ออายุใน collection นี้",
        fields=[
            FirestoreField("active", "bool", "สิทธิยัง active อยู่หรือไม่"),
            FirestoreField("packageId", "string", "รหัสแพ็กเกจ"),
            FirestoreField("sourceOrderId", "string", "คำสั่งซื้อที่ทำให้สิทธินี้เกิดขึ้น"),
            FirestoreField("paymentRef", "string", "อ้างอิง payment/transRef"),
            FirestoreField("durationDays", "int", "จำนวนวันจากรายการนั้น"),
            FirestoreField("activatedAt", "timestamp", "วันเริ่ม active"),
            FirestoreField("expiresAt", "timestamp", "วันหมดอายุ"),
            FirestoreField("updatedAt", "timestamp", "อัปเดตล่าสุด"),
            FirestoreField("lastCorrectionAt", "timestamp", "เวลาที่ admin แก้ล่าสุด (ถ้ามี)"),
            FirestoreField("lastCorrectionBy", "string", "admin uid ที่แก้"),
            FirestoreField("lastCorrectionNote", "string", "หมายเหตุแก้ไข"),
            FirestoreField("lastCorrectionDaysDelta", "int", "วันที่เพิ่ม/ลดล่าสุด"),
        ],
    ),
    FirestoreNode(
        path="users/{uid}/purchase_history/{paymentId}",
        title="ประวัติการซื้อของผู้ใช้",
        purpose="เก็บ purchase history ที่หน้า Account/Admin สามารถอ่านย้อนหลังได้",
        read_rule="เจ้าของบัญชีอ่านได้เอง",
        write_rule="client ห้ามเขียนตรง",
        notes="สร้างเมื่อ verifyPackageSlip สำเร็จ และใช้ paymentRef เป็น document id",
        fields=[
            FirestoreField("uid", "string", "เจ้าของรายการ"),
            FirestoreField("packageId", "string", "แพ็กเกจที่ซื้อ"),
            FirestoreField("orderId", "string", "คำสั่งซื้อ"),
            FirestoreField("paymentRef", "string", "transRef จาก Thunder"),
            FirestoreField("status", "string", "PAID"),
            FirestoreField("expectedAmount", "number", "ราคาที่คาดหวังตาม products"),
            FirestoreField("amountInSlip", "number", "ยอดที่ Thunder อ่านจากสลิป"),
            FirestoreField("currency", "string", "สกุลเงิน"),
            FirestoreField("durationDays", "int", "จำนวนวันที่ได้"),
            FirestoreField("source", "string", "เช่น thunder_slip"),
            FirestoreField("storagePath", "string", "path ของสลิปใน Storage"),
            FirestoreField("slipSha256", "string", "ลายนิ้วมือไฟล์สลิป"),
            FirestoreField("paidAt", "timestamp", "เวลาจ่ายสำเร็จ"),
            FirestoreField("entitlementExpiresAt", "timestamp", "วันหมดอายุหลังบวกแพ็กเกจ"),
        ],
    ),
    FirestoreNode(
        path="users/{uid}/package_history/{eventId}",
        title="ประวัติการเปลี่ยนแปลงแพ็กเกจ",
        purpose="audit trail ของการซื้อ, trial, manual correction",
        read_rule="เจ้าของบัญชีอ่านได้เอง",
        write_rule="client ห้ามเขียนตรง",
        notes="เหมาะกับงานตรวจย้อนหลังว่าทำไมวันใช้งานเพิ่ม/ลด",
        fields=[
            FirestoreField("uid", "string", "เจ้าของรายการ"),
            FirestoreField("packageId", "string", "แพ็กเกจที่เกี่ยวข้อง"),
            FirestoreField("eventType", "string", "PURCHASE / MANUAL_CORRECTION / อื่น ๆ"),
            FirestoreField("source", "string", "thunder_slip / admin_manual / signup-trial"),
            FirestoreField("orderId", "string", "คำสั่งซื้อที่เกี่ยวข้อง"),
            FirestoreField("paymentRef", "string", "อ้างอิง payment"),
            FirestoreField("daysDelta", "int", "จำนวนวันที่เปลี่ยน"),
            FirestoreField("note", "string", "หมายเหตุ"),
            FirestoreField("beforeExpiresAt", "timestamp", "วันหมดอายุก่อนแก้"),
            FirestoreField("afterExpiresAt", "timestamp", "วันหมดอายุหลังแก้"),
            FirestoreField("activeAfter", "bool", "สิทธิยัง active หลังรายการนี้หรือไม่"),
            FirestoreField("createdAt", "timestamp", "เวลาบันทึก event"),
            FirestoreField("createdBy", "string", "system/admin ที่สร้าง event"),
        ],
    ),
    FirestoreNode(
        path="orders/{orderId}",
        title="คำสั่งซื้อแพ็กเกจ",
        purpose="ตัวกลางระหว่างการกดซื้อในแอปกับการ verify สลิป",
        read_rule="owner ของ order อ่านได้",
        write_rule="client ห้ามเขียนตรง",
        notes="order จะเริ่มเป็น PENDING และเปลี่ยนเป็น PAID หรือ EXPIRED",
        fields=[
            FirestoreField("uid", "string", "เจ้าของ order"),
            FirestoreField("packageId", "string", "รหัสแพ็กเกจ"),
            FirestoreField("expectedAmount", "number", "ยอดที่ต้องจ่ายจาก products"),
            FirestoreField("currency", "string", "THB"),
            FirestoreField("durationDays", "int", "จำนวนวันที่แพ็กเกจให้"),
            FirestoreField("status", "string", "PENDING / PAID / EXPIRED"),
            FirestoreField("createdAt", "timestamp", "เวลาสร้าง order"),
            FirestoreField("expiresAt", "timestamp", "หมดเวลาสำหรับ order นี้"),
            FirestoreField("slipPath", "string|null", "Storage path ของสลิป"),
            FirestoreField("slipSha256", "string|null", "hash ของสลิป"),
            FirestoreField("paymentRef", "string|null", "transRef เมื่อชำระสำเร็จ"),
            FirestoreField("lastVerifyCode", "string|null", "โค้ดผล verify ล่าสุด"),
            FirestoreField("lastVerifyMessage", "string|null", "ข้อความผล verify ล่าสุด"),
            FirestoreField("lastVerificationAt", "timestamp", "เวลาตรวจล่าสุด"),
            FirestoreField("paidAt", "timestamp", "เวลาชำระสำเร็จ"),
        ],
    ),
    FirestoreNode(
        path="payments/{paymentId}",
        title="ธุรกรรมการชำระเงิน",
        purpose="หลักฐานธุรกรรมสำเร็จที่ผูกกับ Thunder transRef",
        read_rule="client อ่านไม่ได้",
        write_rule="client เขียนไม่ได้",
        notes="ข้อมูลชุดนี้ควรมองผ่าน admin tool หรือ backend เท่านั้น",
        fields=[
            FirestoreField("uid", "string", "เจ้าของรายการ"),
            FirestoreField("orderId", "string", "คำสั่งซื้อที่เกี่ยวข้อง"),
            FirestoreField("packageId", "string", "แพ็กเกจ"),
            FirestoreField("expectedAmount", "number", "ยอดที่ควรเป็น"),
            FirestoreField("amountInSlip", "number", "ยอดที่อ่านจากสลิป"),
            FirestoreField("currency", "string", "THB"),
            FirestoreField("durationDays", "int", "จำนวนวันที่ให้"),
            FirestoreField("transRef", "string", "เลขอ้างอิงหลักจาก Thunder"),
            FirestoreField("storagePath", "string", "ตำแหน่งไฟล์สลิป"),
            FirestoreField("slipSha256", "string", "hash สลิป"),
            FirestoreField("createdAt", "timestamp", "เวลาสร้าง payment"),
            FirestoreField("thunderRaw", "map", "payload ดิบที่ Thunder ส่งกลับมา"),
        ],
    ),
    FirestoreNode(
        path="products/{packageId}",
        title="รายการแพ็กเกจที่ขาย",
        purpose="แหล่งความจริงเรื่องชื่อแพ็กเกจ ราคา และจำนวนวัน",
        read_rule="อ่านได้ทุกคน",
        write_rule="client เขียนไม่ได้",
        notes="แอปต้องอ่านราคาจริงจาก doc นี้ ไม่เชื่อค่าจาก client",
        fields=[
            FirestoreField("name", "string", "ชื่อแพ็กเกจที่แสดง"),
            FirestoreField("price", "number", "ราคา"),
            FirestoreField("currency", "string", "THB"),
            FirestoreField("durationDays", "int", "จำนวนวันใช้งาน"),
            FirestoreField("active", "bool", "พร้อมขายหรือไม่"),
        ],
    ),
    FirestoreNode(
        path="manual_correction_requests/{requestId}",
        title="คำขอแก้ไขรายการด้วยคน",
        purpose="รับเคสที่สลิปผิดปกติหรือผู้ใช้ต้องการให้ admin ตรวจสอบเอง",
        read_rule="admin อ่านได้ หรือ owner ของเคสอ่านได้",
        write_rule="client ห้ามเขียนตรง",
        notes="ใช้คู่กับ applyManualPackageCorrection ใน backend",
        fields=[
            FirestoreField("uid", "string", "เจ้าของเคส"),
            FirestoreField("email", "string", "อีเมลผู้ร้องขอ"),
            FirestoreField("packageId", "string", "แพ็กเกจที่เกี่ยวข้อง"),
            FirestoreField("orderId", "string|null", "คำสั่งซื้อที่อ้างถึง"),
            FirestoreField("paymentRef", "string|null", "paymentRef ที่อ้างถึง"),
            FirestoreField("note", "string", "รายละเอียดจากผู้ใช้/admin"),
            FirestoreField("status", "string", "OPEN / APPLIED / อื่น ๆ"),
            FirestoreField("createdAt", "timestamp", "เวลาสร้างคำขอ"),
            FirestoreField("updatedAt", "timestamp", "เวลาอัปเดตล่าสุด"),
            FirestoreField("resolvedAt", "timestamp", "เวลาปิดเคส"),
            FirestoreField("resolvedBy", "string", "admin ผู้ปิดเคส"),
            FirestoreField("resolutionNote", "string", "หมายเหตุการปิดเคส"),
            FirestoreField("appliedDaysDelta", "int", "จำนวนวันที่ admin แก้"),
        ],
    ),
    FirestoreNode(
        path="settings/payment_account",
        title="บัญชีรับโอน",
        purpose="แอปหน้า Buy package ใช้อ่านข้อมูลบัญชีจาก doc นี้โดยตรง",
        read_rule="ไม่ได้เปิด client read ใน rules ปัจจุบัน; ใช้ผ่าน backend/native wiring ตามโปรเจ็กต์",
        write_rule="ควรแก้โดย admin เท่านั้น",
        notes="เป็น doc เดี่ยว ไม่ใช่ collection ย่อย `default`",
        fields=[
            FirestoreField("bankDisplayName", "string", "ชื่อธนาคารที่จะแสดง"),
            FirestoreField("accountNameEn", "string", "ชื่อบัญชีภาษาอังกฤษ"),
            FirestoreField("accountNameTh", "string", "ชื่อบัญชีภาษาไทย"),
            FirestoreField("accountNumber", "string", "เลขบัญชี"),
        ],
    ),
    FirestoreNode(
        path="app_updates/android",
        title="metadata ระบบอัปเดตแอป",
        purpose="ตัว setup app และตัวอัปเดตใช้ดูว่ามีเวอร์ชันใหม่หรือไม่",
        read_rule="อ่านได้เฉพาะ doc android",
        write_rule="client เขียนไม่ได้",
        notes="เหมาะกับการ monitor release channel และ metadata การปล่อยอัปเดต",
        fields=[
            FirestoreField("appId", "string", "package/app id ที่ metadata นี้ใช้กับมัน"),
            FirestoreField("releaseChannel", "string", "stable / beta / internal"),
            FirestoreField("latestVersionCode", "int", "versionCode ล่าสุด"),
            FirestoreField("latestVersionName", "string", "versionName ล่าสุด"),
            FirestoreField("minimumSupportedVersionCode", "int", "ต่ำสุดที่ยังรองรับ"),
            FirestoreField("updaterEnabled", "bool", "เปิดระบบอัปเดตหรือไม่"),
            FirestoreField("forceUpdate", "bool", "บังคับอัปเดตหรือไม่"),
            FirestoreField("apkUrl", "string", "ลิงก์ดาวน์โหลด APK"),
            FirestoreField("apkSha256", "string", "checksum ของ APK"),
            FirestoreField("apkFileSizeBytes", "int", "ขนาดไฟล์"),
            FirestoreField("releaseNotes", "array", "release notes"),
            FirestoreField("rolloutPercent", "int", "เปอร์เซ็น rollout"),
        ],
    ),
]


def iter_schema_map() -> Iterable[FirestoreNode]:
    return FIRESTORE_SCHEMA_MAP


def render_schema_map_markdown() -> str:
    lines: List[str] = ["# GO_PLAY Firestore Map", ""]
    for node in FIRESTORE_SCHEMA_MAP:
        lines.append(f"## {node.title}")
        lines.append("")
        lines.append(f"- Path: `{node.path}`")
        lines.append(f"- Purpose: {node.purpose}")
        lines.append(f"- Read rule: {node.read_rule}")
        lines.append(f"- Write rule: {node.write_rule}")
        lines.append(f"- Notes: {node.notes}")
        lines.append("")
        lines.append("| Field | Type | Description |")
        lines.append("| --- | --- | --- |")
        for item in node.fields:
            lines.append(f"| `{item.name}` | `{item.field_type}` | {item.description} |")
        lines.append("")
    return "\n".join(lines)
