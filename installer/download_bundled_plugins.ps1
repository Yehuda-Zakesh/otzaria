# מוריד את התוספים שברשימת ההיתר אל installer\bundled_plugins, כדי שהמתקין
# יארוז אותם ואוצריא תרשום אותם בעלייה הראשונה (docs/bundled_plugins.md).
#
# רשימת ההיתר היא lib/plugins/services/bundled_plugin_ids.dart — אותו קובץ
# שנקמפל אל תוך האפליקציה, כדי שלא תיווצר רשימה שנייה שיוצאת מסינכרון.
# כל רשומה היא זוג 'מזהה-חנות': 'מזהה-מניפסט[@פלטפורמות]' — ההורדה לפי מזהה
# החנות, והקובץ נשמר בשם מזהה המניפסט, שמולו האפליקציה מאמתת את הארכיון.
# רשימה ריקה = לא נוצרת תיקייה, וה-Source במתקין מדלג עליה.
#
# -Platform אופציונלי: שם הפלטפורמה הנבנית — רשומה עם סיומת @פלטפורמות
# שאינה כוללת אותו מדולגת. בלי הפרמטר אין סינון.

param([string]$Platform = '')

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$allowlistFile = Join-Path $repoRoot 'lib\plugins\services\bundled_plugin_ids.dart'
$outputDir = Join-Path $PSScriptRoot 'bundled_plugins'
$storeBaseUrl = 'https://otzaria.org'

if (-not (Test-Path $allowlistFile)) {
    throw "Bundled plugin allowlist not found: $allowlistFile"
}

# זוג יחיד במרכאות בשורה שאינה הערה — הפורמט שהקובץ מתחייב לו.
$plugins = @()
foreach ($line in Get-Content $allowlistFile) {
    $trimmed = $line.Trim()
    if ($trimmed.StartsWith('//') -or $trimmed.StartsWith('///')) { continue }
    $match = [regex]::Match($trimmed, "^'([^']+)':\s*'([^']+)',?$")
    if ($match.Success) {
        $valueParts = $match.Groups[2].Value.Split('@')
        $manifestId = $valueParts[0]
        if ($valueParts.Length -gt 1 -and $Platform) {
            $platforms = $valueParts[1].Split(',')
            if ($platforms -notcontains $Platform) {
                Write-Host "Skipping $manifestId - not for $Platform ($($valueParts[1]))"
                continue
            }
        }
        $plugins += [pscustomobject]@{
            StoreId    = $match.Groups[1].Value
            ManifestId = $manifestId
        }
    }
}

if ($plugins.Count -eq 0) {
    Write-Host 'No bundled plugins configured - skipping.'
    if (Test-Path $outputDir) { Remove-Item -Path $outputDir -Recurse -Force }
    exit 0
}

# גרסת האוצריא נשלחת לחנות כדי לקבל את גרסת התוסף התואמת ולא את האחרונה.
$versionLine = Select-String -Path (Join-Path $repoRoot 'pubspec.yaml') `
    -Pattern '^version:\s*(.+)$' | Select-Object -First 1
if (-not $versionLine) { throw 'Could not read version from pubspec.yaml' }
$appVersion = $versionLine.Matches[0].Groups[1].Value.Trim().Split('+')[0]
Write-Host "Downloading $($plugins.Count) bundled plugin(s) for Otzaria $appVersion"

if (Test-Path $outputDir) { Remove-Item -Path $outputDir -Recurse -Force }
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

foreach ($plugin in $plugins) {
    if ($plugin.StoreId -notmatch '^[A-Za-z0-9._-]+$') {
        throw "Invalid store id in allowlist: '$($plugin.StoreId)'"
    }
    if ($plugin.ManifestId -notmatch '^[A-Za-z0-9._-]+$') {
        throw "Invalid manifest id in allowlist: '$($plugin.ManifestId)'"
    }

    $target = Join-Path $outputDir "$($plugin.ManifestId).otzplugin"
    $url = "$storeBaseUrl/api/plugins/$($plugin.StoreId)/download?appVersion=$appVersion"
    Write-Host "  $($plugin.ManifestId) <- $url"
    # 404 = אין בחנות גרסת תוסף תואמת לאוצריא הזו. שינוי שמפתח תוסף עושה באתר
    # לא יפיל את כל הבנייה — מדלגים; כל שאר קודי התשובה נשארים קטלניים.
    $notCompatible = $false
    try {
        Invoke-WebRequest -Uri $url -OutFile $target -UseBasicParsing
    } catch {
        $response = $_.Exception.Response
        if ($null -eq $response -or [int]$response.StatusCode -ne 404) { throw }
        Write-Host "::warning::No '$($plugin.ManifestId)' release compatible with Otzaria $appVersion - not bundled"
        Remove-Item $target -Force -ErrorAction SilentlyContinue
        $notCompatible = $true
    }
    # continue בתוך catch יוצא מהלולאה כולה ב-PowerShell — לכן דגל.
    if ($notCompatible) { continue }

    # תשובת שגיאה שהוגשה כ-200 (דף HTML) נשמרת כארכיון תקין למראה ונכשלת רק
    # אצל המשתמש — בודקים את חתימת ה-ZIP כאן.
    $magic = [System.IO.File]::ReadAllBytes($target)[0..1]
    if ($magic[0] -ne 0x50 -or $magic[1] -ne 0x4B) {
        throw "Downloaded file for '$($plugin.ManifestId)' is not a zip archive"
    }

    # אימות מוקדם של החוזה מול האפליקציה: מזהה המניפסט שבארכיון חייב להתאים
    # לרשומה — אחרת ה-seeder ידחה את הארכיון בשקט אצל המשתמש.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($target)
    try {
        $entry = $zip.GetEntry('manifest.json')
        if (-not $entry) { throw "No manifest.json in archive for '$($plugin.ManifestId)'" }
        $reader = New-Object System.IO.StreamReader($entry.Open())
        $manifest = $reader.ReadToEnd() | ConvertFrom-Json
        $reader.Dispose()
    } finally {
        $zip.Dispose()
    }
    if ($manifest.id -ne $plugin.ManifestId) {
        throw "Manifest id mismatch for store id '$($plugin.StoreId)': allowlist says '$($plugin.ManifestId)' but archive declares '$($manifest.id)'"
    }

    $sizeKb = [math]::Round((Get-Item $target).Length / 1KB, 1)
    Write-Host "    ok ($sizeKb KB, v$($manifest.version))"
}

# כל התוספים דולגו — Source ריק במתקין, ולכן מתנהגים בדיוק כמו ברשימה ריקה.
if (-not (Get-ChildItem $outputDir -File)) {
    Write-Host 'No compatible bundled plugins - skipping.'
    Remove-Item -Path $outputDir -Recurse -Force
}
