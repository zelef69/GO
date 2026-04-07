from __future__ import annotations

import json
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk
from typing import Any, Dict, List

from .firebase_backend import FirestoreAdminBackend
from .reporting import build_dashboard_text, build_export_summary
from .schema_map import FIRESTORE_SCHEMA_MAP, render_schema_map_markdown


class GoPlayAdminApp:
    def __init__(self) -> None:
        self.backend = FirestoreAdminBackend()
        self.root = tk.Tk()
        self.root.title("GO_PLAY Admin + Monitor + Report")
        self._configure_window()

        self.status_var = tk.StringVar(value="ยังไม่เชื่อม Firestore")
        self.credential_var = tk.StringVar()
        self.project_var = tk.StringVar()
        self.user_search_var = tk.StringVar()
        self.orders_filter_var = tk.StringVar()
        self.manual_filter_var = tk.StringVar()
        self.current_user_id_var = tk.StringVar()

        self.user_plan_var = tk.StringVar()
        self.user_status_var = tk.StringVar()
        self.user_expire_var = tk.StringVar()
        self.user_max_devices_var = tk.StringVar()
        self.user_extra_days_var = tk.StringVar()
        self.user_updated_by_var = tk.StringVar(value="python_admin_tool")
        self.user_detail_limit_var = tk.StringVar(value="100")
        self.entitlement_package_var = tk.StringVar()
        self.entitlement_expire_var = tk.StringVar()
        self.entitlement_duration_var = tk.StringVar()
        self.entitlement_note_var = tk.StringVar(value="ให้สิทธิแพ็กเกจจริงจาก admin gui")
        self.special_package_var = tk.StringVar(value="admin_grant")
        self.special_expire_var = tk.StringVar()
        self.special_duration_var = tk.StringVar()
        self.special_note_var = tk.StringVar(value="ให้สิทธิพิเศษจาก admin gui")
        self.deactivate_note_var = tk.StringVar(value="ปิดสิทธิทุกแพ็กเกจจาก admin gui")

        self.manual_status_var = tk.StringVar(value="APPLIED")
        self.manual_resolution_note_var = tk.StringVar()
        self.manual_updated_by_var = tk.StringVar(value="python_admin_tool")

        self.product_id_var = tk.StringVar()
        self.product_name_var = tk.StringVar()
        self.product_price_var = tk.StringVar()
        self.product_currency_var = tk.StringVar(value="THB")
        self.product_duration_var = tk.StringVar()
        self.product_active_var = tk.BooleanVar(value=True)

        self.bank_display_var = tk.StringVar()
        self.account_name_en_var = tk.StringVar()
        self.account_name_th_var = tk.StringVar()
        self.account_number_var = tk.StringVar()

        self.update_app_id_var = tk.StringVar()
        self.update_channel_var = tk.StringVar()
        self.update_latest_code_var = tk.StringVar()
        self.update_latest_name_var = tk.StringVar()
        self.update_min_code_var = tk.StringVar()
        self.update_updater_enabled_var = tk.BooleanVar(value=True)
        self.update_force_var = tk.BooleanVar(value=False)
        self.update_url_var = tk.StringVar()
        self.update_sha_var = tk.StringVar()
        self.update_size_var = tk.StringVar()
        self.update_rollout_var = tk.StringVar(value="100")

        self.explorer_path_var = tk.StringVar()
        self.explorer_mode_var = tk.StringVar(value="document")

        self.selected_users: List[Dict[str, Any]] = []
        self.selected_orders: List[Dict[str, Any]] = []
        self.selected_payments: List[Dict[str, Any]] = []
        self.selected_manual_requests: List[Dict[str, Any]] = []
        self.selected_products: List[Dict[str, Any]] = []

        self._autofill_credential_path()
        self._build_layout()

    def _configure_window(self) -> None:
        screen_width = self.root.winfo_screenwidth()
        screen_height = self.root.winfo_screenheight()
        window_width = min(max(int(screen_width * 0.92), 1200), screen_width)
        window_height = min(max(int(screen_height * 0.9), 760), screen_height)
        offset_x = max((screen_width - window_width) // 2, 0)
        offset_y = max((screen_height - window_height) // 2, 0)

        self.root.geometry(f"{window_width}x{window_height}+{offset_x}+{offset_y}")
        self.root.minsize(1080, 700)
        self.root.resizable(True, True)

        windowing_system = str(self.root.tk.call("tk", "windowingsystem")).lower()
        if windowing_system == "win32":
            self.root.after(0, self._fit_windows_screen)

    def _fit_windows_screen(self) -> None:
        try:
            self.root.state("zoomed")
        except tk.TclError:
            pass

    def _autofill_credential_path(self) -> None:
        tool_root = Path(__file__).resolve().parent.parent
        for candidate in sorted(tool_root.glob("*.json")):
            try:
                payload = json.loads(candidate.read_text(encoding="utf-8"))
            except Exception:
                continue
            if payload.get("type") == "service_account":
                self.credential_var.set(str(candidate))
                if not self.project_var.get().strip():
                    self.project_var.set(str(payload.get("project_id", "")).strip())
                break

    def _build_layout(self) -> None:
        top = ttk.Frame(self.root, padding=12)
        top.pack(fill="x")
        ttk.Label(top, text="ไฟล์ Service Account JSON").grid(row=0, column=0, sticky="w")
        ttk.Entry(top, textvariable=self.credential_var, width=72).grid(row=0, column=1, sticky="ew", padx=8)
        ttk.Button(top, text="เลือกไฟล์", command=self.choose_credential).grid(row=0, column=2, padx=4)
        ttk.Label(top, text="Project ID (ถ้ามี)").grid(row=0, column=3, padx=(18, 0), sticky="w")
        ttk.Entry(top, textvariable=self.project_var, width=28).grid(row=0, column=4, sticky="w", padx=8)
        ttk.Button(top, text="เชื่อม Firestore", command=self.connect).grid(row=0, column=5, padx=4)
        top.columnconfigure(1, weight=1)

        ttk.Label(self.root, textvariable=self.status_var, padding=(12, 0, 12, 8), foreground="#0b5394").pack(anchor="w")

        self.notebook = ttk.Notebook(self.root)
        self.notebook.pack(fill="both", expand=True, padx=12, pady=(0, 12))

        self._build_dashboard_tab()
        self._build_schema_tab()
        self._build_users_tab()
        self._build_orders_tab()
        self._build_products_tab()
        self._build_reports_tab()
        self._build_explorer_tab()

    def _build_dashboard_tab(self) -> None:
        frame = ttk.Frame(self.notebook, padding=12)
        self.notebook.add(frame, text="Dashboard")

        actions = ttk.Frame(frame)
        actions.pack(fill="x")
        ttk.Button(actions, text="รีเฟรชภาพรวม", command=self.refresh_dashboard).pack(side="left")

        body = ttk.PanedWindow(frame, orient="horizontal")
        body.pack(fill="both", expand=True, pady=(12, 0))

        left = ttk.Frame(body)
        right = ttk.Frame(body)
        body.add(left, weight=1)
        body.add(right, weight=2)

        self.dashboard_text = tk.Text(left, wrap="word")
        self.dashboard_text.pack(fill="both", expand=True)

        notebook = ttk.Notebook(right)
        notebook.pack(fill="both", expand=True)
        self.recent_orders_tree = self._build_simple_tree(notebook, ["id", "packageId", "status", "expectedAmount", "createdAt"], "orders ล่าสุด")
        self.recent_payments_tree = self._build_simple_tree(notebook, ["id", "packageId", "amountInSlip", "createdAt"], "payments ล่าสุด")
        self.recent_manual_tree = self._build_simple_tree(notebook, ["id", "packageId", "status", "createdAt"], "manual requests ล่าสุด")

    def _build_schema_tab(self) -> None:
        frame = ttk.Frame(self.notebook, padding=12)
        self.notebook.add(frame, text="Firestore Map")

        pane = ttk.PanedWindow(frame, orient="horizontal")
        pane.pack(fill="both", expand=True)
        left = ttk.Frame(pane)
        right = ttk.Frame(pane)
        pane.add(left, weight=1)
        pane.add(right, weight=2)

        self.schema_list = tk.Listbox(left)
        self.schema_list.pack(fill="both", expand=True)
        for node in FIRESTORE_SCHEMA_MAP:
            self.schema_list.insert("end", f"{node.path} | {node.title}")
        self.schema_list.bind("<<ListboxSelect>>", self.on_schema_selected)

        self.schema_detail = tk.Text(right, wrap="word")
        self.schema_detail.pack(fill="both", expand=True)
        self.schema_detail.insert("1.0", render_schema_map_markdown())

    def _build_users_tab(self) -> None:
        frame = ttk.Frame(self.notebook, padding=12)
        self.notebook.add(frame, text="Users / สิทธิ")

        top = ttk.Frame(frame)
        top.pack(fill="x")
        ttk.Label(top, text="ค้นหาแบบเร็ว (UID / email / keyword ล่าสุด)").pack(side="left")
        ttk.Entry(top, textvariable=self.user_search_var, width=40).pack(side="left", padx=8)
        ttk.Button(top, text="ค้นหา", command=self.search_users).pack(side="left")
        ttk.Button(top, text="โหลดล่าสุด 100", command=self.load_recent_users).pack(side="left", padx=(8, 0))
        ttk.Button(top, text="ล้างรายการ", command=self.clear_user_results).pack(side="left", padx=(8, 0))

        pane = ttk.PanedWindow(frame, orient="horizontal")
        pane.pack(fill="both", expand=True, pady=(12, 0))
        left = ttk.Frame(pane)
        center = ttk.Frame(pane)
        right = ttk.Frame(pane)
        pane.add(left, weight=2)
        pane.add(center, weight=2)
        pane.add(right, weight=3)

        self.users_tree = ttk.Treeview(left, columns=("uid", "email", "status", "plan", "remainingDays"), show="headings")
        for col, text, width in [
            ("uid", "UID", 220),
            ("email", "อีเมล", 220),
            ("status", "สถานะ", 90),
            ("plan", "แพ็กเกจ", 100),
            ("remainingDays", "คงเหลือ(วัน)", 90),
        ]:
            self.users_tree.heading(col, text=text)
            self.users_tree.column(col, width=width, anchor="w")
        self.users_tree.pack(fill="both", expand=True)
        self.users_tree.bind("<<TreeviewSelect>>", self.on_user_selected)

        center_notebook = ttk.Notebook(center)
        center_notebook.pack(fill="both", expand=True)

        metadata_tab = ttk.Frame(center_notebook, padding=10)
        entitlement_tab = ttk.Frame(center_notebook, padding=10)
        special_tab = ttk.Frame(center_notebook, padding=10)
        access_tab = ttk.Frame(center_notebook, padding=10)
        inspect_tab = ttk.Frame(center_notebook, padding=10)
        center_notebook.add(metadata_tab, text="Metadata")
        center_notebook.add(entitlement_tab, text="สิทธิจริง")
        center_notebook.add(special_tab, text="สิทธิพิเศษ")
        center_notebook.add(access_tab, text="ปิดสิทธิ")
        center_notebook.add(inspect_tab, text="Inspect")

        form = ttk.LabelFrame(metadata_tab, text="แก้ metadata บัญชี", padding=10)
        form.pack(fill="x")
        self._label_entry(form, "UID", self.current_user_id_var, 0, state="readonly")
        self._label_entry(form, "Plan", self.user_plan_var, 1)
        self._label_entry(form, "Status", self.user_status_var, 2)
        self._label_entry(form, "ExpireAt (ISO)", self.user_expire_var, 3)
        self._label_entry(form, "Max devices", self.user_max_devices_var, 4)
        self._label_entry(form, "Extra days", self.user_extra_days_var, 5)
        self._label_entry(form, "Updated by", self.user_updated_by_var, 6)
        ttk.Button(form, text="บันทึก metadata เท่านั้น", command=self.save_user_subscription).grid(row=7, column=0, columnspan=2, sticky="ew", pady=(10, 4))
        ttk.Button(form, text="Revoke ทุกอุปกรณ์", command=self.revoke_user_devices).grid(row=8, column=0, columnspan=2, sticky="ew")

        entitlement_form = ttk.LabelFrame(entitlement_tab, text="ให้สิทธิแพ็กเกจจริง", padding=10)
        entitlement_form.pack(fill="x")
        self._label_entry(entitlement_form, "Package ID", self.entitlement_package_var, 0)
        self._label_entry(entitlement_form, "ExpireAt (ISO) กำหนดเอง", self.entitlement_expire_var, 1)
        self._label_entry(entitlement_form, "Duration days (+เพิ่ม)", self.entitlement_duration_var, 2)
        self._label_entry(entitlement_form, "หมายเหตุ", self.entitlement_note_var, 3)
        ttk.Button(
            entitlement_form,
            text="ให้สิทธิแพ็กเกจจริง",
            command=self.grant_real_entitlement,
        ).grid(row=4, column=0, columnspan=2, sticky="ew", pady=(8, 0))

        special_form = ttk.LabelFrame(special_tab, text="ให้สิทธิพิเศษ / admin grant", padding=10)
        special_form.pack(fill="x")
        self._label_entry(special_form, "Special package ID", self.special_package_var, 0)
        self._label_entry(special_form, "ExpireAt (ISO) กำหนดเอง", self.special_expire_var, 1)
        self._label_entry(special_form, "Duration days (+เพิ่ม)", self.special_duration_var, 2)
        self._label_entry(special_form, "หมายเหตุ", self.special_note_var, 3)
        ttk.Button(
            special_form,
            text="ให้สิทธิพิเศษ",
            command=self.grant_special_entitlement,
        ).grid(row=4, column=0, columnspan=2, sticky="ew", pady=(8, 0))

        access_form = ttk.LabelFrame(access_tab, text="จัดการสิทธิใช้งานจริง", padding=10)
        access_form.pack(fill="x")
        self._label_entry(access_form, "หมายเหตุ", self.deactivate_note_var, 0)
        ttk.Button(
            access_form,
            text="ปิดสิทธิทุกแพ็กเกจจริง",
            command=self.deactivate_all_entitlements,
        ).grid(row=1, column=0, columnspan=2, sticky="ew", pady=(8, 0))

        quick = ttk.LabelFrame(inspect_tab, text="โหลดรายละเอียดทีละส่วน", padding=10)
        quick.pack(fill="x")
        ttk.Label(quick, text="จำนวนสูงสุดต่อรายการ").grid(row=0, column=0, sticky="w", padx=(0, 8))
        ttk.Entry(quick, textvariable=self.user_detail_limit_var, width=10).grid(row=0, column=1, sticky="w")
        ttk.Button(quick, text="โหลดสรุป user", command=self.load_selected_user_summary).grid(row=1, column=0, columnspan=2, sticky="ew", pady=(8, 4))
        ttk.Button(quick, text="ดู devices", command=lambda: self.load_selected_user_subcollection("devices")).grid(row=2, column=0, columnspan=2, sticky="ew", pady=2)
        ttk.Button(quick, text="ดู entitlements", command=lambda: self.load_selected_user_subcollection("entitlements")).grid(row=3, column=0, columnspan=2, sticky="ew", pady=2)
        ttk.Button(quick, text="ดู purchase_history", command=lambda: self.load_selected_user_subcollection("purchase_history")).grid(row=4, column=0, columnspan=2, sticky="ew", pady=2)
        ttk.Button(quick, text="ดู package_history", command=lambda: self.load_selected_user_subcollection("package_history")).grid(row=5, column=0, columnspan=2, sticky="ew", pady=2)
        ttk.Button(quick, text="ดู logs", command=lambda: self.load_selected_user_subcollection("logs")).grid(row=6, column=0, columnspan=2, sticky="ew", pady=2)

        self.user_detail = tk.Text(right, wrap="word")
        self.user_detail.pack(fill="both", expand=True)

    def _build_orders_tab(self) -> None:
        frame = ttk.Frame(self.notebook, padding=12)
        self.notebook.add(frame, text="Orders / Payments / Correction")

        top = ttk.Frame(frame)
        top.pack(fill="x")
        ttk.Label(top, text="Filter orders").pack(side="left")
        ttk.Combobox(top, textvariable=self.orders_filter_var, values=["", "PENDING", "PAID", "EXPIRED"], width=12).pack(side="left", padx=6)
        ttk.Button(top, text="รีโหลด orders", command=self.load_orders).pack(side="left")
        ttk.Label(top, text="Filter manual").pack(side="left", padx=(18, 0))
        ttk.Combobox(top, textvariable=self.manual_filter_var, values=["", "OPEN", "APPLIED"], width=12).pack(side="left", padx=6)
        ttk.Button(top, text="รีโหลด manual", command=self.load_manual_requests).pack(side="left")
        ttk.Button(top, text="รีโหลด payments", command=self.load_payments).pack(side="left", padx=(8, 0))

        pane = ttk.PanedWindow(frame, orient="horizontal")
        pane.pack(fill="both", expand=True, pady=(12, 0))

        left = ttk.Notebook(pane)
        center = ttk.Frame(pane)
        right = ttk.Frame(pane)
        pane.add(left, weight=3)
        pane.add(center, weight=2)
        pane.add(right, weight=3)

        orders_tab = ttk.Frame(left)
        payments_tab = ttk.Frame(left)
        manual_tab = ttk.Frame(left)
        left.add(orders_tab, text="Orders")
        left.add(payments_tab, text="Payments")
        left.add(manual_tab, text="Manual")

        self.orders_tree = self._tree_in_frame(orders_tab, ["id", "packageId", "status", "expectedAmount", "createdAt"])
        self.orders_tree.bind("<<TreeviewSelect>>", self.on_order_selected)
        self.payments_tree = self._tree_in_frame(payments_tab, ["id", "packageId", "amountInSlip", "createdAt"])
        self.payments_tree.bind("<<TreeviewSelect>>", self.on_payment_selected)
        self.manual_tree = self._tree_in_frame(manual_tab, ["id", "packageId", "status", "createdAt"])
        self.manual_tree.bind("<<TreeviewSelect>>", self.on_manual_selected)

        manual_form = ttk.LabelFrame(center, text="จัดการ manual request", padding=10)
        manual_form.pack(fill="x")
        self._label_entry(manual_form, "สถานะใหม่", self.manual_status_var, 0)
        self._label_entry(manual_form, "หมายเหตุ", self.manual_resolution_note_var, 1)
        self._label_entry(manual_form, "Updated by", self.manual_updated_by_var, 2)
        ttk.Button(manual_form, text="บันทึกสถานะ request", command=self.save_manual_request_status).grid(row=3, column=0, columnspan=2, sticky="ew", pady=(10, 0))

        self.order_detail = tk.Text(right, wrap="word")
        self.order_detail.pack(fill="both", expand=True)

    def _build_products_tab(self) -> None:
        frame = ttk.Frame(self.notebook, padding=12)
        self.notebook.add(frame, text="Products / Settings / Update")

        pane = ttk.PanedWindow(frame, orient="horizontal")
        pane.pack(fill="both", expand=True)

        left = ttk.Frame(pane)
        center = ttk.Frame(pane)
        right = ttk.Frame(pane)
        pane.add(left, weight=2)
        pane.add(center, weight=2)
        pane.add(right, weight=3)

        ttk.Button(left, text="รีโหลด products", command=self.load_products).pack(fill="x")
        self.products_tree = ttk.Treeview(left, columns=("id", "name", "price", "durationDays", "active"), show="headings")
        for col, text, width in [
            ("id", "ID", 100),
            ("name", "ชื่อ", 220),
            ("price", "ราคา", 80),
            ("durationDays", "วัน", 70),
            ("active", "active", 70),
        ]:
            self.products_tree.heading(col, text=text)
            self.products_tree.column(col, width=width, anchor="w")
        self.products_tree.pack(fill="both", expand=True, pady=(8, 0))
        self.products_tree.bind("<<TreeviewSelect>>", self.on_product_selected)

        product_form = ttk.LabelFrame(center, text="แก้ products / payment account", padding=10)
        product_form.pack(fill="x")
        self._label_entry(product_form, "Package ID", self.product_id_var, 0, state="readonly")
        self._label_entry(product_form, "ชื่อแพ็กเกจ", self.product_name_var, 1)
        self._label_entry(product_form, "ราคา", self.product_price_var, 2)
        self._label_entry(product_form, "Currency", self.product_currency_var, 3)
        self._label_entry(product_form, "DurationDays", self.product_duration_var, 4)
        ttk.Checkbutton(product_form, text="เปิดขายอยู่", variable=self.product_active_var).grid(row=5, column=0, columnspan=2, sticky="w", pady=(4, 4))
        ttk.Button(product_form, text="บันทึก product", command=self.save_product).grid(row=6, column=0, columnspan=2, sticky="ew", pady=(6, 12))

        account_frame = ttk.LabelFrame(center, text="settings/payment_account", padding=10)
        account_frame.pack(fill="x", pady=(8, 0))
        self._label_entry(account_frame, "ธนาคาร", self.bank_display_var, 0)
        self._label_entry(account_frame, "ชื่อบัญชี EN", self.account_name_en_var, 1)
        self._label_entry(account_frame, "ชื่อบัญชี TH", self.account_name_th_var, 2)
        self._label_entry(account_frame, "เลขบัญชี", self.account_number_var, 3)
        ttk.Button(account_frame, text="บันทึกบัญชีรับโอน", command=self.save_payment_account).grid(row=4, column=0, columnspan=2, sticky="ew", pady=(6, 0))

        right_notebook = ttk.Notebook(right)
        right_notebook.pack(fill="both", expand=True)

        update_tab = ttk.Frame(right_notebook, padding=10)
        raw_tab = ttk.Frame(right_notebook, padding=10)
        right_notebook.add(update_tab, text="app_updates/android")
        right_notebook.add(raw_tab, text="รายละเอียด")

        self._label_entry(update_tab, "App ID", self.update_app_id_var, 0)
        self._label_entry(update_tab, "Channel", self.update_channel_var, 1)
        self._label_entry(update_tab, "Latest code", self.update_latest_code_var, 2)
        self._label_entry(update_tab, "Latest name", self.update_latest_name_var, 3)
        self._label_entry(update_tab, "Min support code", self.update_min_code_var, 4)
        ttk.Checkbutton(update_tab, text="updaterEnabled", variable=self.update_updater_enabled_var).grid(row=5, column=0, sticky="w")
        ttk.Checkbutton(update_tab, text="forceUpdate", variable=self.update_force_var).grid(row=5, column=1, sticky="w")
        self._label_entry(update_tab, "APK URL", self.update_url_var, 6)
        self._label_entry(update_tab, "APK SHA-256", self.update_sha_var, 7)
        self._label_entry(update_tab, "ขนาดไฟล์", self.update_size_var, 8)
        self._label_entry(update_tab, "Rollout %", self.update_rollout_var, 9)
        ttk.Label(update_tab, text="Release notes (1 บรรทัดต่อ 1 ข้อ)").grid(row=10, column=0, columnspan=2, sticky="w", pady=(8, 4))
        self.release_notes_text = tk.Text(update_tab, height=8)
        self.release_notes_text.grid(row=11, column=0, columnspan=2, sticky="nsew")
        update_tab.rowconfigure(11, weight=1)
        update_tab.columnconfigure(1, weight=1)
        ttk.Button(update_tab, text="บันทึก app update metadata", command=self.save_app_update).grid(row=12, column=0, columnspan=2, sticky="ew", pady=(8, 0))

        self.product_detail = tk.Text(raw_tab, wrap="word")
        self.product_detail.pack(fill="both", expand=True)

    def _build_reports_tab(self) -> None:
        frame = ttk.Frame(self.notebook, padding=12)
        self.notebook.add(frame, text="Reports / Export")

        top = ttk.Frame(frame)
        top.pack(fill="x")
        ttk.Button(top, text="สร้างสรุปรายงาน", command=self.refresh_report_preview).pack(side="left")
        ttk.Button(top, text="ส่งออก JSON + CSV", command=self.export_reports).pack(side="left", padx=(8, 0))

        self.report_text = tk.Text(frame, wrap="word")
        self.report_text.pack(fill="both", expand=True, pady=(12, 0))

    def _build_explorer_tab(self) -> None:
        frame = ttk.Frame(self.notebook, padding=12)
        self.notebook.add(frame, text="Explorer")

        top = ttk.Frame(frame)
        top.pack(fill="x")
        ttk.Combobox(top, textvariable=self.explorer_mode_var, values=["document", "collection"], width=12).pack(side="left")
        ttk.Entry(top, textvariable=self.explorer_path_var, width=72).pack(side="left", padx=8, fill="x", expand=True)
        ttk.Button(top, text="เปิด path", command=self.open_explorer_path).pack(side="left")

        self.explorer_text = tk.Text(frame, wrap="word")
        self.explorer_text.pack(fill="both", expand=True, pady=(12, 0))

    def _tree_in_frame(self, frame: ttk.Frame, columns: List[str]) -> ttk.Treeview:
        tree = ttk.Treeview(frame, columns=columns, show="headings")
        for col in columns:
            tree.heading(col, text=col)
            tree.column(col, width=160, anchor="w")
        tree.pack(fill="both", expand=True)
        return tree

    def _build_simple_tree(self, notebook: ttk.Notebook, columns: List[str], title: str) -> ttk.Treeview:
        frame = ttk.Frame(notebook, padding=8)
        notebook.add(frame, text=title)
        return self._tree_in_frame(frame, columns)

    def _label_entry(self, parent: ttk.Frame, label: str, variable: tk.Variable, row: int, state: str = "normal") -> None:
        ttk.Label(parent, text=label).grid(row=row, column=0, sticky="w", padx=(0, 8), pady=4)
        ttk.Entry(parent, textvariable=variable, state=state).grid(row=row, column=1, sticky="ew", pady=4)
        parent.columnconfigure(1, weight=1)

    def choose_credential(self) -> None:
        selected = filedialog.askopenfilename(
            title="เลือก Service Account JSON",
            filetypes=[("JSON", "*.json"), ("All files", "*.*")],
        )
        if selected:
            self.credential_var.set(selected)

    def connect(self) -> None:
        try:
            self.backend.connect(self.credential_var.get(), self.project_var.get())
            self.status_var.set(f"เชื่อม Firestore สำเร็จ | project={self.backend.project_id} | cred={self.backend.credential_path}")
            self.refresh_dashboard()
            self.load_orders()
            self.load_payments()
            self.load_manual_requests()
            self.load_products()
            self.load_payment_account()
            self.load_app_update()
            self.clear_user_results()
        except Exception as exc:
            messagebox.showerror("เชื่อม Firestore ไม่สำเร็จ", str(exc))

    def ensure_connected(self) -> bool:
        if not self.backend.is_connected:
            messagebox.showwarning("ยังไม่พร้อม", "กรุณาเชื่อม Firestore ก่อน")
            return False
        return True

    def refresh_dashboard(self) -> None:
        if not self.ensure_connected():
            return
        try:
            snapshot = self.backend.get_dashboard()
            self.dashboard_text.delete("1.0", "end")
            self.dashboard_text.insert("1.0", build_dashboard_text(snapshot))
            self._fill_tree(self.recent_orders_tree, snapshot.recent_orders, ["id", "packageId", "status", "expectedAmount", "createdAt"])
            self._fill_tree(self.recent_payments_tree, snapshot.recent_payments, ["id", "packageId", "amountInSlip", "createdAt"])
            self._fill_tree(self.recent_manual_tree, snapshot.recent_manual_requests, ["id", "packageId", "status", "createdAt"])
        except Exception as exc:
            messagebox.showerror("รีเฟรช dashboard ไม่สำเร็จ", str(exc))

    def on_schema_selected(self, _event: Any) -> None:
        selection = self.schema_list.curselection()
        if not selection:
            return
        node = FIRESTORE_SCHEMA_MAP[selection[0]]
        lines = [
            node.title,
            "",
            f"Path: {node.path}",
            f"Purpose: {node.purpose}",
            f"Read rule: {node.read_rule}",
            f"Write rule: {node.write_rule}",
            f"Notes: {node.notes}",
            "",
            "Fields:",
        ]
        for field in node.fields:
            lines.append(f"- {field.name} [{field.field_type}] : {field.description}")
        self.schema_detail.delete("1.0", "end")
        self.schema_detail.insert("1.0", "\n".join(lines))

    def search_users(self) -> None:
        self._load_users(self.user_search_var.get())

    def load_recent_users(self) -> None:
        self._load_users("", recent=True)

    def clear_user_results(self) -> None:
        self.selected_users = []
        self._fill_tree(self.users_tree, [], ["uid", "email", "status", "plan", "remainingDays"])
        self.current_user_id_var.set("")
        self.user_plan_var.set("")
        self.user_status_var.set("")
        self.user_expire_var.set("")
        self.user_max_devices_var.set("")
        self.user_extra_days_var.set("")
        self.user_detail.delete("1.0", "end")
        self.user_detail.insert("1.0", "ยังไม่ได้โหลดรายการผู้ใช้\n\nกด 'โหลดล่าสุด 100' หรือค้นหาด้วย UID / email ก่อน")

    def _load_users(self, keyword: str, recent: bool = False) -> None:
        if not self.ensure_connected():
            return
        try:
            if recent:
                self.selected_users = self.backend.list_recent_users(limit=100)
            else:
                self.selected_users = self.backend.search_users_fast(keyword, limit=100)
            self._fill_tree(
                self.users_tree,
                self.selected_users,
                ["uid", "email", "status", "plan", "remainingDays"],
            )
        except Exception as exc:
            messagebox.showerror("โหลด users ไม่สำเร็จ", str(exc))

    def on_user_selected(self, _event: Any) -> None:
        focus = self.users_tree.focus()
        if not focus:
            return
        user = self.selected_users[int(focus)]
        summary = user
        uid = str(summary["uid"])
        self.current_user_id_var.set(uid)
        self.user_plan_var.set(str(summary.get("plan", "")))
        self.user_status_var.set(str(summary.get("status", "")))
        self.user_expire_var.set(str(summary.get("expireAt", "")))
        self.user_max_devices_var.set(str(summary.get("maxDevices", "")))
        self.user_extra_days_var.set("")
        self.entitlement_package_var.set(str(summary.get("plan", "")))
        self.entitlement_expire_var.set(str(summary.get("expireAt", "")))
        self.entitlement_duration_var.set("")
        self.special_expire_var.set(str(summary.get("expireAt", "")))
        self.special_duration_var.set("")
        self.user_detail.delete("1.0", "end")
        self.user_detail.insert(
            "1.0",
            json.dumps(
                {
                    "hint": "โหลดเฉพาะสรุปแล้ว เพื่อให้หน้าลื่นขึ้น",
                    "important": [
                        "ปุ่ม metadata แก้เฉพาะ users/{uid}.subscription",
                        "สิทธิใช้งานจริงของแอปอ่านจาก users/{uid}/entitlements",
                        "ถ้าต้องการบล็อกการใช้งานจริง ให้ใช้ปุ่ม 'ปิดสิทธิทุกแพ็กเกจจริง'",
                    ],
                    "summary": summary,
                    "nextActions": [
                        "กด 'โหลดสรุป user' เพื่อดึง root document ล่าสุด",
                        "กดปุ่ม devices / entitlements / purchase_history / package_history / logs เพื่อดูทีละส่วน",
                    ],
                },
                ensure_ascii=False,
                indent=2,
            ),
        )

    def _selected_uid(self) -> str:
        uid = self.current_user_id_var.get().strip()
        if not uid:
            raise ValueError("กรุณาเลือก user ก่อน")
        return uid

    def _detail_limit(self) -> int:
        try:
            value = int(self.user_detail_limit_var.get())
        except ValueError as exc:
            raise ValueError("จำนวนสูงสุดต่อรายการต้องเป็นตัวเลข") from exc
        return max(1, min(value, 1000))

    def load_selected_user_summary(self) -> None:
        if not self.ensure_connected():
            return
        try:
            detail = self.backend.get_user_summary(self._selected_uid())
            summary = detail["summary"]
            self.user_plan_var.set(str(summary.get("plan", "")))
            self.user_status_var.set(str(summary.get("status", "")))
            self.user_expire_var.set(str(summary.get("expireAt", "")))
            self.user_max_devices_var.set(str(summary.get("maxDevices", "")))
            self.user_extra_days_var.set(str(detail["user"].get("subscription", {}).get("extraDays", "")))
            self.entitlement_package_var.set(str(summary.get("plan", "")))
            self.entitlement_expire_var.set(str(summary.get("expireAt", "")))
            self.special_expire_var.set(str(summary.get("expireAt", "")))
            self.user_detail.delete("1.0", "end")
            self.user_detail.insert("1.0", json.dumps(detail, ensure_ascii=False, indent=2))
        except Exception as exc:
            messagebox.showerror("โหลดสรุป user ไม่สำเร็จ", str(exc))

    def load_selected_user_subcollection(self, subcollection: str) -> None:
        if not self.ensure_connected():
            return
        try:
            detail = self.backend.get_user_subcollection(
                self._selected_uid(),
                subcollection,
                limit=self._detail_limit(),
            )
            self.user_detail.delete("1.0", "end")
            self.user_detail.insert("1.0", json.dumps(detail, ensure_ascii=False, indent=2))
        except Exception as exc:
            messagebox.showerror(f"โหลด {subcollection} ไม่สำเร็จ", str(exc))

    def save_user_subscription(self) -> None:
        if not self.ensure_connected():
            return
        try:
            self.backend.update_user_subscription(
                uid=self.current_user_id_var.get(),
                plan=self.user_plan_var.get(),
                status=self.user_status_var.get(),
                expire_at_iso=self.user_expire_var.get(),
                max_devices=int(self.user_max_devices_var.get()),
                extra_days=int(self.user_extra_days_var.get()),
                updated_by=self.user_updated_by_var.get(),
            )
            messagebox.showinfo("สำเร็จ", "บันทึก metadata subscription แล้ว (ยังไม่แตะ entitlement)")
            self._load_users(self.user_search_var.get())
        except Exception as exc:
            messagebox.showerror("บันทึกไม่สำเร็จ", str(exc))

    def grant_real_entitlement(self) -> None:
        if not self.ensure_connected():
            return
        try:
            self.backend.grant_product_entitlement(
                uid=self._selected_uid(),
                package_id=self.entitlement_package_var.get(),
                expire_at_iso=self.entitlement_expire_var.get(),
                duration_days=int(self.entitlement_duration_var.get() or 0),
                note=self.entitlement_note_var.get(),
                updated_by=self.user_updated_by_var.get(),
            )
            messagebox.showinfo("สำเร็จ", "ให้สิทธิแพ็กเกจจริงแล้ว")
            self._load_users(self.user_search_var.get())
            self.load_selected_user_summary()
        except Exception as exc:
            messagebox.showerror("ให้สิทธิแพ็กเกจจริงไม่สำเร็จ", str(exc))

    def grant_special_entitlement(self) -> None:
        if not self.ensure_connected():
            return
        try:
            self.backend.grant_special_entitlement(
                uid=self._selected_uid(),
                package_id=self.special_package_var.get(),
                expire_at_iso=self.special_expire_var.get(),
                duration_days=int(self.special_duration_var.get() or 0),
                note=self.special_note_var.get(),
                updated_by=self.user_updated_by_var.get(),
            )
            messagebox.showinfo("สำเร็จ", "ให้สิทธิพิเศษแล้ว")
            self._load_users(self.user_search_var.get())
            self.load_selected_user_summary()
        except Exception as exc:
            messagebox.showerror("ให้สิทธิพิเศษไม่สำเร็จ", str(exc))

    def deactivate_all_entitlements(self) -> None:
        if not self.ensure_connected():
            return
        try:
            result = self.backend.deactivate_all_entitlements(
                uid=self._selected_uid(),
                note=self.deactivate_note_var.get(),
                updated_by=self.user_updated_by_var.get(),
            )
            messagebox.showinfo(
                "สำเร็จ",
                f"ปิดสิทธิจริงแล้ว {result['deactivatedEntitlements']} รายการ",
            )
            self._load_users(self.user_search_var.get())
            self.load_selected_user_summary()
        except Exception as exc:
            messagebox.showerror("ปิดสิทธิไม่สำเร็จ", str(exc))

    def revoke_user_devices(self) -> None:
        if not self.ensure_connected():
            return
        try:
            result = self.backend.revoke_all_devices(
                self.current_user_id_var.get(),
                self.user_updated_by_var.get(),
            )
            messagebox.showinfo(
                "สำเร็จ",
                f"revoke {result['revokedDevices']} อุปกรณ์แล้ว | version ใหม่ {result['newVersion']}",
            )
            self._load_users(self.user_search_var.get())
        except Exception as exc:
            messagebox.showerror("revoke ไม่สำเร็จ", str(exc))

    def load_orders(self) -> None:
        if not self.ensure_connected():
            return
        try:
            self.selected_orders = self.backend.list_orders(self.orders_filter_var.get())
            self._fill_tree(self.orders_tree, self.selected_orders, ["id", "packageId", "status", "expectedAmount", "createdAt"])
        except Exception as exc:
            messagebox.showerror("โหลด orders ไม่สำเร็จ", str(exc))

    def load_payments(self) -> None:
        if not self.ensure_connected():
            return
        try:
            self.selected_payments = self.backend.list_payments()
            self._fill_tree(self.payments_tree, self.selected_payments, ["id", "packageId", "amountInSlip", "createdAt"])
        except Exception as exc:
            messagebox.showerror("โหลด payments ไม่สำเร็จ", str(exc))

    def load_manual_requests(self) -> None:
        if not self.ensure_connected():
            return
        try:
            self.selected_manual_requests = self.backend.list_manual_requests(self.manual_filter_var.get())
            self._fill_tree(self.manual_tree, self.selected_manual_requests, ["id", "packageId", "status", "createdAt"])
        except Exception as exc:
            messagebox.showerror("โหลด manual requests ไม่สำเร็จ", str(exc))

    def on_order_selected(self, _event: Any) -> None:
        focus = self.orders_tree.focus()
        if not focus:
            return
        item = self.selected_orders[int(focus)]
        self.order_detail.delete("1.0", "end")
        self.order_detail.insert("1.0", json.dumps(item, ensure_ascii=False, indent=2))

    def on_payment_selected(self, _event: Any) -> None:
        focus = self.payments_tree.focus()
        if not focus:
            return
        item = self.selected_payments[int(focus)]
        self.order_detail.delete("1.0", "end")
        self.order_detail.insert("1.0", json.dumps(item, ensure_ascii=False, indent=2))

    def on_manual_selected(self, _event: Any) -> None:
        focus = self.manual_tree.focus()
        if not focus:
            return
        item = self.selected_manual_requests[int(focus)]
        self.order_detail.delete("1.0", "end")
        self.order_detail.insert("1.0", json.dumps(item, ensure_ascii=False, indent=2))
        self.manual_resolution_note_var.set(str(item.get("note", "")))

    def save_manual_request_status(self) -> None:
        if not self.ensure_connected():
            return
        focus = self.manual_tree.focus()
        if not focus:
            messagebox.showwarning("ยังไม่พร้อม", "กรุณาเลือก manual request ก่อน")
            return
        item = self.selected_manual_requests[int(focus)]
        try:
            self.backend.update_manual_request_status(
                request_id=str(item["id"]),
                status=self.manual_status_var.get(),
                resolution_note=self.manual_resolution_note_var.get(),
                updated_by=self.manual_updated_by_var.get(),
            )
            messagebox.showinfo("สำเร็จ", "อัปเดตสถานะ request แล้ว")
            self.load_manual_requests()
        except Exception as exc:
            messagebox.showerror("อัปเดต request ไม่สำเร็จ", str(exc))

    def load_products(self) -> None:
        if not self.ensure_connected():
            return
        try:
            self.selected_products = self.backend.list_products()
            self._fill_tree(self.products_tree, self.selected_products, ["id", "name", "price", "durationDays", "active"])
        except Exception as exc:
            messagebox.showerror("โหลด products ไม่สำเร็จ", str(exc))

    def on_product_selected(self, _event: Any) -> None:
        focus = self.products_tree.focus()
        if not focus:
            return
        item = self.selected_products[int(focus)]
        self.product_id_var.set(str(item["id"]))
        self.product_name_var.set(str(item["name"]))
        self.product_price_var.set(str(item["price"]))
        self.product_currency_var.set(str(item["currency"]))
        self.product_duration_var.set(str(item["durationDays"]))
        self.product_active_var.set(bool(item["active"]))
        self.product_detail.delete("1.0", "end")
        self.product_detail.insert("1.0", json.dumps(item, ensure_ascii=False, indent=2))

    def save_product(self) -> None:
        if not self.ensure_connected():
            return
        try:
            self.backend.update_product(
                package_id=self.product_id_var.get(),
                name=self.product_name_var.get(),
                price=float(self.product_price_var.get()),
                currency=self.product_currency_var.get(),
                duration_days=int(self.product_duration_var.get()),
                active=bool(self.product_active_var.get()),
            )
            messagebox.showinfo("สำเร็จ", "บันทึก product แล้ว")
            self.load_products()
        except Exception as exc:
            messagebox.showerror("บันทึก product ไม่สำเร็จ", str(exc))

    def load_payment_account(self) -> None:
        if not self.ensure_connected():
            return
        try:
            data = self.backend.get_payment_account()
            self.bank_display_var.set(str(data.get("bankDisplayName", "")))
            self.account_name_en_var.set(str(data.get("accountNameEn", "")))
            self.account_name_th_var.set(str(data.get("accountNameTh", "")))
            self.account_number_var.set(str(data.get("accountNumber", "")))
        except Exception as exc:
            messagebox.showerror("โหลด payment account ไม่สำเร็จ", str(exc))

    def save_payment_account(self) -> None:
        if not self.ensure_connected():
            return
        try:
            self.backend.update_payment_account(
                bank_display_name=self.bank_display_var.get(),
                account_name_en=self.account_name_en_var.get(),
                account_name_th=self.account_name_th_var.get(),
                account_number=self.account_number_var.get(),
            )
            messagebox.showinfo("สำเร็จ", "บันทึกบัญชีรับโอนแล้ว")
        except Exception as exc:
            messagebox.showerror("บันทึกบัญชีรับโอนไม่สำเร็จ", str(exc))

    def load_app_update(self) -> None:
        if not self.ensure_connected():
            return
        try:
            data = self.backend.get_app_update()
            self.update_app_id_var.set(str(data.get("appId", "")))
            self.update_channel_var.set(str(data.get("releaseChannel", "")))
            self.update_latest_code_var.set(str(data.get("latestVersionCode", "")))
            self.update_latest_name_var.set(str(data.get("latestVersionName", "")))
            self.update_min_code_var.set(str(data.get("minimumSupportedVersionCode", "")))
            self.update_updater_enabled_var.set(bool(data.get("updaterEnabled", True)))
            self.update_force_var.set(bool(data.get("forceUpdate", False)))
            self.update_url_var.set(str(data.get("apkUrl", "")))
            self.update_sha_var.set(str(data.get("apkSha256", "")))
            self.update_size_var.set(str(data.get("apkFileSizeBytes", "")))
            self.update_rollout_var.set(str(data.get("rolloutPercent", "")))
            notes = data.get("releaseNotes", [])
            if not isinstance(notes, list):
                notes = []
            self.release_notes_text.delete("1.0", "end")
            self.release_notes_text.insert("1.0", "\n".join(str(note) for note in notes))
            self.product_detail.delete("1.0", "end")
            self.product_detail.insert("1.0", json.dumps({"paymentAccount": self.backend.get_payment_account(), "appUpdateAndroid": data}, ensure_ascii=False, indent=2))
        except Exception as exc:
            messagebox.showerror("โหลด app update ไม่สำเร็จ", str(exc))

    def save_app_update(self) -> None:
        if not self.ensure_connected():
            return
        try:
            payload = {
                "appId": self.update_app_id_var.get(),
                "releaseChannel": self.update_channel_var.get(),
                "latestVersionCode": int(self.update_latest_code_var.get()),
                "latestVersionName": self.update_latest_name_var.get(),
                "minimumSupportedVersionCode": int(self.update_min_code_var.get()),
                "updaterEnabled": bool(self.update_updater_enabled_var.get()),
                "forceUpdate": bool(self.update_force_var.get()),
                "apkUrl": self.update_url_var.get(),
                "apkSha256": self.update_sha_var.get(),
                "apkFileSizeBytes": int(self.update_size_var.get() or 0),
                "releaseNotes": self.release_notes_text.get("1.0", "end").strip(),
                "rolloutPercent": int(self.update_rollout_var.get() or 100),
            }
            self.backend.update_app_update(payload)
            messagebox.showinfo("สำเร็จ", "บันทึก app update metadata แล้ว")
            self.load_app_update()
        except Exception as exc:
            messagebox.showerror("บันทึก app update ไม่สำเร็จ", str(exc))

    def refresh_report_preview(self) -> None:
        if not self.ensure_connected():
            return
        try:
            snapshot = self.backend.get_dashboard()
            bundle = self.backend.generate_report_bundle()
            preview = {
                "summary": build_dashboard_text(snapshot),
                "products": bundle["products"],
                "paymentAccount": bundle["paymentAccount"],
                "appUpdateAndroid": bundle["appUpdateAndroid"],
            }
            self.report_text.delete("1.0", "end")
            self.report_text.insert("1.0", json.dumps(preview, ensure_ascii=False, indent=2))
        except Exception as exc:
            messagebox.showerror("สร้าง preview report ไม่สำเร็จ", str(exc))

    def export_reports(self) -> None:
        if not self.ensure_connected():
            return
        target_dir = filedialog.askdirectory(title="เลือกโฟลเดอร์ปลายทางสำหรับ report")
        if not target_dir:
            return
        try:
            paths = self.backend.export_report_bundle(target_dir)
            self.report_text.delete("1.0", "end")
            self.report_text.insert("1.0", build_export_summary(paths))
            messagebox.showinfo("สำเร็จ", "ส่งออกรายงานแล้ว")
        except Exception as exc:
            messagebox.showerror("ส่งออก report ไม่สำเร็จ", str(exc))

    def open_explorer_path(self) -> None:
        if not self.ensure_connected():
            return
        try:
            mode = self.explorer_mode_var.get().strip().lower()
            path = self.explorer_path_var.get().strip()
            if mode == "collection":
                data = self.backend.list_collection_by_path(path)
            else:
                data = self.backend.get_document_by_path(path)
            self.explorer_text.delete("1.0", "end")
            self.explorer_text.insert("1.0", json.dumps(data, ensure_ascii=False, indent=2))
        except Exception as exc:
            messagebox.showerror("เปิด path ไม่สำเร็จ", str(exc))

    def _fill_tree(self, tree: ttk.Treeview, rows: List[Dict[str, Any]], columns: List[str]) -> None:
        for item in tree.get_children():
            tree.delete(item)
        for index, row in enumerate(rows):
            values = [row.get(col, "") for col in columns]
            tree.insert("", "end", iid=str(index), values=values)

    def run(self) -> None:
        self.root.mainloop()


def run() -> None:
    app = GoPlayAdminApp()
    app.run()
