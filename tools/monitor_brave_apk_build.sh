#!/usr/bin/env bash
set -euo pipefail

STATUS_FILE=/mnt/c/Users/Master/src/brave/out_logs/apk_status_live.txt
LOG=/mnt/c/Users/Master/src/brave/out_logs/apk_build_live.log
APK_DIR=/home/master/brave_out/android_Component_arm64/apks

while true; do
  now=$(date '+%Y-%m-%d %H:%M:%S')
  {
    echo "[$now]"

    procs=$(ps -ef | grep -E '/usr/bin/ninja|autoninja|commands.js build' | grep -v grep || true)
    if [[ -n "${procs}" ]]; then
      echo 'PROCESSES:'
      echo "${procs}"
    else
      echo 'PROCESSES: none'
    fi

    progress=$(grep -ao '\[[0-9]\+/[0-9]\+\]' "${LOG}" 2>/dev/null | tail -n 1 || true)
    if [[ -n "${progress}" ]]; then
      echo "PROGRESS: ${progress}"
    else
      echo 'PROGRESS: none yet'
    fi

    apk=$(find "${APK_DIR}" -maxdepth 3 -type f 2>/dev/null | sort || true)
    if [[ -n "${apk}" ]]; then
      echo 'APK:'
      echo "${apk}"
    else
      echo 'APK: not yet'
    fi

    fails=$(grep -n -E 'FAILED:|AssertionError|Program autoninja exited|ninja: build stopped|error:' "${LOG}" | tail -n 20 || true)
    if [[ -n "${fails}" ]]; then
      echo 'FAILURES:'
      echo "${fails}"
    fi

    echo 'TAIL:'
    tail -n 20 "${LOG}" 2>/dev/null || true
  } > "${STATUS_FILE}"

  sleep 60
done