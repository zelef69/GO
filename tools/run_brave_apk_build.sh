#!/usr/bin/env bash
set -euo pipefail

LOG=/mnt/c/Users/Master/src/brave/out_logs/apk_build_live.log
OUTPUT_DIR=/home/master/brave_out/android_Component_arm64
BRAVE_DIR=/mnt/c/Users/Master/src/brave

mkdir -p /mnt/c/Users/Master/src/brave/out_logs

pkill -f "commands.js build -C ${OUTPUT_DIR}" || true
pkill -f "autoninja -C ${OUTPUT_DIR} chrome_public_apk" || true
pkill -f "/usr/bin/ninja -j .* -C ${OUTPUT_DIR} chrome_public_apk" || true

cd "${BRAVE_DIR}"
export CHROMIUM_CHECKOUT_ROOT=/mnt/c/Users/Master/src
export PATH=/mnt/c/Users/Master/src/brave/out_logs/bin:/mnt/c/Users/Master/src/brave/vendor/depot_tools:/mnt/c/Users/Master/src/brave/vendor/depot_tools/.cipd_bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export AUTONINJA_BUILD_ID="${AUTONINJA_BUILD_ID:-onetabtube-wsl}"
export PYTHONPATH=/mnt/c/Users/Master/src/brave/script${PYTHONPATH:+:${PYTHONPATH}}

: > "${LOG}"
exec /usr/bin/ninja -j 14 -C "${OUTPUT_DIR}" chrome_public_apk -k 1 > "${LOG}" 2>&1
