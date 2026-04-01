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

7. `docs/current-status.md`
   - สถานะล่าสุดสำหรับ resume งาน

8. `docs/progress-log.md`
   - log ความคืบหน้าแบบตามเวลาเพื่อ handoff และ audit trail

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

## Work continuity and automatic status snapshots

เพื่อให้ทีมกลับมาทำงานต่อได้โดยไม่ต้องไล่เดาบริบทใหม่ ต้องมีการบันทึกสถานะงานล่าสุดแบบต่อเนื่องและอ่านต่อได้ทันที

### Mandatory cadence
- ระหว่างที่กำลังทำงานอยู่ ต้องอัปเดตสถานะอัตโนมัติทุก ๆ 10 นาที
- ถ้าจะหยุดงาน, pause, เปลี่ยนงาน, หรือจบ session ก่อนครบ 10 นาที ให้เขียน handoff snapshot ทันทีอีก 1 ครั้งก่อนหยุด
- ห้ามปล่อยให้ session จบโดยไม่มีสถานะล่าสุดที่บอกได้ว่าค้างอยู่ตรงไหน

### Required status files
ต้องมีไฟล์ต่อไปนี้เสมอ:

1. `docs/current-status.md`
   - ใช้เป็น single source of truth ของสถานะล่าสุด
   - คนที่กลับมาอ่านต้องใช้เวลาไม่เกิน 1 นาทีเพื่อเข้าใจว่าตอนนี้งานอยู่ตรงไหน

2. `docs/progress-log.md`
   - เป็น append-only log
   - บันทึก snapshot ตามลำดับเวลาเพื่อดูความคืบหน้า, สิ่งที่ลองไปแล้ว, และจุดที่เปลี่ยนแผน

### Every snapshot must include
ทุกครั้งที่อัปเดตสถานะ ต้องมีข้อมูลอย่างน้อย:
- timestamp
- current phase
- task/objective ที่กำลังทำ
- สิ่งที่เสร็จแล้วตั้งแต่ snapshot ก่อนหน้า
- สิ่งที่กำลังทำค้างอยู่ตอนนี้
- blockers / risks
- files/modules ที่แตะล่าสุด
- build/test status
- exact next concrete step
- expected resume inspection scope
- current tool(s)
- exact command(s)
- tool purpose
- tool state
- expected resume command
- expected output/artifact path (ถ้ามี)
- repo root / working directory
- current branch
- base commit / HEAD seen
- build flavor / target
- primary working set
- files to inspect first after resume
- command run from
- prerequisites before command
- expected success signal
- expected failure signal
- last known log location
- last known artifact path
- recent decisions
- rejected approaches
- stop point classification
- what is done but unverified
- what is verified
- external prerequisite
- secret required but not stored

### Resume rule
เมื่อกลับมาทำงานต่อ ต้องเริ่มจาก:
1. อ่าน `docs/current-status.md`
2. อ่าน entry ล่าสุดใน `docs/progress-log.md`
3. ทำงานต่อจาก `exact next concrete step` ที่ถูกบันทึกไว้ล่าสุด

ห้ามเริ่มด้วยการสำรวจใหม่ทั้งหมด ถ้ายังมีบริบทล่าสุดเพียงพอในไฟล์สถานะ

### Codex / agent resume entrypoint
เมื่อถูกสั่งด้วยคำว่า:
- "ดูงานล่าสุด"
- "resume"
- "continue"
- "continue from latest"
- "check latest work"
- "ดูว่าค้างตรงไหน"
- "ทำต่อจากที่ทีมค้างไว้"

ให้ทำตามลำดับนี้ก่อนทุกครั้ง:
1. เปิด `docs/current-status.md`
2. เปิด entry ล่าสุดใน `docs/progress-log.md`
3. สรุปให้ชัดก่อนเริ่มลงมือว่า:
   - ตอนนี้งานอยู่ phase ไหน
   - ล่าสุดทำอะไรไปแล้ว
   - กำลังค้างที่อะไร
   - next concrete step คืออะไร
4. จากนั้นค่อยทำงานต่อจาก `Next concrete step`

ห้ามเริ่มด้วยการสำรวจ repo ใหม่ทั้งหมด ถ้าในไฟล์สถานะมีบริบทเพียงพออยู่แล้ว

ถ้าไฟล์สถานะยังไม่มี, หาย, หรือไม่อัปเดตตาม cadence:
- ให้รายงานว่า handoff context ไม่สมบูรณ์
- ให้สร้างหรืออัปเดต `docs/current-status.md` และ `docs/progress-log.md` ทันทีเมื่อเริ่มจับบริบทได้

### Post-resume code reality check
หลังจากอ่าน `docs/current-status.md` และ entry ล่าสุดใน `docs/progress-log.md` แล้ว
ต้องตรวจสภาพโค้ดจริงก่อนตัดสินใจทำงานต่อ โดยใช้ targeted inspection เท่านั้น
ไม่ใช่การสำรวจ repo ใหม่ทั้งหมด

ลำดับการทำงานหลัง resume:
1. ระบุไฟล์/โมดูลที่เกี่ยวข้องจาก:
   - `Files/modules touched`
   - `Current objective`
   - `In progress now`
   - `Next concrete step`
   - `Expected resume inspection scope`
   - `Primary working set`
   - `Files to inspect first after resume`

2. ตรวจโค้ดจริงเฉพาะส่วนที่เกี่ยวข้อง เช่น:
   - ไฟล์ที่แก้ล่าสุด
   - call sites ที่เกี่ยวข้อง
   - config/build files ที่เกี่ยวข้อง
   - test/build artifacts หรือ error output ที่เกี่ยวข้อง ถ้ามี

3. เปรียบเทียบสิ่งที่พบในโค้ดกับสถานะล่าสุดที่ถูกบันทึกไว้ แล้วตอบให้ได้ว่า:
   - งานค้างอยู่ตรงไหนตามโค้ดจริง
   - สิ่งที่บันทึกไว้ยังตรงกับ reality หรือไม่
   - มีแนวทางไปต่อได้กี่ทาง
   - ทางที่ควรทำต่อทันทีคืออะไร

4. ถ้าสถานะที่บันทึกไว้ไม่ตรงกับโค้ดจริง:
   - ให้ถือ “โค้ดและผล build/test ที่ตรวจได้จริง” เป็น source of truth
   - แล้วอัปเดต `docs/current-status.md` และ `docs/progress-log.md` ทันที ก่อนลงมือแก้ต่อ

5. ก่อนเริ่มทำงานต่อ ให้สรุปสั้น ๆ เสมอ:
   - latest recorded status
   - actual code state after resume
   - chosen direction
   - next concrete step

### Tooling continuity across snapshots
เพื่อให้ resume งานได้แม่นขึ้น ต้องบันทึกเครื่องมือและคำสั่งที่ใช้งานอยู่ในแต่ละ snapshot
โดยเฉพาะเมื่อกำลัง build, run script, generate artifact, run tests, หรือ inspect code ผ่าน command-line tools

### How to record tooling state
ให้บันทึกแบบ actionable เช่น:
- Current tool(s): `shell`, `autoninja`
- Exact command(s): `autoninja -C out/Default chrome_public_apk`
- Tool purpose: build Android APK after UI color change
- Tool state: running at last snapshot / last observed before interruption
- Expected resume command: rerun `autoninja -C out/Default chrome_public_apk` and inspect compile output
- Expected output/artifact path: `out/Default/apks/`

ห้ามเขียนกว้าง ๆ เช่น:
- "using terminal"
- "running build tool"
- "using python"

ให้ระบุชื่อ tool หรือ command จริงเสมอ เช่น:
- `shell`
- `python scripts/generate_allowlist.py`
- `./gradlew assembleOnetabytDebug`
- `autoninja -C out/Default ...`

### Resume behavior for tooling
หลัง resume แล้ว ต้องตรวจจาก status files ก่อนว่า snapshot ล่าสุดระบุเครื่องมือ/คำสั่งใดไว้
ถ้า command เดิมเป็น long-running command หรือ build command:
1. อย่าสมมติว่ามันยังรันค้างอยู่
2. ให้ตรวจ artifact, logs, และ output path ที่เกี่ยวข้องก่อน
3. ถ้ายังไม่มีหลักฐานว่า command สำเร็จ ให้ถือว่า needs rerun
4. ให้สรุปก่อนลงมือว่า:
   - last recorded tool
   - last recorded command
   - whether result is observable in repo/output/logs
   - whether the same tool/command should be reused now

### Workspace continuity and desk state
เพื่อให้ Codex กลับมาแล้วเหมือนมานั่งที่โต๊ะทำงานเดิม ให้บันทึก “state ของโต๊ะ” ควบคู่กับ state ของงาน
ไม่ใช่แค่กำลังทำอะไร แต่ต้องรู้ด้วยว่าทำอยู่ที่ไหน ใช้บริบทอะไร รอผลจากอะไร และกลับมาต้องเปิดอะไรเป็นอย่างแรก

### Desk state rules
ทุก snapshot ต้องสะท้อนให้ตอบได้ว่า:
- กำลังอยู่ repo/path ไหน
- อยู่ branch/commit ไหน
- กำลังทำกับ build target หรือ flavor ไหน
- working set หลักคือไฟล์ใด
- ตอนหยุดงานกำลังอยู่ micro-step ไหน
- อะไร verified แล้ว และอะไรยังไม่ verified
- มี external dependency อะไรบ้างก่อน resume

### Active working set rule
เมื่อกำลังทำงานกับปัญหาใดปัญหาหนึ่ง ต้องระบุ working set หลัก 3 ถึง 8 ไฟล์หรือโมดูลที่เกี่ยวข้องที่สุด
พร้อมบอกสั้น ๆ ว่าแต่ละไฟล์เกี่ยวข้องอย่างไร
ห้ามปล่อยให้ resume ต้องเดาเองจาก `Files/modules touched` แบบกว้าง ๆ อย่างเดียว

### Build and test evidence rule
ถ้ามีการ build, test, run script, generate artifact, หรือ run long command
ต้องบันทึกหลักฐานที่ใช้ตรวจ reality หลัง resume ด้วย เช่น:
- log file path
- build output path
- test report path
- last observed error excerpt
- success signal ที่คาดว่าจะเจอ

ถ้าไม่มีหลักฐานเหล่านี้ ห้ามสรุปว่า command สำเร็จแล้ว

### Decision journal rule
ทุก snapshot ต้องบันทึก decision สั้น ๆ ที่สำคัญ:
- เลือกทางไหน
- เพราะอะไร
- มีทางไหนที่ลองแล้วไม่เอา
- assumption อะไรที่ยังถืออยู่

เป้าหมายคือป้องกันการกลับไปลองทางเดิมซ้ำโดยไม่จำเป็น

### Stop-point contract
ก่อนหยุดงาน ต้องระบุ stop point ให้ชัดว่าอยู่ช่วงไหนของ micro-step เช่น:
- code edited but not compiled
- compile started but not verified
- build passed but APK not installed
- installed but runtime not smoke-tested
- test failed and root cause not confirmed

ห้ามจบ snapshot ด้วยสถานะกว้าง ๆ ที่ไม่บอกระดับความเสร็จของ step ปัจจุบัน

### External dependency boundary
ห้ามเก็บ secrets, tokens, cookies, private keys, raw credentials หรือข้อมูลลับอื่นลงใน status files
ถ้าต้องใช้ dependency ภายนอก ให้บันทึกแบบนี้แทน:
- ต้อง login บริการใด
- ต้องมี credential ประเภทใด
- มี manual prerequisite อะไรก่อน resume
- อะไรที่ required แต่ intentionally not stored

### 60-second resume checklist
ใน 60 วินาทีแรกหลัง resume ให้ทำตามลำดับนี้:
1. เปิด `docs/current-status.md`
2. เปิด entry ล่าสุดใน `docs/progress-log.md`
3. ตรวจ `Repo root / working directory`, `Current branch`, และ `Base commit / HEAD seen`
4. เปิด `Primary working set` และ `Files to inspect first after resume`
5. ตรวจ `Current tool(s)`, `Exact command(s)`, `Tool state`, และ `Expected resume command`
6. ตรวจ `Last known log location` และ `Last known artifact path`
7. สรุปว่า:
   - recorded desk state คืออะไร
   - actual desk state หลัง resume คืออะไร
   - ต้อง rerun command เดิมไหม
   - จะทำ step ไหนต่อทันที

### Example of good desk-state recording
ตัวอย่าง:
- Repo root / working directory: `/src/brave/android`
- Current branch: `feat/onetabyt-green-cta`
- Base commit / HEAD seen: `abc1234`
- Build flavor / target: `onetabytDebug`
- Primary working set:
  - `app/src/.../MainToolbar.java` — CTA color wiring
  - `app/src/.../ThemeUtils.java` — shared color source
  - `app/build.gradle` — flavor resource merge validation
- Files to inspect first after resume:
  - `MainToolbar.java`
  - `ThemeUtils.java`
  - `app/build/outputs/apk/onetabyt/debug/`
- Command run from: repo root
- Expected success signal: APK emitted at expected output path with no compile errors
- Expected failure signal: resource merge error or unresolved symbol in toolbar/theme classes
- Stop point classification: compile started but not verified
- What is done but unverified: CTA color changed from red to green in code
- What is verified: source edits saved successfully
- External prerequisite: Android SDK and local Brave/Chromium deps synced
- Secret required but not stored: signing credentials intentionally not stored

### Tool choice rule after resume
ถ้าหลัง resume พบว่าเครื่องมือเดิมยังเหมาะกับงานเดิม ให้ใช้เครื่องมือเดิมก่อน
ห้ามเปลี่ยนจาก tool เดิมไปใช้ tool ใหม่โดยไม่จำเป็น
เว้นแต่:
- command เดิมใช้ไม่ได้แล้ว
- path/config เปลี่ยน
- build system ชี้ว่าควรใช้ tool อื่น
- latest code state ทำให้ next step เปลี่ยนไป

### Direction selection rule after resume
หลังจากกลับมาและตรวจโค้ดแล้ว ให้เลือกแนวทางไปต่อโดยใช้ลำดับความสำคัญนี้:
1. unblock build/test failure ที่ค้างอยู่ก่อน
2. ทำ `Next concrete step` เดิม ถ้ายัง valid
3. ถ้า `Next concrete step` เดิมไม่ valid แล้ว ให้เลือก step ใหม่ที่ใกล้เป้าหมายเดิมที่สุด
4. หลีกเลี่ยงการเปลี่ยนแผนใหญ่ เว้นแต่โค้ดจริงหรือผล build/test บอกชัดว่าทางเดิมไปต่อไม่ได้

### Scope limit for resume inspection
หลัง resume ห้ามเริ่มจากการไล่ดูทั้ง repo ใหม่ เว้นแต่:
- status files ไม่มีข้อมูลพอ
- touched files หาไม่เจอ
- โค้ดจริงขัดกับสถานะล่าสุดอย่างมีนัยสำคัญ
- build/test failure ชี้ว่าปัญหากระทบกว้างกว่าขอบเขตเดิม

โดยค่าเริ่มต้น ให้ inspect เฉพาะขอบเขตที่เกี่ยวข้องกับงานล่าสุดก่อนเสมอ

### Example of expected resume reasoning
ตัวอย่าง:
- recorded status: เปลี่ยนปุ่มจากสีแดงเป็นสีเขียวแล้ว และกำลังประกอบ APK
- actual code state after resume: พบว่าไฟล์ UI ถูกแก้แล้ว แต่ไม่มี build output ใหม่ และไม่มีผลลัพธ์ยืนยันว่า assemble สำเร็จ
- chosen direction: เริ่มจาก re-run build ใน flavor เดิม แทนการแก้ UI เพิ่ม
- next concrete step: run `./gradlew assembleOnetabytDebug` แล้วตรวจ APK output path และ compile errors

### Quality bar for status writing
ห้ามเขียนสถานะแบบกว้างเกินไป เช่น:
- "working on browser stuff"
- "fixing tabs"
- "investigating issue"

ให้เขียนแบบ actionable และส่งต่องานได้ทันที เช่น:
- "Tracing Brave tab creation flow in `<class/file>` to disable new-tab entry points without breaking reuse of current tab"
- "Implemented initial YouTube allowlist matcher; next step is verify Google sign-in redirects that are required for YouTube auth"
- "Build failed in flavor wiring after branding changes; next step is fix manifest/resource mismatch in onetabyt flavor"

### Minimum handoff guarantee
ทุกสถานะล่าสุดต้องทำให้คนที่กลับมาอ่านตอบได้ภายใน 1 นาทีว่า:
- ตอนนี้งานค้างอยู่ที่ไหน
- เพิ่งทำอะไรไปล่าสุด
- อะไรเป็น blocker
- ต้องทำอะไรต่อเป็น step ถัดไป
- กำลังนั่งอยู่ที่โต๊ะไหนในเชิงปฏิบัติการ
- ต้องเปิดไฟล์/เครื่องมือ/หลักฐานอะไรเป็นอย่างแรก

### Suggested template for `docs/current-status.md`

# Current Status

- Last updated:
- Current phase:
- Current objective:
- Completed since last update:
- In progress now:
- Files/modules touched:
- Build/test status:
- Blockers/risks:
- Next concrete step:
- Expected resume inspection scope:
- Current tool(s):
- Exact command(s):
- Tool purpose:
- Tool state:
- Expected resume command:
- Expected output/artifact path:
- Repo root / working directory:
- Current branch:
- Base commit / HEAD seen:
- Build flavor / target:
- Primary working set:
- Files to inspect first after resume:
- Command run from:
- Prerequisites before command:
- Expected success signal:
- Expected failure signal:
- Last known log location:
- Last known artifact path:
- Recent decisions:
- Rejected approaches:
- Stop point classification:
- What is done but unverified:
- What is verified:
- External prerequisite:
- Secret required but not stored:
- Actual code state after resume:
- Chosen direction:

### Suggested template for `docs/progress-log.md`

# Progress Log

## [YYYY-MM-DD HH:MM]
- Phase:
- Objective:
- Done:
- In progress:
- Files touched:
- Build/test status:
- Blockers/risks:
- Next step:
- Expected resume inspection scope:
- Current tool(s):
- Exact command(s):
- Tool purpose:
- Tool state:
- Expected resume command:
- Expected output/artifact path:
- Repo root / working directory:
- Current branch:
- Base commit / HEAD seen:
- Build flavor / target:
- Primary working set:
- Files to inspect first after resume:
- Command run from:
- Prerequisites before command:
- Expected success signal:
- Expected failure signal:
- Last known log location:
- Last known artifact path:
- Recent decisions:
- Rejected approaches:
- Stop point classification:
- What is done but unverified:
- What is verified:
- External prerequisite:
- Secret required but not stored:

## [YYYY-MM-DD HH:MM]
- Phase:
- Objective:
- Done:
- In progress:
- Files touched:
- Build/test status:
- Blockers/risks:
- Next step:
- Expected resume inspection scope:
- Current tool(s):
- Exact command(s):
- Tool purpose:
- Tool state:
- Expected resume command:
- Expected output/artifact path:
- Repo root / working directory:
- Current branch:
- Base commit / HEAD seen:
- Build flavor / target:
- Primary working set:
- Files to inspect first after resume:
- Command run from:
- Prerequisites before command:
- Expected success signal:
- Expected failure signal:
- Last known log location:
- Last known artifact path:
- Recent decisions:
- Rejected approaches:
- Stop point classification:
- What is done but unverified:
- What is verified:
- External prerequisite:
- Secret required but not stored:

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

เริ่มจาก:
1. ถ้ามี `docs/current-status.md` และ `docs/progress-log.md` อยู่แล้ว ให้เปิดอ่านก่อนเพื่อดูงานล่าสุด
2. หลังอ่าน status files แล้ว ให้ทำ targeted inspection เฉพาะ scope ที่เกี่ยวข้องกับงานล่าสุด เพื่อยืนยันสภาพโค้ดจริงก่อนเริ่มทำต่อ
3. ใน 60 วินาทีแรก ให้รันตาม `60-second resume checklist`
4. ถ้ายังไม่มีไฟล์สถานะ ให้เริ่ม inspect repo structure และสร้างไฟล์สถานะตั้งแต่รอบแรก
5. หา:
   - gradle modules
   - Android app module entry
   - Brave-specific feature wiring
   - tab/navigation/shields related classes

จากนั้นสร้าง `docs/architecture-notes.md` และ `docs/change-plan.md` ก่อนลงมือแก้โค้ดจริง
