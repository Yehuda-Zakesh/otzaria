# מריץ את אבחון המשאבים המלא:
#   1. מגבה את נתוני המשתמש (טאבים/היסטוריה/סימניות) שהסימולציה עלולה לדרוס.
#   2. מפעיל דוגם CPU/RAM חיצוני ברקע.
#   3. מריץ את תרחיש השימוש (flutter drive, מצב profile).
#   4. עוצר את הדוגם, משחזר את נתוני המשתמש, ומדפיס היכן הפלט.
#
# ניתוח התוצאות: dart run tool/perf_probe/analyze.dart <run-dir>
param(
  [string]$Mode = "profile",   # profile | debug
  [string]$Target = "integration_test/perf_resource_probe_test.dart",
  [switch]$SkipBackup
)

$ErrorActionPreference = "Stop"

$repo = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$probeRoot = Join-Path $env:TEMP "otzaria_perf_probe"
$runStamp = (Get-Date).ToString("yyyyMMdd_HHmmss", [System.Globalization.CultureInfo]::InvariantCulture)
$runDir = Join-Path $probeRoot ("run_" + $runStamp)
$phasesFile = Join-Path $probeRoot "phases.jsonl"
$heapFile = Join-Path $probeRoot "heap.jsonl"
$summaryFile = Join-Path $probeRoot "reader_scroll_summary.txt"
$samplesCsv = Join-Path $runDir "samples.csv"
$stopFile = Join-Path $runDir "sampler.stop"
$driveLog = Join-Path $runDir "flutter_drive.log"

New-Item -ItemType Directory -Force -Path $probeRoot, $runDir | Out-Null
Remove-Item -LiteralPath $phasesFile -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $heapFile -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $summaryFile -ErrorAction SilentlyContinue

if (Get-Process -Name "otzaria" -ErrorAction SilentlyContinue) {
  throw "otzaria כבר רץ — יש לסגור אותו לפני הרצת האבחון (בדיקת single-instance תפיל את התרחיש)."
}

# --- גיבוי נתוני משתמש שהסימולציה משנה (Hive) ---
$dataRoot = Join-Path $env:APPDATA "otzaria"
$backupDir = Join-Path $runDir "user_data_backup"
$hiveFiles = @("tabs.hive", "history.hive", "bookmarks.hive", "workspaces.hive")
if (-not $SkipBackup) {
  New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
  foreach ($f in $hiveFiles) {
    $src = Join-Path $dataRoot $f
    if (Test-Path $src) { Copy-Item -LiteralPath $src -Destination $backupDir }
  }
  Write-Host "גיבוי נתוני משתמש: $backupDir"
}

# --- הפעלת הדוגם ברקע ---
$samplerScript = Join-Path $PSScriptRoot "sample_resources.ps1"
$sampler = Start-Process -FilePath "pwsh" -WindowStyle Hidden -PassThru -ArgumentList @(
  "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $samplerScript,
  "-OutCsv", $samplesCsv, "-StopFile", $stopFile, "-IntervalMs", "500"
)
Write-Host "דוגם משאבים רץ (PID $($sampler.Id))"

# --- הרצת התרחיש ---
try {
  Push-Location $repo
  try {
    flutter drive `
      --driver=test_driver/integration_test.dart `
      --target=$Target `
      -d windows `
      --$Mode `
      --dart-define=SENTRY_DSN= `
      2>&1 | Tee-Object -FilePath $driveLog
    $driveExit = $LASTEXITCODE
  } finally {
    Pop-Location
  }
} finally {
  # --- עצירת הדוגם ---
  New-Item -ItemType File -Force -Path $stopFile | Out-Null
  Wait-Process -Id $sampler.Id -Timeout 15 -ErrorAction SilentlyContinue

  # --- שחזור נתוני משתמש ---
  if (-not $SkipBackup) {
    foreach ($f in $hiveFiles) {
      $bak = Join-Path $backupDir $f
      if (Test-Path $bak) { Copy-Item -LiteralPath $bak -Destination (Join-Path $dataRoot $f) -Force }
    }
    Write-Host "נתוני המשתמש שוחזרו מהגיבוי."
  }

  if (Test-Path $phasesFile) {
    Copy-Item -LiteralPath $phasesFile -Destination (Join-Path $runDir "phases.jsonl") -Force
  }
  if (Test-Path $heapFile) {
    Copy-Item -LiteralPath $heapFile -Destination (Join-Path $runDir "heap.jsonl") -Force
  }
  if (Test-Path $summaryFile) {
    Copy-Item -LiteralPath $summaryFile -Destination (Join-Path $runDir "reader_scroll_summary.txt") -Force
  }
}

Write-Host ""
Write-Host "exit code של flutter drive: $driveExit"
Write-Host "תוצאות ההרצה: $runDir"
Write-Host "לניתוח: dart run tool/perf_probe/analyze.dart `"$runDir`""
exit $driveExit
