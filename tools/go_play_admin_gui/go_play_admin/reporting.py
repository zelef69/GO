from __future__ import annotations

from typing import Dict

from .firebase_backend import DashboardSnapshot


def build_dashboard_text(snapshot: DashboardSnapshot) -> str:
    lines = [
        "สรุปภาพรวม GO_PLAY",
        "",
        f"- ผู้ใช้ทั้งหมด: {snapshot.total_users}",
        f"- ผู้ใช้ active: {snapshot.active_users}",
        f"- ผู้ใช้ expired: {snapshot.expired_users}",
        f"- ผู้ใช้ blocked: {snapshot.blocked_users}",
        f"- ผู้ใช้ใกล้หมดอายุใน 7 วัน: {snapshot.expiring_7_days}",
        f"- จำนวนอุปกรณ์ active รวม: {snapshot.total_active_devices}",
        "",
        f"- แพ็กเกจที่มีขาย: {snapshot.total_products}",
        f"- orders ทั้งหมด: {snapshot.total_orders}",
        f"- orders pending: {snapshot.pending_orders}",
        f"- orders paid: {snapshot.paid_orders}",
        f"- orders expired: {snapshot.expired_orders}",
        "",
        f"- payments ทั้งหมด: {snapshot.total_payments}",
        f"- รายได้รวมตาม payments: {snapshot.total_revenue:,.2f} THB",
        f"- manual correction ที่ยังเปิด: {snapshot.open_manual_requests}",
    ]
    return "\n".join(lines)


def build_export_summary(paths: Dict[str, str]) -> str:
    lines = ["ส่งออกรายงานสำเร็จ", ""]
    for label, path in paths.items():
        lines.append(f"- {label}: {path}")
    return "\n".join(lines)
