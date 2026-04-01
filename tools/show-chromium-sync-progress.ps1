param(
    [string]$HomePath = 'C:\Users\Master',
    [double]$ExpectedGiB = 61.49,
    [int]$RefreshSeconds = 2
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$expectedBytes = [double]($ExpectedGiB * 1GB)

function Format-Bytes {
    param([double]$Bytes)

    if ($Bytes -ge 1TB) {
        return ('{0:N2} TiB' -f ($Bytes / 1TB))
    }
    if ($Bytes -ge 1GB) {
        return ('{0:N2} GiB' -f ($Bytes / 1GB))
    }
    if ($Bytes -ge 1MB) {
        return ('{0:N2} MiB' -f ($Bytes / 1MB))
    }
    if ($Bytes -ge 1KB) {
        return ('{0:N2} KiB' -f ($Bytes / 1KB))
    }

    return ('{0:N0} B' -f $Bytes)
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Chromium Sync Progress'
$form.Size = New-Object System.Drawing.Size(560, 260)
$form.StartPosition = 'CenterScreen'
$form.TopMost = $true

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Location = New-Object System.Drawing.Point(20, 20)
$titleLabel.Size = New-Object System.Drawing.Size(500, 24)
$titleLabel.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$titleLabel.Text = 'Chromium sync download progress'
$form.Controls.Add($titleLabel)

$percentLabel = New-Object System.Windows.Forms.Label
$percentLabel.Location = New-Object System.Drawing.Point(20, 52)
$percentLabel.Size = New-Object System.Drawing.Size(500, 32)
$percentLabel.Font = New-Object System.Drawing.Font('Segoe UI', 18, [System.Drawing.FontStyle]::Bold)
$percentLabel.Text = '0.00%'
$form.Controls.Add($percentLabel)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(20, 92)
$progressBar.Size = New-Object System.Drawing.Size(500, 26)
$progressBar.Minimum = 0
$progressBar.Maximum = 1000
$progressBar.Style = 'Continuous'
$form.Controls.Add($progressBar)

$detailLabel = New-Object System.Windows.Forms.Label
$detailLabel.Location = New-Object System.Drawing.Point(20, 132)
$detailLabel.Size = New-Object System.Drawing.Size(500, 24)
$detailLabel.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.Controls.Add($detailLabel)

$repoLabel = New-Object System.Windows.Forms.Label
$repoLabel.Location = New-Object System.Drawing.Point(20, 156)
$repoLabel.Size = New-Object System.Drawing.Size(500, 24)
$repoLabel.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.Controls.Add($repoLabel)

$diskLabel = New-Object System.Windows.Forms.Label
$diskLabel.Location = New-Object System.Drawing.Point(20, 180)
$diskLabel.Size = New-Object System.Drawing.Size(500, 24)
$diskLabel.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.Controls.Add($diskLabel)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object System.Drawing.Point(20, 204)
$statusLabel.Size = New-Object System.Drawing.Size(500, 24)
$statusLabel.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$statusLabel.ForeColor = [System.Drawing.Color]::DimGray
$statusLabel.Text = 'Estimate based on current tmp_pack size versus announced remote transfer size.'
$form.Controls.Add($statusLabel)

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = [Math]::Max(1, $RefreshSeconds) * 1000

$updateUi = {
    $drive = Get-PSDrive C -ErrorAction SilentlyContinue
    if ($drive) {
        $diskLabel.Text = 'C: free {0:N2} GiB / used {1:N2} GiB' -f ($drive.Free / 1GB), ($drive.Used / 1GB)
    } else {
        $diskLabel.Text = 'C: drive information unavailable'
    }

    $repo = Get-ChildItem $HomePath -Force -Directory -Filter '_gclient_src_*' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $repo) {
        $progressBar.Style = 'Continuous'
        $percentLabel.Text = '0.00%'
        $progressBar.Value = 0
        $detailLabel.Text = 'No active _gclient_src_* directory found.'
        $repoLabel.Text = ''
        $statusLabel.Text = 'Waiting for Chromium sync to start...'
        return
    }

    $repoLabel.Text = 'Watching: {0}' -f $repo.FullName

    $tmpPack = Get-ChildItem (Join-Path $repo.FullName '.git\objects\pack') -Force -Filter 'tmp_pack*' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($tmpPack) {
        $now = Get-Date
        $secondsSinceWrite = ($now - $tmpPack.LastWriteTime).TotalSeconds
        $isIndexPackPhase = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -eq 'git.exe' -and
                $_.CommandLine -like '*index-pack*'
            } |
            Select-Object -First 1

        if ($isIndexPackPhase -and $secondsSinceWrite -gt 20) {
            $progressBar.Style = 'Marquee'
            $percentLabel.Text = 'Processing pack...'
            $detailLabel.Text = 'Downloaded {0}; Git is indexing/validating objects.' -f (Format-Bytes ([double]$tmpPack.Length))
            $statusLabel.Text = 'Index-pack phase can run for a long time without percentage changes.'
            return
        }

        $downloadedBytes = [double]$tmpPack.Length
        $percent = 0.0
        if ($expectedBytes -gt 0) {
            $percent = [Math]::Min(100.0, [Math]::Max(0.0, ($downloadedBytes / $expectedBytes) * 100.0))
        }

        $progressBar.Style = 'Continuous'
        $progressBar.Value = [int][Math]::Min(1000, [Math]::Round($percent * 10))
        $percentLabel.Text = '{0:N2}%' -f $percent
        $detailLabel.Text = '{0} of {1} via {2}' -f (Format-Bytes $downloadedBytes), (Format-Bytes $expectedBytes), $tmpPack.Name
        $statusLabel.Text = 'Download phase active.'
        return
    }

    if (Test-Path (Join-Path $HomePath 'src\chrome')) {
        $progressBar.Style = 'Continuous'
        $progressBar.Value = 1000
        $percentLabel.Text = '100.00%'
        $detailLabel.Text = 'Download stage completed; src\\chrome now exists.'
        $statusLabel.Text = 'Chromium checkout detected.'
        return
    }

    $progressBar.Style = 'Continuous'
    $percentLabel.Text = '0.00%'
    $progressBar.Value = 0
    $detailLabel.Text = 'No tmp_pack file is visible yet. Sync may be starting or between phases.'
    $statusLabel.Text = 'Waiting for download signal...'
}

$timer.Add_Tick($updateUi)
$form.Add_Shown({
    & $updateUi
    $timer.Start()
})
$form.Add_FormClosed({
    $timer.Stop()
    $timer.Dispose()
})

[void]$form.ShowDialog()