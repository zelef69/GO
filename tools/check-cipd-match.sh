#!/usr/bin/env bash
set -euo pipefail
cd /mnt/c/Users/Master/src/brave/vendor/depot_tools
PLATFORM="linux-amd64"
while IFS= read -r line; do
  if [[ "$line" =~ ^([0-9a-z-]+)[[:blank:]]+sha256[[:blank:]]+([0-9a-f]+)$ ]]; then
    plat="${BASH_REMATCH[1]}"
    hash="${BASH_REMATCH[2]}"
    if [[ "$plat" == "$PLATFORM" ]]; then
      echo "MATCH plat=$plat hashprefix=${hash:0:12}"
      exit 0
    fi
  fi
done < cipd_client_version.digests

echo "NO_MATCH"
exit 1
