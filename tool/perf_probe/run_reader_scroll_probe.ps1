# מדידת גלילה בקורא (integration_test/reader_scroll_probe_test.dart) במצב profile.
# עוטף את run_perf_probe.ps1: גיבוי ושחזור נתוני המשתמש, ודוגם CPU/RAM.
param([string]$Mode = "profile", [switch]$SkipBackup)

& (Join-Path $PSScriptRoot "run_perf_probe.ps1") `
  -Mode $Mode `
  -Target "integration_test/reader_scroll_probe_test.dart" `
  -SkipBackup:$SkipBackup
exit $LASTEXITCODE
