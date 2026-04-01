import re
import os
import subprocess
import sys

DEPS_PATH = r'C:\Users\Master\src\DEPS'
SRC_ROOT  = r'C:\Users\Master\src'
CIPD_BAT  = r'C:\Users\Master\src\third_party\depot_tools\cipd.bat'

with open(DEPS_PATH, encoding='utf-8') as f:
    text = f.read()

# Parse Var() definitions
vars_dict = {}
vars_blob = re.search(r'vars\s*=\s*\{(.+?)\n\}\s*deps\s*=', text, re.DOTALL)
if vars_blob:
    for m in re.finditer(r"'(\w+)'\s*:\s*'([^']+)'", vars_blob.group(1)):
        vars_dict[m.group(1)] = m.group(2)

def resolve_var(v):
    return re.sub(r"Var\('(\w+)'\)", lambda m: vars_dict.get(m.group(1), ''), v)

# Match CIPD dependency blocks
pattern = re.compile(
    r"'(src/third_party/[^']+)'\s*:\s*\{[^}]+?dep_type\s*:\s*'cipd'[^}]*?\}",
    re.DOTALL
)

packages = []
seen = set()
for block in pattern.finditer(text):
    raw = block.group(0)
    if 'checkout_android' not in raw:
        continue
    dest_src = block.group(1)
    for pm in re.finditer(
        r"'package'\s*:\s*'([^']+)'\s*,\s*\n\s*'version'\s*:\s*([^\n,]+)",
        raw
    ):
        pkg = pm.group(1)
        ver_raw = pm.group(2).strip().strip("'")
        ver = resolve_var(ver_raw)
        dest_win = os.path.join(SRC_ROOT, dest_src.replace('src/', '', 1).replace('/', os.sep))
        key = (pkg, dest_win)
        if key in seen:
            continue
        seen.add(key)
        packages.append((pkg, ver, dest_win))

print(f"Found {len(packages)} Android CIPD packages to check.")

for pkg, ver, dest in packages:
    # Check if already populated (has files beyond .cipd marker)
    existing = []
    if os.path.isdir(dest):
        existing = [x for x in os.listdir(dest) if not x.startswith('.')]
    if existing:
        print(f"[SKIP] {pkg} (already populated)")
        continue

    print(f"[INSTALL] {pkg} @ {ver[:20]}...")
    os.makedirs(dest, exist_ok=True)
    ensure_file = os.path.join(os.environ.get('TEMP', 'C:\\Temp'), f'cipd-ensure-{hash(pkg)}.txt')
    with open(ensure_file, 'w', encoding='ascii') as ef:
        ef.write(f'{pkg} {ver}\n')

    result = subprocess.run(
        [CIPD_BAT, 'ensure', '-root', dest, '-ensure-file', ensure_file],
        capture_output=True, text=True
    )
    if result.returncode == 0:
        print(f"[OK] {pkg}")
    else:
        print(f"[FAIL] {pkg}: {result.stderr[-400:]}")
    try:
        os.remove(ensure_file)
    except Exception:
        pass

print("Done.")
