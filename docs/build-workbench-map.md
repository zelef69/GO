# Build Workbench Map

เอกสารนี้เป็น source of truth สำหรับ “โต๊ะ build ปัจจุบัน” ของ GO_PLAY / OneTabTube ในสภาพแวดล้อมที่ใช้งานจริงตอนนี้

เป้าหมายคือเปิดไฟล์นี้แล้วสามารถ:
- รู้ว่าแก้ไฟล์ที่ไหน
- รู้ว่า build จากที่ไหน
- รู้ว่าใช้เครื่องมืออะไร
- รู้ว่าคำสั่งไหนคือเส้นหลัก
- รู้ว่าควรได้ artifact อะไรออกมา
- รู้ว่าตรวจ success/failure ตรงไหน

เอกสารนี้ตั้งใจให้ใช้แทนการเดาทางจาก log เก่า ๆ ที่กระจายหลายรอบ

## 1. Baseline Floor ที่ห้ามต่ำกว่า

baseline runtime ปัจจุบันที่ติดตั้งอยู่บนเครื่องทดสอบ:

- package: `com.onetabtube.browser_default`
- versionCode: `429000004`
- versionName: `1.90.0`
- device: `R9TRC00GA2E`
- device-installed APK floor hash: `43402E441C53E92BD64D64758BBF69B528B0FE80916CC5F09E8D4DB257EEEA28`

ไฟล์ APK ที่ตรงกับ baseline นี้ใน build tree:

- [OneTabTube.apk](\\wsl.localhost\Ubuntu\home\master\src_ext4\out\android_Component_arm64\apks\OneTabTube.apk)

ห้ามถือ artifact เก่ากว่า baseline นี้เป็นพื้นฐานใหม่ เว้นแต่ผู้ใช้สั่งชัดเจน

## 2. สภาพแวดล้อมจริงของโต๊ะ build

มี 2 ตำแหน่งหลักที่ต้องแยกให้ออก:

### 2.1 Windows workspace

repo ที่เรากำลังแก้ไฟล์อยู่:

- `C:\Users\Master\Desktop\GO_PLAY`

หน้าที่ของ workspace นี้:

- แก้ source
- เก็บ docs
- เก็บ artifacts และ logs
- เป็นที่เรียก `adb`, `firebase`, `Get-FileHash`, `aapt`, `apksigner`

### 2.2 WSL build tree ที่ใช้ build APK จริง

build จากตรงนี้:

- `\\wsl.localhost\Ubuntu\home\master\src_ext4`

หรือ path ฝั่ง Linux:

- `/home/master/src_ext4`

หน้าที่ของ tree นี้:

- เป็น Brave/Chromium checkout ที่ `autoninja` ใช้งานจริง
- เป็นที่มี `out/android_Component_arm64`
- เป็นที่ออก APK จริง

สรุปสั้น:

- แก้ไฟล์ใน `Desktop\GO_PLAY`
- sync เข้า `src_ext4`
- build ใน `src_ext4`

## 3. แผนที่เครื่องมือที่ใช้จริง

### 3.1 Tool map

| Tool | Path/Invocation | ใช้ทำอะไร |
|---|---|---|
| `PowerShell` | shell หลักของ session | orchestration, copy, hash, adb wrapper |
| `wsl.exe` | `C:\Windows\system32\wsl.exe` | เรียก build ฝั่ง Ubuntu |
| `autoninja` | `/home/master/src_ext4/third_party/depot_tools/autoninja` | build target หลัก |
| `gn` | `/home/master/src_ext4/buildtools/linux64/gn/gn` | regenerate out dir เมื่อจำเป็น |
| `adb.exe` | `C:\Users\Master\AppData\Local\Android\Sdk\platform-tools\adb.exe` | install APK, launch app, dump UI |
| `aapt.exe` | `C:\Users\Master\AppData\Local\Android\Sdk\build-tools\36.1.0\aapt.exe` | inspect APK label / manifest / badging |
| `apksigner.bat` | `C:\Users\Master\AppData\Local\Android\Sdk\build-tools\36.1.0\apksigner.bat` | inspect APK signing metadata |
| `Copy-Item` | PowerShell built-in | sync local edited files เข้า build tree |
| `Get-FileHash` | PowerShell built-in | fingerprint APK |

### 3.2 Tool state ที่ตรวจแล้วตอนเขียนเอกสารนี้

- `wsl.exe`: ใช้งานได้
- `adb.exe`: ใช้งานได้
- `aapt.exe`: มีอยู่จริง
- `apksigner.bat`: มีอยู่จริง
- `src_ext4`: มีอยู่จริง
- `out/android_Component_arm64/args.gn`: มีอยู่จริง
- `OneTabTube.apk`: มีอยู่จริง

## 4. แผนที่ build target และไฟล์ที่เกี่ยวข้อง

### 4.1 GN target หลักที่ใช้ build APK

target ที่ใช้จริง:

- `brave/build/android:onetabtube_android_package`

คำสั่ง build หลักที่ใช้อยู่จริงในช่วงล่าสุด:

```powershell
wsl.exe bash -lc "cd /home/master/src_ext4 && ./third_party/depot_tools/autoninja -C out/android_Component_arm64 brave/build/android:onetabtube_android_package 2>&1 | tee /mnt/c/Users/Master/Desktop/GO_PLAY/artifacts/android_build/<next_log>.log"
```

### 4.2 Success signal ของ build

สัญญาณว่ารอบ build ผ่านจริง:

- log ลงท้ายด้วย action สุดท้ายแนว:
  - `//chrome/android:chrome_public_apk__create`
- และมี artifact ที่:
  - `\\wsl.localhost\Ubuntu\home\master\src_ext4\out\android_Component_arm64\apks\OneTabTube.apk`

ตัวอย่าง log ที่ผ่าน:

- [package_lock_youtube_only_build_20260406.log](C:/Users/Master/Desktop/GO_PLAY/artifacts/android_build/package_lock_youtube_only_build_20260406.log)

### 4.3 Failure signal ที่เจอบ่อย

ตัวอย่างรอบที่ล้ม:

- [package_access_failopen_pkg_rename_build_20260406.log](C:/Users/Master/Desktop/GO_PLAY/artifacts/android_build/package_access_failopen_pkg_rename_build_20260406.log)

failure pattern ที่ต้องอ่านให้ออก:

- `Failed JNI assertion!`
  - แปลว่ามี Java source/JNI registration mismatch
- `warnings-as-errors` หรือ `final_dex / R8`
  - แปลว่า build graph เปลี่ยนจนเกิด warning ที่ target นี้ treat เป็น error
- manifest parse / `unbound prefix`
  - มักเกิดจาก copy manifest snippet ไปทับ full manifest ผิดที่

## 5. แผนที่ไฟล์แก้ -> ไฟล์ build tree

กติกาหลัก:

- source ที่เราแก้ใน repo desktop ต้องถูก sync เข้า `src_ext4` ก่อน build
- ห้ามสมมติว่าแก้ใน `Desktop\GO_PLAY` แล้ว WSL จะเห็นอัตโนมัติ

### 5.1 Mapping หลัก

| Local workspace | WSL build tree |
|---|---|
| `android/java/...` | `\\wsl.localhost\Ubuntu\home\master\src_ext4\brave\android\java\...` |
| `android/brave_java_sources.gni` | `\\wsl.localhost\Ubuntu\home\master\src_ext4\brave\android\brave_java_sources.gni` |
| `android/BUILD.gn` | `\\wsl.localhost\Ubuntu\home\master\src_ext4\brave\android\BUILD.gn` |
| `browser/android/...` | `\\wsl.localhost\Ubuntu\home\master\src_ext4\brave\browser\android\...` |
| `functions/...` | ไม่ใช่ส่วนของ APK build โดยตรง |
| `docs/...` | ไม่ใช่ส่วนของ APK build โดยตรง |

### 5.2 ตัวอย่างคำสั่ง sync

ตัวอย่าง sync ไฟล์ Java เดี่ยว:

```powershell
Copy-Item -LiteralPath "C:\Users\Master\Desktop\GO_PLAY\android\java\org\chromium\chrome\browser\app\BraveActivity.java" `
  -Destination "\\wsl.localhost\Ubuntu\home\master\src_ext4\brave\android\java\org\chromium\chrome\browser\app\BraveActivity.java" `
  -Force
```

ตัวอย่าง sync gni:

```powershell
Copy-Item -LiteralPath "C:\Users\Master\Desktop\GO_PLAY\android\brave_java_sources.gni" `
  -Destination "\\wsl.localhost\Ubuntu\home\master\src_ext4\brave\android\brave_java_sources.gni" `
  -Force
```

## 6. เส้นทาง build หลักที่ควรใช้ตอนนี้

นี่คือเส้นหลักที่ควรใช้ก่อนเสมอ

### Step 1: เช็กโต๊ะ

```powershell
adb devices
Get-Item \\wsl.localhost\Ubuntu\home\master\src_ext4
Get-Item \\wsl.localhost\Ubuntu\home\master\src_ext4\out\android_Component_arm64\args.gn
```

คาดหวัง:

- เจอ device `R9TRC00GA2E`
- เจอ `src_ext4`
- เจอ `args.gn`

### Step 2: sync ไฟล์ที่แก้เข้า build tree

ใช้ `Copy-Item` ตาม mapping ในหัวข้อ 5

### Step 3: build APK

```powershell
wsl.exe bash -lc "cd /home/master/src_ext4 && ./third_party/depot_tools/autoninja -C out/android_Component_arm64 brave/build/android:onetabtube_android_package 2>&1 | tee /mnt/c/Users/Master/Desktop/GO_PLAY/artifacts/android_build/<next_log>.log"
```

หมายเหตุ:

- ให้ตั้งชื่อ `<next_log>.log` ตามงานรอบนั้น
- ค่าเริ่มต้นที่ใช้จริงรอบหลัง ๆ ไม่ต้องใส่ `PYTHONPATH` เพิ่มแล้ว ถ้า tree ปัจจุบันยังอยู่ในสภาพนี้

### Step 4: install ลงเครื่อง

```powershell
adb install -r "\\wsl.localhost\Ubuntu\home\master\src_ext4\out\android_Component_arm64\apks\OneTabTube.apk"
```

ถ้า incremental install แปลก ๆ ค่อยใช้:

```powershell
adb install --no-incremental -r "\\wsl.localhost\Ubuntu\home\master\src_ext4\out\android_Component_arm64\apks\OneTabTube.apk"
```

### Step 5: ยืนยันว่า APK ที่ build ใช่ตัวที่ลง

```powershell
Get-FileHash "\\wsl.localhost\Ubuntu\home\master\src_ext4\out\android_Component_arm64\apks\OneTabTube.apk" -Algorithm SHA256
adb shell dumpsys package com.onetabtube.browser_default | Select-String -Pattern 'versionCode=|versionName=|lastUpdateTime='
```

### Step 6: inspect APK ถ้าต้องเช็ก branding/manifest

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\build-tools\36.1.0\aapt.exe" dump badging "\\wsl.localhost\Ubuntu\home\master\src_ext4\out\android_Component_arm64\apks\OneTabTube.apk"
```

ถ้าต้องเช็ก signing:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\build-tools\36.1.0\apksigner.bat" verify --print-certs "\\wsl.localhost\Ubuntu\home\master\src_ext4\out\android_Component_arm64\apks\OneTabTube.apk"
```

## 7. เส้นทาง recovery ถ้า `out/android_Component_arm64` หายหรือเสีย

อย่าใช้เป็นค่าเริ่มต้นถ้า out dir เดิมยังดีอยู่

### 7.1 ตรวจว่าต้อง regen จริงไหม

```powershell
Get-Item \\wsl.localhost\Ubuntu\home\master\src_ext4\out\android_Component_arm64\args.gn
```

ถ้ายังมี `args.gn` และ build tree ยังครบ ให้ลอง build ปกติก่อน

### 7.2 ถ้าจำเป็นต้อง `gn gen`

```powershell
wsl.exe -d Ubuntu -- bash -lc "cd /home/master/src_ext4 && buildtools/linux64/gn/gn gen out/android_Component_arm64"
```

หลังจากนั้นค่อย rerun build หลัก

### 7.3 args.gn ที่เจอในโต๊ะปัจจุบัน

ค่าที่เห็นอยู่ตอนนี้ใน `out/android_Component_arm64/args.gn`:

```gn
enable_arcore = false
enable_cardboard = false
enable_openxr = false
enable_vr = false
android_static_analysis = "off"
disable_android_lint = true
```

## 8. ฟังก์ชัน/โมดูลที่เกี่ยวกับ build โดยตรง

นี่ไม่ใช่ business logic ของแอป แต่คือจุดที่ถ้าแก้แล้วกระทบ APK build โดยตรง

### 8.1 [android/BUILD.gn](C:/Users/Master/Desktop/GO_PLAY/android/BUILD.gn)

ใช้สำหรับ:

- Brave Android resource wiring
- drawable/layout/string/resource inclusion
- build rules ฝั่ง Android resources

ถ้าทำงานกับ:

- layout ใหม่
- icon ใหม่
- string ใหม่
- resource ใหม่

ให้เช็กไฟล์นี้ด้วย

### 8.2 [android/brave_java_sources.gni](C:/Users/Master/Desktop/GO_PLAY/android/brave_java_sources.gni)

ใช้สำหรับ:

- รวม Java source ของ Brave/OneTab เข้า APK
- filter source ตาม buildflags เช่น `is_onetabyt`

ถ้าเพิ่ม activity/coordinator/manager ใหม่แล้ว APK หา class ไม่เจอ ให้เช็กไฟล์นี้เป็นจุดแรก

### 8.3 GN target `brave/build/android:onetabtube_android_package`

นี่คือ entrypoint หลักของ package build ที่เราใช้จริง

ไม่ควรเปลี่ยน target build ไปมาถ้าไม่ได้มีเหตุจำเป็นจริง

## 9. สิ่งที่ “ไม่ใช่” งาน build APK โดยตรง

กันสับสนไว้ชัด ๆ:

- `functions/` = backend Firebase/Thunder
- `firebase deploy` = ไม่ใช่ APK build
- `seed scripts` = ไม่ใช่ APK build
- `docs/` = ไม่ใช่ APK build

ดังนั้นถ้างานเป็น:

- deploy callable
- seed Firestore
- ทดสอบ payment flow ฝั่ง server

ให้แยกออกจากงาน APK build ในหัว ไม่งั้นจะสับสนว่า “build ผ่านไหม” ทั้งที่จริงไปติดคนละระบบ

## 10. ข้อห้ามสำคัญ

### 10.1 ห้ามแตะ full Chromium manifest ผิดที่

ห้ามเอา:

- `android/java/AndroidManifest.xml`

ไปทับ:

- `src_ext4/chrome/android/java/AndroidManifest.xml`

เหตุผล:

- ไฟล์ใน repo นี้เป็น Brave manifest snippet
- แต่ `chrome/android/java/AndroidManifest.xml` คือ full manifest
- ถ้าทับผิดที่ build จะพังทันที

### 10.2 ห้ามยึด README เก่าเป็น build source of truth

README อธิบายภาพรวมได้ แต่โต๊ะ build จริงของงานนี้ตอนนี้ต้องยึดเอกสารนี้กับ handoff ล่าสุดเป็นหลัก

### 10.3 ห้าม clean tree กว้าง ๆ

ตอนนี้ repo มี modified/untracked จำนวนมาก

ห้ามใช้วิธี:

- ลบกว้าง
- reset กว้าง
- checkout ทับกว้าง

ถ้ายังไม่ได้ยืนยันขอบเขตไฟล์ของงานนั้นจริง

## 11. คำสั่งชุดสั้นสำหรับ “เปิดไฟล์นี้แล้ว build ทันที”

### 11.1 Preflight

```powershell
adb devices
Get-Item \\wsl.localhost\Ubuntu\home\master\src_ext4
Get-Item \\wsl.localhost\Ubuntu\home\master\src_ext4\out\android_Component_arm64\args.gn
```

### 11.2 Sync ที่แก้เข้า ext4

ตัวอย่าง:

```powershell
Copy-Item -LiteralPath "C:\Users\Master\Desktop\GO_PLAY\android\java\org\chromium\chrome\browser\app\BraveActivity.java" `
  -Destination "\\wsl.localhost\Ubuntu\home\master\src_ext4\brave\android\java\org\chromium\chrome\browser\app\BraveActivity.java" `
  -Force
```

### 11.3 Build

```powershell
wsl.exe bash -lc "cd /home/master/src_ext4 && ./third_party/depot_tools/autoninja -C out/android_Component_arm64 brave/build/android:onetabtube_android_package 2>&1 | tee /mnt/c/Users/Master/Desktop/GO_PLAY/artifacts/android_build/manual_build_<timestamp>.log"
```

### 11.4 Install

```powershell
adb install -r "\\wsl.localhost\Ubuntu\home\master\src_ext4\out\android_Component_arm64\apks\OneTabTube.apk"
```

### 11.5 Verify

```powershell
Get-FileHash "\\wsl.localhost\Ubuntu\home\master\src_ext4\out\android_Component_arm64\apks\OneTabTube.apk" -Algorithm SHA256
adb shell dumpsys package com.onetabtube.browser_default | Select-String -Pattern 'versionCode=|versionName=|lastUpdateTime='
```

## 12. เอกสารที่ควรเปิดคู่กัน

ถ้าจะ resume งาน build/feature ต่อ ให้เปิดตามลำดับนี้:

1. [current-status.md](C:/Users/Master/Desktop/GO_PLAY/docs/current-status.md)
2. [progress-log.md](C:/Users/Master/Desktop/GO_PLAY/docs/progress-log.md)
3. [build-workbench-map.md](C:/Users/Master/Desktop/GO_PLAY/docs/build-workbench-map.md)

สามไฟล์นี้รวมกันคือ:

- สถานะล่าสุด
- log การตัดสินใจ
- โต๊ะ build ที่ใช้จริง
