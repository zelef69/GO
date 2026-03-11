#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

export PATH="${HOME}/.cargo/bin:${PATH}"

if [[ -z "${ANDROID_NDK_HOME:-}" && -d "${HOME}/Android/Sdk/ndk" ]]; then
  ANDROID_NDK_HOME="$(ls -1 "${HOME}/Android/Sdk/ndk" | sort | tail -n 1)"
  export ANDROID_NDK_HOME="${HOME}/Android/Sdk/ndk/${ANDROID_NDK_HOME}"
fi

cd "${PROJECT_ROOT}"

cargo ndk \
  -t armeabi-v7a \
  -t arm64-v8a \
  -t x86_64 \
  -o app/src/main/jniLibs \
  build \
  --manifest-path rust/adblock_jni/Cargo.toml \
  --release || {
    cargo clean --manifest-path rust/adblock_jni/Cargo.toml
    cargo ndk \
      -t armeabi-v7a \
      -t arm64-v8a \
      -t x86_64 \
      -o app/src/main/jniLibs \
      build \
      --manifest-path rust/adblock_jni/Cargo.toml \
      --release
  }
