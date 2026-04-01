# Install all Android CIPD dependencies from DEPS file directly
# Avoids gclient sync which fails in Windows+WSL combination

$cipdBat = 'C:\Users\Master\src\third_party\depot_tools\cipd.bat'
$srcRoot = 'C:\Users\Master\src'
$depsFile = Join-Path $srcRoot 'DEPS'

# Key Android CIPD deps from DEPS file:
# Format: @(package, version, relative-dest)
$packages = @(
    @('chromium/third_party/android_sdk/public/build-tools/36.1.0',   '-jLl4Ibk_WmgTsZaP-ueQwZDhBwkWf5BsQ4UNrkzXF0C', 'third_party\android_sdk\public\build-tools\36.1.0'),
    @('chromium/third_party/android_sdk/public/emulator',             '9lGp8nTUCRRWGMnI_96HcKfzjnxEJKUcfvfwmA3wXNkC',  'third_party\android_sdk\public\emulator'),
    @('chromium/third_party/android_sdk/public/platform-tools',       'qTD9QdBlBf3dyHsN1lJ0RH6AhHxR42Hmg2Ih-Vj4zIEC',  'third_party\android_sdk\public\platform-tools'),
    @('chromium/third_party/android_sdk/public/platforms/android-36.1','gxwLT70eR_ObwZJzKK8UIS-N549yAocNTmc0JHgO7gUC', 'third_party\android_sdk\public\platforms\android-36.1'),
    @('chromium/third_party/jdk/linux-amd64',                         '2iiuF-nKDH3moTImx2op4WTRetbfhzKoZhH7Xo44zGsC',  'third_party\jdk\current'),
    @('chromium/third_party/turbine',                                  'BMHNhxMhr7uGz1rh_Od_JE4kAdP9K5MXr6GN2R9tQkAC',  'third_party\turbine\cipd')
)

foreach ($pkg in $packages) {
    $pkgName  = $pkg[0]
    $pkgVer   = $pkg[1]
    $destRel  = $pkg[2]
    $destAbs  = Join-Path $srcRoot $destRel

    # Check if already installed (has content beyond .cipd folder)
    $existing = Get-ChildItem $destAbs -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '^\.' }
    if ($existing) {
        Write-Host "[SKIP] $pkgName - already populated at $destAbs" -ForegroundColor DarkGray
        continue
    }

    Write-Host "[INSTALL] $pkgName @ $pkgVer -> $destAbs" -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path $destAbs | Out-Null

    $ensureFile = Join-Path $env:TEMP "ensure-cipd-$([System.IO.Path]::GetRandomFileName()).txt"
    Set-Content -Path $ensureFile -Encoding ascii -Value "$pkgName $pkgVer"

    & $cipdBat ensure -root $destAbs -ensure-file $ensureFile
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Failed to install $pkgName" -ForegroundColor Red
    } else {
        Write-Host "[OK] $pkgName installed" -ForegroundColor Green
    }
    Remove-Item $ensureFile -ErrorAction SilentlyContinue
}

Write-Host "`nAll Android CIPD deps checked." -ForegroundColor Yellow
