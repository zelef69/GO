# AGENT.MD

## Mission
สร้าง Android app แบบ Chromium-based โดยใช้ **Brave Android source** เป็นฐานหลัก แล้วลด product surface ให้เหลือ **One Tab - YouTube-only browser** โดยยังคง **Brave adblock / shields engine** ให้ทำงานกับ YouTube navigation และ playback ให้มากที่สุดเท่าที่ซอร์ส Brave รองรับได้ในเชิงวิศวกรรมจริง

> ห้ามอ้างผลลัพธ์แบบการันตีว่า “adblock 100% ตลอดไป” เพราะ YouTube และ anti-adblock behavior เปลี่ยนได้เสมอ
> เป้าหมายที่ถูกต้องคือ: **retain Brave adblocking stack intact**, ไม่ถอด ไม่ disable ไม่ fork ทิ้งแบบเสียความสามารถหลัก

---

## Product definition

### Core idea
แอปนี้ไม่ใช่ general-purpose browser
แอปนี้คือ **single-purpose YouTube browser shell** ที่:
- เปิดได้เฉพาะ YouTube domains ที่กำหนด
- มีได้แค่ **1 active tab**
- ตัด UI/feature อื่นที่ไม่จำเป็นออกให้มากที่สุด
- ใช้ Brave Android codebase เป็นต้นทางของ browser engine + shields/adblock integration

### Allowed surfaces
อนุญาตเฉพาะ flow ต่อไปนี้:
- `https://www.youtube.com/*`
- `https://m.youtube.com/*`
- `https://youtube.com/*`
- `https://youtu.be/*`
- หน้า consent / sign-in / account selection ที่จำเป็นต่อการใช้งาน YouTube/Google login เฉพาะที่เกี่ยวข้อง
- optional: `https://accounts.google.com/*` เฉพาะกรณีจำเป็นต่อ sign-in ของ YouTube

### Disallowed surfaces
ต้องบล็อกหรือ redirect ออกทันทีสำหรับ:
- ทุก URL ที่ไม่อยู่ใน allowlist
- external intent ทั่วไปที่พยายามพาออกนอก YouTube scope
- download surface ที่ไม่จำเป็น
- bookmark manager, history UI, sync UI, rewards, wallet, vpn, news/feed, leo/ai, brave account upsell, private windows, multi-window, tab switcher

---

## Non-negotiable requirements

1. **Base code must come from Brave Android**
   - ใช้ Brave เป็นฐานหลักจริง ไม่ใช่เอา Android WebView มาห่อแล้วเรียกว่า Brave-based
   - รักษา Brave shields / adblock pipeline ให้ครบเท่าที่ build target นี้รองรับ

2. **One-tab only**
   - มี tab เดียว
   - ถ้าเปิดลิงก์ใหม่ ให้ reuse tab เดิมเสมอ
   - ปิด UI สำหรับ create/switch/manage tabs

3. **YouTube-only navigation policy**
   - ทุก navigation ต้องผ่าน allowlist policy
   - non-YouTube URL ให้ block พร้อม UX ที่ชัดเจน หรือ fallback กลับ YouTube home

4. **Keep Brave adblock intact**
   - ห้าม disable Brave shields/adblock component
   - ห้ามแทนที่ด้วย adblock แบบ custom ที่ไม่ใช่ Brave stack
   - ถ้าจำเป็นต้องแก้ integration ให้แก้เฉพาะระดับ wiring / product flags / default settings เท่านั้น

5. **Ship as a distinct product flavor / fork target**
   - แยก brand/applicationId/app name/icon/gradle flavor ให้ชัด
   - หลีกเลี่ยงการแก้ที่ทำให้ upstream Brave Android หลักพัง

---

## Success criteria

งานถือว่าเสร็จเมื่อมีครบ:
- build debug APK ได้
- launch ได้บน Android device/emulator
- เข้า YouTube ได้โดยตรงเป็น default home
- เปิดเว็บนอก allowlist ไม่ได้
- ไม่มี tab switcher / multi-tab UX
- Brave shields/adblock code path ยังถูกเปิดใช้งานใน build นี้
- มี README สำหรับ build/run/test
- มีรายการ patch summary ว่าแก้อะไรบ้างและทำไม

---

## Important honesty constraints

ห้ามเขียน claim ต่อไปนี้:
- “บล็อกโฆษณา YouTube ได้ 100% แน่นอนถาวร”
- “จะไม่โดน YouTube anti-adblock detection เลย”
- “ใช้ Brave source แล้วเท่ากับพฤติกรรมเหมือน Brave ทุกจุด”

ให้ใช้ถ้อยคำนี้แทน:
- “retains Brave adblocking stack”
- “aims to preserve Brave Shields behavior for YouTube”
- “actual blocking effectiveness may vary as upstream rules and YouTube behavior evolve”

---

## Expected repository strategy

### Preferred approach
สร้าง fork target จาก Brave Android โดยใช้แนวทางนี้:
- เพิ่ม product flavor ใหม่ เช่น `onetabyt`
- เปลี่ยน branding เป็นชื่อชั่วคราว เช่น `OneTabTube`
- ปิด feature flags และ entry points ที่ไม่เกี่ยวข้อง
- จำกัด navigation ผ่าน allowlist policy layer
- override startup/home intent ให้เข้า YouTube เสมอ

### Avoid
- อย่าเริ่มจากเขียน browser ใหม่บน WebView
- อย่า rewrite adblock engine ใหม่
- อย่า delete subsystem แบบสุ่มจน build พัง

---

## Implementation plan

### Phase 1 — inspect and map Brave Android
ต้องหาให้เจอก่อน:
- app entrypoint
- product flavors / branding setup
- tab management classes
- navigation interception points
- Brave shields/adblock integration points
- settings / menu / bottom sheet / toolbar components ที่ต้องตัด

ส่งออกเป็นเอกสารสั้น ๆ:
- `docs/architecture-notes.md`
- `docs/change-plan.md`

### Phase 2 — product flavor and branding
ทำสิ่งต่อไปนี้:
- เพิ่ม product flavor ใหม่
- ตั้ง `applicationId` ใหม่
- app name ใหม่
- icon placeholder ใหม่
- default homepage/start destination เป็น YouTube

### Phase 3 — one-tab enforcement
ต้องทำให้ได้ทั้งหมด:
- disable new tab creation actions
- disable tab switcher entry points
- force links/new windows/popups ให้เปิดใน tab เดิม
- block incognito/private tab paths
- disable restore multiple tabs behavior

### Phase 4 — YouTube allowlist policy
เพิ่ม centralized navigation policy:
- allow domains ที่กำหนด
- support redirect/sign-in flow เท่าที่จำเป็น
- reject everything else
- มี test cases สำหรับ allow/deny URL patterns

### Phase 5 — surface reduction
remove/hide/disable อย่างน้อย:
- bookmarks UI
- history UI
- downloads UI (ถ้าไม่ critical)
- sync/account surfaces ที่ไม่จำเป็น
- Brave Rewards
- Brave Wallet
- Brave VPN
- News/Feed
- AI/Leo entry points
- share surfaces ที่ไม่ critical
- context menu items ที่พาออกนอก scope
- settings sections ที่ไม่จำเป็นต่อ product

### Phase 6 — preserve Brave adblock behavior
ตรวจให้ชัด:
- Brave shields defaults ยัง active
- content blocking/rule loading path ยังไม่ถูกตัด
- YouTube navigation path ยังผ่าน engine ปกติ
- ไม่มีการ disable component เพราะ product minimization

### Phase 7 — validation
สร้าง:
- smoke test checklist
- basic unit tests สำหรับ URL allowlist
- manual QA steps
- known limitations list

---

## Deliverables

ต้องสร้างไฟล์ต่อไปนี้:

1. `README.md`
   - setup
   - sync dependencies
   - build debug APK
   - install/run
   - known limitations

2. `docs/architecture-notes.md`
   - Brave Android map ที่เกี่ยวข้อง

3. `docs/change-plan.md`
   - รายการแก้ไขแบบ actionable

4. `docs/patch-summary.md`
   - สรุปว่ามีการแก้ไฟล์ไหน/โมดูลไหน/เหตุผลอะไร

5. `docs/testing.md`
   - test matrix + QA steps

6. source changes
   - product flavor / config / code wiring / navigation policy / UI pruning

---

## Acceptance tests

### Build
- `./gradlew assembleOnetabytDebug` หรือ task ที่เทียบเท่า build ผ่าน

### Runtime
- เปิดแอปแล้วเข้า YouTube home
- เปิดลิงก์ `youtube.com/watch?v=...` ได้
- เปิดลิงก์ `youtu.be/...` ได้
- เปิดลิงก์ `google.com` แล้วถูก block หรือ redirect
- ไม่มีปุ่มเปิด tab ใหม่
- ไม่มี tab switcher
- ไม่มี private browsing

### Adblock / shields sanity
- ตรวจว่า shields/adblock preferences และ service wiring ยัง active
- บันทึกวิธีตรวจที่ทำซ้ำได้ใน `docs/testing.md`

---

## Coding rules

- ทำ patch แบบเล็กและอธิบายเหตุผลทุกกลุ่มการเปลี่ยนแปลง
- อย่าลบโค้ดจำนวนมากโดยไม่เช็ก dependency graph
- prefer feature-flag / gating / flavor-based exclusion มากกว่าลบทิ้งตรง ๆ
- ถ้าไม่แน่ใจว่า component ไหนมี side effects ให้ inspect call sites ก่อน
- ทุกครั้งที่แก้ behavior สำคัญ ให้อัปเดตเอกสารควบคู่กัน

---

## Output format while working

ระหว่างทำงาน ให้รายงานเป็นรอบ ๆ แบบนี้:
1. สิ่งที่สำรวจพบ
2. สิ่งที่แก้ไปแล้ว
3. build/test status
4. blockers/risks
5. next concrete step

---

## Final report format

เมื่อจบงาน ให้สรุปเป็นหัวข้อ:
- What changed
- What remains Brave-derived
- What was intentionally removed/hidden
- How one-tab enforcement works
- How YouTube allowlist works
- How adblock/shields were preserved
- Known limitations
- Exact build command
- Exact APK output path

---

## First action

เริ่มจาก inspect repo structure และหา:
- gradle modules
- Android app module entry
- Brave-specific feature wiring
- tab/navigation/shields related classes

จากนั้นสร้าง `docs/architecture-notes.md` และ `docs/change-plan.md` ก่อนลงมือแก้โค้ดจริง
