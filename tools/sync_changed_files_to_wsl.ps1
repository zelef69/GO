[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$WslRepoRoot = "/home/master/src_ext4/brave",
    [string]$WslDistro = "Ubuntu",
    [string]$PathList,
    [switch]$IncludeUntracked,
    [switch]$VerifyOnly,
    [switch]$WriteSyncList,
    [string]$SyncListPath = ".codex_build_sync_list.txt"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $RepoRoot) {
    $scriptDir = Split-Path -Parent $PSCommandPath
    $RepoRoot = (Resolve-Path (Join-Path $scriptDir "..")).Path
}

function Get-RepoRelativePaths {
    param(
        [string]$RepoRootPath,
        [string]$ExplicitPathList,
        [switch]$AlsoIncludeUntracked
    )

    if ($ExplicitPathList) {
        $pathListFile = if ([System.IO.Path]::IsPathRooted($ExplicitPathList)) {
            $ExplicitPathList
        } else {
            Join-Path $RepoRootPath $ExplicitPathList
        }

        if (-not (Test-Path -LiteralPath $pathListFile)) {
            throw "Path list not found: $pathListFile"
        }

        return Get-Content -LiteralPath $pathListFile |
            Where-Object { $_ -and -not $_.StartsWith("#") } |
            ForEach-Object { $_.Trim().Replace("\", "/") } |
            Sort-Object -Unique
    }

    $modified = @(git -c core.safecrlf=false -C $RepoRootPath diff --name-only --diff-filter=ACMRTUXB HEAD 2>$null)
    $paths = @($modified)

    if ($AlsoIncludeUntracked) {
        $allowedUntrackedPrefixes = @(
            "AGENTS.md",
            "README.md",
            "BUILD.gn",
            "android/",
            "app/",
            "base/",
            "browser/",
            "build/",
            "chromium_src/",
            "common/",
            "components/",
            "content/",
            "docs/",
            "extensions/",
            "installer/",
            "net/",
            "patches/",
            "resources/",
            "renderer/",
            "sandbox/",
            "script/",
            "services/",
            "test/",
            "third_party/",
            "tools/",
            "ui/",
            "updater/",
            "utility/",
            "vendor/"
        )

        $untracked = @(git -c core.safecrlf=false -C $RepoRootPath ls-files --others --exclude-standard 2>$null)
        $untracked = $untracked | Where-Object {
            $candidate = $_.Trim().Replace("\", "/")
            $allowedUntrackedPrefixes | Where-Object { $candidate.StartsWith($_) }
        }
        $paths += $untracked
    }

    return $paths |
        Where-Object { $_ } |
        ForEach-Object { $_.Trim().Replace("\", "/") } |
        Sort-Object -Unique
}

function Convert-WslPathToUnc {
    param(
        [string]$Distro,
        [string]$LinuxPath
    )

    $trimmed = $LinuxPath.TrimStart("/")
    $windowsStyle = $trimmed.Replace("/", "\")
    return "\\wsl.localhost\$Distro\$windowsStyle"
}

function Get-Sha256 {
    param([string]$LiteralPath)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $LiteralPath).Hash.ToLowerInvariant()
}

if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot ".git"))) {
    throw "Repo root does not contain .git: $RepoRoot"
}

$repoRootResolved = (Resolve-Path -LiteralPath $RepoRoot).Path
$wslUncRoot = Convert-WslPathToUnc -Distro $WslDistro -LinuxPath $WslRepoRoot

if (-not (Test-Path -LiteralPath $wslUncRoot)) {
    throw "WSL repo root not found via UNC path: $wslUncRoot"
}

$relativePaths = @(Get-RepoRelativePaths -RepoRootPath $repoRootResolved -ExplicitPathList $PathList -AlsoIncludeUntracked:$IncludeUntracked)

if (-not $relativePaths.Count) {
    Write-Host "No files selected for sync."
    exit 0
}

$existingFiles = [System.Collections.Generic.List[string]]::new()
$deletedOrMissing = [System.Collections.Generic.List[string]]::new()
$invalidPathEntries = [System.Collections.Generic.List[string]]::new()

foreach ($relativePath in $relativePaths) {
    try {
        $sourcePath = Join-Path $repoRootResolved $relativePath
        if (Test-Path -LiteralPath $sourcePath -PathType Leaf) {
            $existingFiles.Add($relativePath)
        } else {
            $deletedOrMissing.Add($relativePath)
        }
    } catch {
        $invalidPathEntries.Add($relativePath)
    }
}

if ($WriteSyncList) {
    $syncListPath = if ([System.IO.Path]::IsPathRooted($SyncListPath)) {
        $SyncListPath
    } else {
        Join-Path $repoRootResolved $SyncListPath
    }
    Set-Content -LiteralPath $syncListPath -Value ($existingFiles | Sort-Object)
}

if (-not $VerifyOnly) {
    foreach ($relativePath in $existingFiles) {
        $sourcePath = Join-Path $repoRootResolved $relativePath
        $targetPath = Join-Path $wslUncRoot ($relativePath.Replace("/", "\"))
        $targetDir = Split-Path -Parent $targetPath

        if (-not (Test-Path -LiteralPath $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }

        Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
    }
}

$mismatches = [System.Collections.Generic.List[string]]::new()

foreach ($relativePath in $existingFiles) {
    $sourcePath = Join-Path $repoRootResolved $relativePath
    $targetPath = Join-Path $wslUncRoot ($relativePath.Replace("/", "\"))

    if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
        $mismatches.Add("$relativePath :: target missing in WSL")
        continue
    }

    $sourceHash = Get-Sha256 -LiteralPath $sourcePath
    $targetHash = Get-Sha256 -LiteralPath $targetPath

    if ($sourceHash -ne $targetHash) {
        $mismatches.Add("$relativePath :: hash mismatch ($sourceHash != $targetHash)")
    }
}

Write-Host "Repo root: $repoRootResolved"
Write-Host "WSL repo root: $WslRepoRoot"
Write-Host "WSL UNC root: $wslUncRoot"
Write-Host "Selected files: $($relativePaths.Count)"
Write-Host "Copied or verified files: $($existingFiles.Count)"

if ($deletedOrMissing.Count) {
    Write-Host ""
    Write-Host "Deleted or missing in Windows repo (not removed from WSL automatically):"
    $deletedOrMissing | ForEach-Object { Write-Host "  $_" }
}

if ($invalidPathEntries.Count) {
    Write-Host ""
    Write-Host "Skipped invalid Windows path entries:"
    $invalidPathEntries | ForEach-Object { Write-Host "  $_" }
}

if ($mismatches.Count) {
    Write-Host ""
    Write-Host "Verification mismatches:"
    $mismatches | ForEach-Object { Write-Host "  $_" }
    exit 1
}

Write-Host ""
Write-Host "Windows -> WSL sync verification passed."
