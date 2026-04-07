from __future__ import annotations

import csv
import json
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

import firebase_admin
from firebase_admin import credentials, firestore


UTC = timezone.utc


def now_utc() -> datetime:
    return datetime.now(tz=UTC)


def to_datetime(value: Any) -> Optional[datetime]:
    if value is None:
        return None
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=UTC)
    if hasattr(value, "to_datetime"):
        dt = value.to_datetime()
        return dt if dt.tzinfo else dt.replace(tzinfo=UTC)
    if hasattr(value, "timestamp"):
        try:
            dt = value.timestamp().replace(tzinfo=UTC)
            return dt
        except Exception:
            return None
    if isinstance(value, str):
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
            return parsed if parsed.tzinfo else parsed.replace(tzinfo=UTC)
        except ValueError:
            return None
    return None


def to_iso(value: Any) -> str:
    dt = to_datetime(value)
    if dt is None:
        return "-"
    return dt.astimezone(UTC).isoformat()


def json_safe(value: Any) -> Any:
    if isinstance(value, dict):
        return {str(key): json_safe(raw) for key, raw in value.items()}
    if isinstance(value, list):
        return [json_safe(item) for item in value]
    if isinstance(value, tuple):
        return [json_safe(item) for item in value]
    dt = to_datetime(value)
    if dt is not None:
        return dt.astimezone(UTC).isoformat()
    return value


def get_nested(data: Dict[str, Any], path: str, default: Any = None) -> Any:
    current: Any = data
    for part in path.split("."):
        if not isinstance(current, dict) or part not in current:
            return default
        current = current[part]
    return current


@dataclass
class DashboardSnapshot:
    total_users: int
    active_users: int
    expired_users: int
    blocked_users: int
    total_active_devices: int
    total_products: int
    total_orders: int
    pending_orders: int
    paid_orders: int
    expired_orders: int
    total_payments: int
    total_revenue: float
    open_manual_requests: int
    expiring_7_days: int
    recent_orders: List[Dict[str, Any]]
    recent_payments: List[Dict[str, Any]]
    recent_manual_requests: List[Dict[str, Any]]


class FirestoreAdminBackend:
    def __init__(self) -> None:
        self._app: Optional[firebase_admin.App] = None
        self._db: Optional[firestore.Client] = None
        self._credential_path: Optional[Path] = None
        self._project_id: str = ""

    @property
    def is_connected(self) -> bool:
        return self._db is not None

    @property
    def project_id(self) -> str:
        return self._project_id

    @property
    def credential_path(self) -> str:
        return str(self._credential_path) if self._credential_path else ""

    @property
    def db(self) -> firestore.Client:
        if self._db is None:
            raise RuntimeError("ยังไม่ได้เชื่อม Firestore")
        return self._db

    def connect(self, credential_path: str, project_id: str = "") -> None:
        path = Path(credential_path).expanduser().resolve()
        if not path.exists():
            raise FileNotFoundError(f"ไม่พบไฟล์ service account: {path}")

        if self._app is not None:
            firebase_admin.delete_app(self._app)
            self._app = None
            self._db = None

        cred = credentials.Certificate(str(path))
        options: Dict[str, Any] = {}
        if project_id.strip():
            options["projectId"] = project_id.strip()
        self._app = firebase_admin.initialize_app(cred, options=options)
        self._db = firestore.client(app=self._app)
        self._credential_path = path
        self._project_id = self._app.project_id or project_id.strip()

    def _collection_docs(
        self, collection_path: str, limit: int = 100
    ) -> List[Tuple[str, Dict[str, Any]]]:
        docs = self.db.collection(collection_path).limit(limit).stream()
        return [(doc.id, doc.to_dict() or {}) for doc in docs]

    def _collection_docs_ordered(
        self,
        collection_path: str,
        order_field: str,
        descending: bool = True,
        limit: int = 50,
    ) -> List[Tuple[str, Dict[str, Any]]]:
        direction = (
            firestore.Query.DESCENDING if descending else firestore.Query.ASCENDING
        )
        docs = (
            self.db.collection(collection_path)
            .order_by(order_field, direction=direction)
            .limit(limit)
            .stream()
        )
        return [(doc.id, doc.to_dict() or {}) for doc in docs]

    def _iter_user_docs(self, limit: int = 1000) -> List[Tuple[str, Dict[str, Any]]]:
        return self._collection_docs("users", limit=limit)

    def _remaining_days(self, expire_at: Optional[datetime]) -> int:
        if expire_at is None:
            return -1
        diff = expire_at - now_utc()
        return int(diff.total_seconds() // 86400)

    def _decorate_user(self, uid: str, data: Dict[str, Any]) -> Dict[str, Any]:
        expire_at = to_datetime(get_nested(data, "subscription.expireAt"))
        return {
            "uid": uid,
            "email": data.get("email", ""),
            "displayName": data.get("displayName", ""),
            "plan": get_nested(data, "subscription.plan", ""),
            "status": get_nested(data, "subscription.status", ""),
            "expireAt": to_iso(expire_at),
            "remainingDays": self._remaining_days(expire_at),
            "maxDevices": get_nested(data, "subscription.maxDevices", 0),
            "activeDeviceCount": get_nested(data, "stats.activeDeviceCount", 0),
            "raw": json_safe(data),
        }

    def _decorate_order(self, order_id: str, data: Dict[str, Any]) -> Dict[str, Any]:
        return {
            "id": order_id,
            "uid": data.get("uid", ""),
            "packageId": data.get("packageId", ""),
            "status": data.get("status", ""),
            "expectedAmount": data.get("expectedAmount", 0),
            "paymentRef": data.get("paymentRef", ""),
            "createdAt": to_iso(data.get("createdAt")),
            "expiresAt": to_iso(data.get("expiresAt")),
            "lastVerifyCode": data.get("lastVerifyCode", ""),
            "raw": json_safe(data),
        }

    def _decorate_payment(self, payment_id: str, data: Dict[str, Any]) -> Dict[str, Any]:
        return {
            "id": payment_id,
            "uid": data.get("uid", ""),
            "packageId": data.get("packageId", ""),
            "orderId": data.get("orderId", ""),
            "amountInSlip": data.get("amountInSlip", 0),
            "expectedAmount": data.get("expectedAmount", 0),
            "createdAt": to_iso(data.get("createdAt")),
            "raw": json_safe(data),
        }

    def _decorate_manual_request(
        self, request_id: str, data: Dict[str, Any]
    ) -> Dict[str, Any]:
        return {
            "id": request_id,
            "uid": data.get("uid", ""),
            "email": data.get("email", ""),
            "packageId": data.get("packageId", ""),
            "status": data.get("status", ""),
            "note": data.get("note", ""),
            "createdAt": to_iso(data.get("createdAt")),
            "updatedAt": to_iso(data.get("updatedAt")),
            "raw": json_safe(data),
        }

    def get_dashboard(self) -> DashboardSnapshot:
        users = self._iter_user_docs(limit=5000)
        orders = self._collection_docs("orders", limit=5000)
        payments = self._collection_docs("payments", limit=5000)
        products = self._collection_docs("products", limit=100)
        manual_requests = self._collection_docs("manual_correction_requests", limit=1000)

        now = now_utc()
        active_users = 0
        expired_users = 0
        blocked_users = 0
        total_active_devices = 0
        expiring_7_days = 0

        for _, user in users:
            status = str(get_nested(user, "subscription.status", "")).lower()
            expire_at = to_datetime(get_nested(user, "subscription.expireAt"))
            total_active_devices += int(get_nested(user, "stats.activeDeviceCount", 0) or 0)
            if status == "blocked":
                blocked_users += 1
                continue
            if expire_at is None or expire_at <= now:
                expired_users += 1
            else:
                active_users += 1
                if expire_at <= now + timedelta(days=7):
                    expiring_7_days += 1

        pending_orders = 0
        paid_orders = 0
        expired_orders = 0
        for _, order in orders:
            status = str(order.get("status", "")).upper()
            if status == "PENDING":
                pending_orders += 1
            elif status == "PAID":
                paid_orders += 1
            elif status == "EXPIRED":
                expired_orders += 1

        total_revenue = 0.0
        for _, payment in payments:
            total_revenue += float(payment.get("amountInSlip") or payment.get("expectedAmount") or 0)

        open_manual_requests = 0
        for _, item in manual_requests:
            if str(item.get("status", "")).upper() == "OPEN":
                open_manual_requests += 1

        recent_orders = [
            self._decorate_order(doc_id, data)
            for doc_id, data in self._collection_docs_ordered(
                "orders", "createdAt", descending=True, limit=15
            )
        ]
        recent_payments = [
            self._decorate_payment(doc_id, data)
            for doc_id, data in self._collection_docs_ordered(
                "payments", "createdAt", descending=True, limit=15
            )
        ]
        recent_manual_requests = [
            self._decorate_manual_request(doc_id, data)
            for doc_id, data in self._collection_docs_ordered(
                "manual_correction_requests", "createdAt", descending=True, limit=15
            )
        ]

        return DashboardSnapshot(
            total_users=len(users),
            active_users=active_users,
            expired_users=expired_users,
            blocked_users=blocked_users,
            total_active_devices=total_active_devices,
            total_products=len(products),
            total_orders=len(orders),
            pending_orders=pending_orders,
            paid_orders=paid_orders,
            expired_orders=expired_orders,
            total_payments=len(payments),
            total_revenue=total_revenue,
            open_manual_requests=open_manual_requests,
            expiring_7_days=expiring_7_days,
            recent_orders=recent_orders,
            recent_payments=recent_payments,
            recent_manual_requests=recent_manual_requests,
        )

    def search_users(self, keyword: str, limit: int = 200) -> List[Dict[str, Any]]:
        keyword_lower = keyword.strip().lower()
        users = self._iter_user_docs(limit=5000)
        results: List[Dict[str, Any]] = []
        for uid, data in users:
            candidate = self._decorate_user(uid, data)
            haystack = " ".join(
                [
                    str(candidate["uid"]),
                    str(candidate["email"]),
                    str(candidate["displayName"]),
                    str(candidate["plan"]),
                    str(candidate["status"]),
                ]
            ).lower()
            if not keyword_lower or keyword_lower in haystack:
                results.append(candidate)
            if len(results) >= limit:
                break
        results.sort(key=lambda item: (str(item["status"]), str(item["email"])))
        return results

    def list_recent_users(self, limit: int = 100) -> List[Dict[str, Any]]:
        try:
            docs = self._collection_docs_ordered(
                "users", "updatedAt", descending=True, limit=limit
            )
        except Exception:
            docs = self._iter_user_docs(limit=limit)
        return [self._decorate_user(uid, data) for uid, data in docs]

    def search_users_fast(self, keyword: str, limit: int = 100) -> List[Dict[str, Any]]:
        keyword = keyword.strip()
        if not keyword:
            return self.list_recent_users(limit=limit)

        seen: Dict[str, Dict[str, Any]] = {}

        user_snap = self.db.collection("users").document(keyword).get()
        if user_snap.exists:
            seen[user_snap.id] = self._decorate_user(user_snap.id, user_snap.to_dict() or {})

        email_docs = (
            self.db.collection("users")
            .where("email", "==", keyword)
            .limit(limit)
            .stream()
        )
        for doc in email_docs:
            seen[doc.id] = self._decorate_user(doc.id, doc.to_dict() or {})

        if seen:
            return sorted(
                seen.values(),
                key=lambda item: (str(item["status"]), str(item["email"])),
            )[:limit]

        recent = self.list_recent_users(limit=max(limit * 3, 150))
        keyword_lower = keyword.lower()
        filtered = []
        for item in recent:
            haystack = " ".join(
                [
                    str(item["uid"]),
                    str(item["email"]),
                    str(item["displayName"]),
                    str(item["plan"]),
                    str(item["status"]),
                ]
            ).lower()
            if keyword_lower in haystack:
                filtered.append(item)
            if len(filtered) >= limit:
                break
        return filtered

    def get_user_summary(self, uid: str) -> Dict[str, Any]:
        user_ref = self.db.collection("users").document(uid)
        user_snap = user_ref.get()
        if not user_snap.exists:
            raise KeyError(f"ไม่พบผู้ใช้: {uid}")

        user_data = user_snap.to_dict() or {}
        summary = self._decorate_user(uid, user_data)
        return {
            "summary": summary,
            "documentPath": f"users/{uid}",
            "user": json_safe(user_data),
        }

    def get_user_subcollection(
        self, uid: str, subcollection: str, limit: int = 200
    ) -> Dict[str, Any]:
        user_ref = self.db.collection("users").document(uid)
        user_snap = user_ref.get()
        if not user_snap.exists:
            raise KeyError(f"ไม่พบผู้ใช้: {uid}")

        docs = list(user_ref.collection(subcollection).limit(limit).stream())
        rows = [{"id": doc.id, **json_safe(doc.to_dict() or {})} for doc in docs]
        return {
            "uid": uid,
            "path": f"users/{uid}/{subcollection}",
            "subcollection": subcollection,
            "limit": limit,
            "count": len(rows),
            "rows": rows,
        }

    def get_user_detail(self, uid: str) -> Dict[str, Any]:
        user_ref = self.db.collection("users").document(uid)
        user_snap = user_ref.get()
        if not user_snap.exists:
            raise KeyError(f"ไม่พบผู้ใช้: {uid}")

        user_data = user_snap.to_dict() or {}
        devices = [
            {"id": doc.id, **json_safe(doc.to_dict() or {})}
            for doc in user_ref.collection("devices").stream()
        ]
        entitlements = [
            {"id": doc.id, **json_safe(doc.to_dict() or {})}
            for doc in user_ref.collection("entitlements").stream()
        ]
        purchase_history = [
            {"id": doc.id, **json_safe(doc.to_dict() or {})}
            for doc in user_ref.collection("purchase_history").stream()
        ]
        package_history = [
            {"id": doc.id, **json_safe(doc.to_dict() or {})}
            for doc in user_ref.collection("package_history").stream()
        ]
        logs = [
            {"id": doc.id, **json_safe(doc.to_dict() or {})}
            for doc in user_ref.collection("logs").stream()
        ]

        return {
            "summary": self._decorate_user(uid, user_data),
            "documentPath": f"users/{uid}",
            "user": json_safe(user_data),
            "devices": devices,
            "entitlements": entitlements,
            "purchase_history": purchase_history,
            "package_history": package_history,
            "logs": logs,
        }

    def update_user_subscription(
        self,
        uid: str,
        plan: str,
        status: str,
        expire_at_iso: str,
        max_devices: int,
        extra_days: int,
        updated_by: str,
    ) -> None:
        expire_at = to_datetime(expire_at_iso)
        if expire_at is None:
            raise ValueError("รูปแบบ expireAt ไม่ถูกต้อง ใช้ ISO เช่น 2026-05-01T00:00:00+07:00")

        user_ref = self.db.collection("users").document(uid)
        snapshot = user_ref.get()
        if not snapshot.exists:
            raise KeyError(f"ไม่พบผู้ใช้: {uid}")

        current = snapshot.to_dict() or {}
        start_at = to_datetime(get_nested(current, "subscription.startAt")) or now_utc()
        version = int(get_nested(current, "subscription.version", 1) or 1)
        normalized_plan = plan.strip()
        normalized_status = status.strip().lower()
        actor = updated_by.strip() or "python_admin_tool"

        user_ref.set(
            {
                "subscription": {
                    "plan": normalized_plan,
                    "status": normalized_status,
                    "startAt": start_at,
                    "expireAt": expire_at,
                    "maxDevices": int(max_devices),
                    "extraDays": int(extra_days),
                    "version": version,
                    "updatedAt": firestore.SERVER_TIMESTAMP,
                    "updatedBy": actor,
                },
                "updatedAt": firestore.SERVER_TIMESTAMP,
            },
            merge=True,
        )

    def _grant_entitlement(
        self,
        uid: str,
        package_id: str,
        expire_at_iso: str,
        duration_days: int,
        note: str,
        updated_by: str,
        *,
        event_type: str,
        validate_product: bool,
    ) -> None:
        normalized_package_id = package_id.strip()
        if not normalized_package_id:
            raise ValueError("à¸à¸£à¸¸à¸“à¸²à¸£à¸°à¸šà¸¸ packageId")

        user_ref = self.db.collection("users").document(uid)
        snapshot = user_ref.get()
        if not snapshot.exists:
            raise KeyError(f"à¹„à¸¡à¹ˆà¸žà¸šà¸œà¸¹à¹‰à¹ƒà¸Šà¹‰: {uid}")

        if validate_product:
            product_ref = self.db.collection("products").document(normalized_package_id)
            if not product_ref.get().exists:
                raise KeyError(f"à¹„à¸¡à¹ˆà¸žà¸šà¹à¸žà¹‡à¸à¹€à¸à¸ˆà¸ˆà¸£à¸´à¸‡à¹ƒà¸™ products/{normalized_package_id}")

        current = snapshot.to_dict() or {}
        actor = updated_by.strip() or "python_admin_tool"
        now = now_utc()
        subscription_start_at = (
            to_datetime(get_nested(current, "subscription.startAt")) or now
        )
        subscription_version = int(get_nested(current, "subscription.version", 1) or 1)
        max_devices = int(get_nested(current, "subscription.maxDevices", 10) or 10)
        extra_days = int(get_nested(current, "subscription.extraDays", 0) or 0)

        entitlement_ref = user_ref.collection("entitlements").document(normalized_package_id)
        entitlement_snap = entitlement_ref.get()
        entitlement_data = entitlement_snap.to_dict() if entitlement_snap.exists else {}
        activated_at = (
            to_datetime(entitlement_data.get("activatedAt")) or subscription_start_at
        )
        before_expires_at = (
            to_datetime(entitlement_data.get("expiresAt"))
            or to_datetime(get_nested(current, "subscription.expireAt"))
            or activated_at
        )
        resolved_duration_days = int(duration_days or 0)
        raw_expire_at = to_datetime(expire_at_iso) if str(expire_at_iso).strip() else None

        if resolved_duration_days > 0:
            extension_base = before_expires_at if before_expires_at > now else now
            expire_at = extension_base + timedelta(days=resolved_duration_days)
        elif raw_expire_at is not None:
            expire_at = raw_expire_at
            resolved_duration_days = int(entitlement_data.get("durationDays") or 0)
            if resolved_duration_days <= 0:
                resolved_duration_days = max(
                    1, (expire_at.date() - activated_at.date()).days or 1
                )
        else:
            raise ValueError(
                "à¸à¸£à¸¸à¸“à¸²à¸£à¸°à¸šà¸¸ Duration days à¸«à¸£à¸·à¸­ ExpireAt (ISO) à¸­à¸¢à¹ˆà¸²à¸‡à¹ƒà¸”à¸­à¸¢à¹ˆà¸²à¸‡à¸«à¸™à¸¶à¹ˆà¸‡"
            )

        active_after = expire_at > now
        note_text = note.strip() or (
            "Granted from admin GUI."
            if validate_product
            else "Special entitlement granted from admin GUI."
        )

        batch = self.db.batch()
        batch.set(
            entitlement_ref,
            {
                "active": active_after,
                "packageId": normalized_package_id,
                "activatedAt": activated_at,
                "expiresAt": expire_at,
                "durationDays": resolved_duration_days,
                "updatedAt": firestore.SERVER_TIMESTAMP,
                "lastCorrectionAt": firestore.SERVER_TIMESTAMP,
                "lastCorrectionBy": actor,
                "lastCorrectionNote": note_text,
                "lastCorrectionDaysDelta": resolved_duration_days,
            },
            merge=True,
        )
        batch.set(
            user_ref,
            {
                "subscription": {
                    "plan": normalized_package_id,
                    "status": "active" if active_after else "expired",
                    "startAt": subscription_start_at,
                    "expireAt": expire_at,
                    "maxDevices": max_devices,
                    "extraDays": extra_days,
                    "version": subscription_version,
                    "updatedAt": firestore.SERVER_TIMESTAMP,
                    "updatedBy": actor,
                },
                "updatedAt": firestore.SERVER_TIMESTAMP,
            },
            merge=True,
        )
        batch.set(
            user_ref.collection("package_history").document(),
            {
                "uid": uid,
                "packageId": normalized_package_id,
                "eventType": event_type,
                "source": "python_admin_gui",
                "orderId": None,
                "paymentRef": None,
                "daysDelta": resolved_duration_days,
                "note": note_text,
                "beforeExpiresAt": before_expires_at,
                "afterExpiresAt": expire_at,
                "activeAfter": active_after,
                "createdAt": now,
                "createdBy": actor,
            },
        )
        batch.commit()

    def grant_product_entitlement(
        self,
        uid: str,
        package_id: str,
        expire_at_iso: str,
        duration_days: int,
        note: str,
        updated_by: str,
    ) -> None:
        self._grant_entitlement(
            uid,
            package_id,
            expire_at_iso,
            duration_days,
            note,
            updated_by,
            event_type="ADMIN_GRANT_PRODUCT",
            validate_product=True,
        )

    def grant_special_entitlement(
        self,
        uid: str,
        package_id: str,
        expire_at_iso: str,
        duration_days: int,
        note: str,
        updated_by: str,
    ) -> None:
        self._grant_entitlement(
            uid,
            package_id,
            expire_at_iso,
            duration_days,
            note,
            updated_by,
            event_type="ADMIN_GRANT_SPECIAL",
            validate_product=False,
        )

    def deactivate_all_entitlements(
        self, uid: str, note: str, updated_by: str
    ) -> Dict[str, Any]:
        user_ref = self.db.collection("users").document(uid)
        snapshot = user_ref.get()
        if not snapshot.exists:
            raise KeyError(f"à¹„à¸¡à¹ˆà¸žà¸šà¸œà¸¹à¹‰à¹ƒà¸Šà¹‰: {uid}")

        current = snapshot.to_dict() or {}
        actor = updated_by.strip() or "python_admin_tool"
        note_text = note.strip() or "Deactivated all entitlements from admin GUI."
        subscription_expire_at = to_datetime(get_nested(current, "subscription.expireAt"))
        package_id = str(get_nested(current, "subscription.plan", "") or "all")
        entitlement_docs = list(user_ref.collection("entitlements").stream())

        batch = self.db.batch()
        for doc in entitlement_docs:
            batch.set(
                doc.reference,
                {
                    "active": False,
                    "updatedAt": firestore.SERVER_TIMESTAMP,
                    "lastCorrectionAt": firestore.SERVER_TIMESTAMP,
                    "lastCorrectionBy": actor,
                    "lastCorrectionNote": note_text,
                    "lastCorrectionDaysDelta": 0,
                },
                merge=True,
            )

        batch.set(
            user_ref,
            {
                "subscription": {
                    "status": "blocked",
                    "updatedAt": firestore.SERVER_TIMESTAMP,
                    "updatedBy": actor,
                },
                "updatedAt": firestore.SERVER_TIMESTAMP,
            },
            merge=True,
        )
        batch.set(
            user_ref.collection("package_history").document(),
            {
                "uid": uid,
                "packageId": package_id,
                "eventType": "ADMIN_DEACTIVATE_ALL",
                "source": "python_admin_gui",
                "orderId": None,
                "paymentRef": None,
                "daysDelta": 0,
                "note": note_text,
                "beforeExpiresAt": subscription_expire_at,
                "afterExpiresAt": subscription_expire_at,
                "activeAfter": False,
                "createdAt": now_utc(),
                "createdBy": actor,
            },
        )
        batch.commit()
        return {"deactivatedEntitlements": len(entitlement_docs)}

    def revoke_all_devices(self, uid: str, updated_by: str) -> Dict[str, Any]:
        user_ref = self.db.collection("users").document(uid)
        snapshot = user_ref.get()
        if not snapshot.exists:
            raise KeyError(f"ไม่พบผู้ใช้: {uid}")

        current = snapshot.to_dict() or {}
        version = int(get_nested(current, "subscription.version", 1) or 1) + 1
        device_docs = list(user_ref.collection("devices").stream())

        batch = self.db.batch()
        for doc in device_docs:
            batch.set(
                doc.reference,
                {
                    "isActive": False,
                    "revoked": True,
                    "lastSeenAt": firestore.SERVER_TIMESTAMP,
                },
                merge=True,
            )
        batch.set(
            user_ref,
            {
                "subscription": {
                    "version": version,
                    "updatedAt": firestore.SERVER_TIMESTAMP,
                    "updatedBy": updated_by.strip() or "python_admin_tool",
                },
                "stats": {"activeDeviceCount": 0},
                "updatedAt": firestore.SERVER_TIMESTAMP,
            },
            merge=True,
        )
        batch.commit()

        return {
            "revokedDevices": len(device_docs),
            "newVersion": version,
        }

    def list_orders(self, status_filter: str = "", limit: int = 200) -> List[Dict[str, Any]]:
        docs = self._collection_docs_ordered("orders", "createdAt", descending=True, limit=limit)
        rows = [self._decorate_order(doc_id, data) for doc_id, data in docs]
        if status_filter.strip():
            wanted = status_filter.strip().upper()
            rows = [row for row in rows if str(row["status"]).upper() == wanted]
        return rows

    def list_payments(self, limit: int = 200) -> List[Dict[str, Any]]:
        docs = self._collection_docs_ordered("payments", "createdAt", descending=True, limit=limit)
        return [self._decorate_payment(doc_id, data) for doc_id, data in docs]

    def list_manual_requests(
        self, status_filter: str = "", limit: int = 200
    ) -> List[Dict[str, Any]]:
        docs = self._collection_docs_ordered(
            "manual_correction_requests", "createdAt", descending=True, limit=limit
        )
        rows = [self._decorate_manual_request(doc_id, data) for doc_id, data in docs]
        if status_filter.strip():
            wanted = status_filter.strip().upper()
            rows = [row for row in rows if str(row["status"]).upper() == wanted]
        return rows

    def update_manual_request_status(
        self, request_id: str, status: str, resolution_note: str, updated_by: str
    ) -> None:
        ref = self.db.collection("manual_correction_requests").document(request_id)
        if not ref.get().exists:
            raise KeyError(f"ไม่พบ request: {request_id}")
        ref.set(
            {
                "status": status.strip().upper(),
                "updatedAt": firestore.SERVER_TIMESTAMP,
                "resolvedAt": firestore.SERVER_TIMESTAMP,
                "resolvedBy": updated_by.strip() or "python_admin_tool",
                "resolutionNote": resolution_note.strip(),
            },
            merge=True,
        )

    def list_products(self) -> List[Dict[str, Any]]:
        docs = self._collection_docs("products", limit=100)
        rows: List[Dict[str, Any]] = []
        for doc_id, data in docs:
            rows.append(
                {
                    "id": doc_id,
                    "name": data.get("name", ""),
                    "price": data.get("price", 0),
                    "currency": data.get("currency", "THB"),
                    "durationDays": data.get("durationDays", 0),
                    "active": bool(data.get("active", False)),
                    "raw": json_safe(data),
                }
            )
        rows.sort(key=lambda item: str(item["id"]))
        return rows

    def update_product(
        self,
        package_id: str,
        name: str,
        price: float,
        currency: str,
        duration_days: int,
        active: bool,
    ) -> None:
        ref = self.db.collection("products").document(package_id)
        ref.set(
            {
                "name": name.strip(),
                "price": float(price),
                "currency": currency.strip() or "THB",
                "durationDays": int(duration_days),
                "active": bool(active),
            },
            merge=True,
        )

    def get_payment_account(self) -> Dict[str, Any]:
        snap = self.db.document("settings/payment_account").get()
        if not snap.exists:
            return {
                "bankDisplayName": "",
                "accountNameEn": "",
                "accountNameTh": "",
                "accountNumber": "",
            }
        return json_safe(snap.to_dict() or {})

    def update_payment_account(
        self,
        bank_display_name: str,
        account_name_en: str,
        account_name_th: str,
        account_number: str,
    ) -> None:
        self.db.document("settings/payment_account").set(
            {
                "bankDisplayName": bank_display_name.strip(),
                "accountNameEn": account_name_en.strip(),
                "accountNameTh": account_name_th.strip(),
                "accountNumber": account_number.strip(),
            },
            merge=True,
        )

    def get_app_update(self) -> Dict[str, Any]:
        snap = self.db.document("app_updates/android").get()
        if not snap.exists:
            return {}
        return json_safe(snap.to_dict() or {})

    def update_app_update(self, payload: Dict[str, Any]) -> None:
        release_notes = payload.get("releaseNotes", [])
        if isinstance(release_notes, str):
            release_notes = [line.strip() for line in release_notes.splitlines() if line.strip()]
        self.db.document("app_updates/android").set(
            {
                "appId": str(payload.get("appId", "")).strip(),
                "releaseChannel": str(payload.get("releaseChannel", "stable")).strip(),
                "latestVersionCode": int(payload.get("latestVersionCode", 0)),
                "latestVersionName": str(payload.get("latestVersionName", "")).strip(),
                "minimumSupportedVersionCode": int(payload.get("minimumSupportedVersionCode", 0)),
                "updaterEnabled": bool(payload.get("updaterEnabled", True)),
                "forceUpdate": bool(payload.get("forceUpdate", False)),
                "apkUrl": str(payload.get("apkUrl", "")).strip(),
                "apkSha256": str(payload.get("apkSha256", "")).strip(),
                "apkFileSizeBytes": int(payload.get("apkFileSizeBytes", 0)),
                "releaseNotes": release_notes,
                "rolloutPercent": int(payload.get("rolloutPercent", 100)),
            },
            merge=True,
        )

    def get_document_by_path(self, doc_path: str) -> Dict[str, Any]:
        snap = self.db.document(doc_path.strip().strip("/")).get()
        if not snap.exists:
            raise KeyError(f"ไม่พบ document: {doc_path}")
        data = snap.to_dict() or {}
        subcollections = [col.id for col in snap.reference.collections()]
        return {
            "path": doc_path.strip().strip("/"),
            "id": snap.id,
            "data": json_safe(data),
            "subcollections": subcollections,
        }

    def list_collection_by_path(self, collection_path: str, limit: int = 100) -> List[Dict[str, Any]]:
        path = collection_path.strip().strip("/")
        docs = self.db.collection(path).limit(limit).stream()
        rows: List[Dict[str, Any]] = []
        for doc in docs:
            rows.append(
                {
                    "id": doc.id,
                    "path": doc.reference.path,
                    "data": json_safe(doc.to_dict() or {}),
                }
            )
        return rows

    def generate_report_bundle(self) -> Dict[str, Any]:
        dashboard = self.get_dashboard()
        users = self.search_users("", limit=1000)
        orders = self.list_orders(limit=1000)
        payments = self.list_payments(limit=1000)
        manual_requests = self.list_manual_requests(limit=1000)
        products = self.list_products()
        payment_account = self.get_payment_account()
        app_update = self.get_app_update()
        return {
            "generatedAt": now_utc().isoformat(),
            "projectId": self.project_id,
            "dashboard": json_safe(dashboard.__dict__),
            "users": users,
            "orders": orders,
            "payments": payments,
            "manualRequests": manual_requests,
            "products": products,
            "paymentAccount": payment_account,
            "appUpdateAndroid": app_update,
        }

    def export_report_bundle(self, output_dir: str) -> Dict[str, str]:
        target_dir = Path(output_dir).expanduser().resolve()
        target_dir.mkdir(parents=True, exist_ok=True)
        timestamp = now_utc().strftime("%Y%m%d_%H%M%S")
        bundle = self.generate_report_bundle()

        json_path = target_dir / f"go_play_report_{timestamp}.json"
        with json_path.open("w", encoding="utf-8") as fp:
            json.dump(bundle, fp, ensure_ascii=False, indent=2)

        users_csv = target_dir / f"go_play_users_{timestamp}.csv"
        self._write_csv(
            users_csv,
            bundle["users"],
            ["uid", "email", "displayName", "plan", "status", "expireAt", "remainingDays", "maxDevices", "activeDeviceCount"],
        )
        orders_csv = target_dir / f"go_play_orders_{timestamp}.csv"
        self._write_csv(
            orders_csv,
            bundle["orders"],
            ["id", "uid", "packageId", "status", "expectedAmount", "paymentRef", "createdAt", "expiresAt", "lastVerifyCode"],
        )
        payments_csv = target_dir / f"go_play_payments_{timestamp}.csv"
        self._write_csv(
            payments_csv,
            bundle["payments"],
            ["id", "uid", "packageId", "orderId", "amountInSlip", "expectedAmount", "createdAt"],
        )
        manual_csv = target_dir / f"go_play_manual_requests_{timestamp}.csv"
        self._write_csv(
            manual_csv,
            bundle["manualRequests"],
            ["id", "uid", "email", "packageId", "status", "note", "createdAt", "updatedAt"],
        )

        return {
            "json": str(json_path),
            "usersCsv": str(users_csv),
            "ordersCsv": str(orders_csv),
            "paymentsCsv": str(payments_csv),
            "manualRequestsCsv": str(manual_csv),
        }

    def _write_csv(self, path: Path, rows: Iterable[Dict[str, Any]], columns: List[str]) -> None:
        with path.open("w", encoding="utf-8-sig", newline="") as fp:
            writer = csv.DictWriter(fp, fieldnames=columns)
            writer.writeheader()
            for row in rows:
                writer.writerow({key: row.get(key, "") for key in columns})
