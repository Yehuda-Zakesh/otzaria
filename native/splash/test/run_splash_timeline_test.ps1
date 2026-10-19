# מקמפל ומריץ את טסט ציר הזמן של ה-splash עם MSVC (נמצא דרך vswhere).
$ErrorActionPreference = 'Stop'
$testDir = $PSScriptRoot
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw 'MSVC not found' }
$vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'
$out = Join-Path ([IO.Path]::GetTempPath()) ("splash_timeline_test_" + [Guid]::NewGuid())
New-Item -ItemType Directory $out | Out-Null
try {
  $src = Join-Path $testDir 'splash_timeline_test.cpp'
  cmd /c "call `"$vcvars`" >nul && cl /nologo /std:c++17 /W4 /WX /EHsc /utf-8 `"$src`" /Fo`"$out\\`" /Fe`"$out\splash_timeline_test.exe`""
  if ($LASTEXITCODE -ne 0) { throw 'compile failed' }
  & "$out\splash_timeline_test.exe"
  if ($LASTEXITCODE -ne 0) { throw 'tests failed' }
} finally {
  Remove-Item -Recurse -Force $out
}
