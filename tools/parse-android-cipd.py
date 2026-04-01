"""
Parse DEPS file and emit all checkout_android CIPD packages.
Output format: PACKAGE VERSION DEST_PATH
"""
import re
import os
import sys

DEPS_PATH = r'C:\Users\Master\src\DEPS'
SRC_ROOT  = r'C:\Users\Master\src'

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
# Using a greedy multi-line approach for each top-level dict entry
pattern = re.compile(
    r"'(src/third_party/[^']+)'\s*:\s*\{[^}]+?dep_type[^}]+?\}",
    re.DOTALL
)

found = []
for block in pattern.finditer(text):
    raw = block.group(0)
    if 'cipd' not in raw:
        continue
    if 'checkout_android' not in raw:
        continue
    dest_src = block.group(1)

    # May have multiple packages per block
    for pm in re.finditer(r"'package'\s*:\s*'([^']+)'\s*,\s*\n\s*'version'\s*:\s*([^\n,]+)", raw):
        pkg = pm.group(1)
        ver_raw = pm.group(2).strip().strip("'")
        ver = resolve_var(ver_raw) if 'Var(' in ver_raw else ver_raw

        dest_win = os.path.join(SRC_ROOT, dest_src.replace('src/', '', 1).replace('/', os.sep))
        found.append((pkg, ver, dest_win))

for pkg, ver, dest in found:
    print(f'{pkg}|{ver}|{dest}')
