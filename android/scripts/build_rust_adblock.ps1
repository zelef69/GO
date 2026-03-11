param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$manifest = Join-Path $ProjectRoot "rust\\adblock_jni\\Cargo.toml"
if (-not (Test-Path $manifest)) {
    Write-Error "Rust manifest not found: $manifest"
    exit 1
}

$cargoBin = Join-Path $env:USERPROFILE ".cargo\\bin"
$env:PATH = "$cargoBin;$env:PATH"

if (-not $env:ANDROID_NDK_HOME) {
    $defaultNdkRoot = Join-Path $env:LOCALAPPDATA "Android\\Sdk\\ndk"
    if (Test-Path $defaultNdkRoot) {
        $latestNdk = Get-ChildItem $defaultNdkRoot -Directory | Sort-Object Name | Select-Object -Last 1
        if ($latestNdk) {
            $env:ANDROID_NDK_HOME = $latestNdk.FullName
        }
    }
}

Push-Location $ProjectRoot
try {
    cargo ndk `
      -t armeabi-v7a `
      -t arm64-v8a `
      -t x86_64 `
      -o app/src/main/jniLibs `
      build `
      --manifest-path rust/adblock_jni/Cargo.toml `
      --release

    if ($LASTEXITCODE -ne 0) {
        cargo clean --manifest-path rust/adblock_jni/Cargo.toml
        cargo ndk `
          -t armeabi-v7a `
          -t arm64-v8a `
          -t x86_64 `
          -o app/src/main/jniLibs `
          build `
          --manifest-path rust/adblock_jni/Cargo.toml `
          --release
    }
} finally {
    Pop-Location
}
