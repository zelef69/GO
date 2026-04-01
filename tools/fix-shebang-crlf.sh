#!/usr/bin/env bash
set -euo pipefail

ROOT="/mnt/c/Users/Master/src"

count_crlf_shebang() {
  python3 - "$ROOT" <<'PY'
import os, sys
root = sys.argv[1]
skip = {'.git', 'node_modules', 'out'}
count = 0
for dp, dns, fns in os.walk(root):
    dns[:] = [d for d in dns if d not in skip]
    for fn in fns:
        p = os.path.join(dp, fn)
        try:
            with open(p, 'rb') as f:
                head = f.read(1024)
            if not head.startswith(b'#!'):
                continue
            nl = head.find(b'\n')
            if nl > 0 and head[nl-1:nl] == b'\r':
                count += 1
        except Exception:
            pass
print(count)
PY
}

fix_crlf_shebang() {
  python3 - "$ROOT" <<'PY'
import os, sys
root = sys.argv[1]
skip = {'.git', 'node_modules', 'out'}
fixed = 0
for dp, dns, fns in os.walk(root):
    dns[:] = [d for d in dns if d not in skip]
    for fn in fns:
        p = os.path.join(dp, fn)
        try:
            with open(p, 'rb') as f:
                data = f.read()
            if not data.startswith(b'#!'):
                continue
            nl = data.find(b'\n')
            if nl > 0 and data[nl-1:nl] == b'\r':
                data = data.replace(b'\r\n', b'\n')
                with open(p, 'wb') as f:
                    f.write(data)
                fixed += 1
        except Exception:
            pass
print(fixed)
PY
}

before=$(count_crlf_shebang)
echo "before=$before"
fixed=$(fix_crlf_shebang)
echo "fixed=$fixed"
after=$(count_crlf_shebang)
echo "after=$after"
