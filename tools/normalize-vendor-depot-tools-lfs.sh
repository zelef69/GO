#!/usr/bin/env bash
set -euo pipefail

ROOT="/mnt/c/Users/Master/src/brave/vendor/depot_tools"

python3 - "$ROOT" <<'PY'
import os
import sys

root = sys.argv[1]
converted = 0
checked = 0
skip_dirs = {'.git'}
skip_exts = {
    '.exe', '.dll', '.so', '.dylib', '.zip', '.png', '.jpg', '.jpeg', '.gif',
    '.ico', '.pdf', '.bin', '.obj', '.lib', '.a', '.o', '.pyc', '.pyo', '.pyd'
}
for dp, dns, fns in os.walk(root):
    dns[:] = [d for d in dns if d not in skip_dirs]
    for fn in fns:
        path = os.path.join(dp, fn)
        _, ext = os.path.splitext(fn)
        if ext.lower() in skip_exts:
            continue
        try:
            with open(path, 'rb') as f:
                data = f.read()
            checked += 1
            if b'\x00' in data:
                continue
            new_data = data.replace(b'\r\n', b'\n')
            if new_data != data:
                with open(path, 'wb') as f:
                    f.write(new_data)
                converted += 1
        except Exception:
            pass
print(f'checked={checked}')
print(f'converted={converted}')
PY
