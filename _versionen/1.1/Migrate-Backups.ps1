# Einmalige Umstellung der Ablage: aus den alten ZIP-Archiven unter
# snapshots\ werden Ordner unter Charaktere\ bzw. Gesamtstand\.
#
#   Vorschau:  powershell -File Migrate-Backups.ps1 -Vorschau
#   Umstellen: powershell -File Migrate-Backups.ps1
#
# Vor dem echten Lauf wird der komplette Backup-Ordner kopiert. Erst wenn
# jedes einzelne Archiv fehlerfrei entpackt wurde, verschwindet snapshots\.
#
# Die Funktionen kommen aus dem Programm selbst, damit Ordnernamen und
# _INFO.txt exakt so entstehen wie bei einer neuen Sicherung.

param([switch]$Vorschau)

$ErrorActionPreference = 'Stop'
foreach ($asm in 'PresentationFramework','System.IO.Compression','System.IO.Compression.FileSystem') {
    try { Add-Type -AssemblyName $asm -ErrorAction Stop } catch { }
}

$AppSkript = Join-Path $PSScriptRoot 'D2RCharBackupManager.ps1'
if (-not (Test-Path -LiteralPath $AppSkript)) {
    Write-Host "Fehler: $AppSkript nicht gefunden." -ForegroundColor Red; exit 1
}

# Nur die Funktionen und harmlosen Konstanten übernehmen, nicht die Oberfläche.
$ast = [System.Management.Automation.Language.Parser]::ParseFile($AppSkript, [ref]$null, [ref]$null)
foreach ($a in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $false)) {
    if ($a.Left.Extent.Text -match '^\$script:(AppName|AppVersion|ExcludedExtensions|DefaultClassNames|TextsEn)$') {
        Invoke-Expression $a.Extent.Text
    }
}
foreach ($f in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
    Invoke-Expression $f.Extent.Text
}

$script:ScriptDir  = $PSScriptRoot   # von New-DefaultConfig benötigt
$script:ConfigPath = Join-Path $PSScriptRoot 'config.json'
$script:Config     = Import-Config
$BackupPath        = $script:Config.BackupPath
$AlteAblage        = Join-Path $BackupPath 'snapshots'

Write-Host ''
Write-Host "  Backup-Ordner: $BackupPath"

Import-Index

# Sicherungen aus der Zeit vor dem Hexenbeschwörer tragen noch
# "Klasse 7 (unbekannt)". Die Klasse eines Charakters ändert sich nie, also
# lässt sie sich aus dem aktuellen Spielstand nachtragen — sonst stünde der
# alte Text für immer im Ordnernamen.
foreach ($r in @($script:Index.snapshots)) {
    if ($r.kind -ne 'char' -or -not $r.char) { continue }
    if ($r.className -notmatch '^(Klasse|Class) \d+') { continue }
    $d2s = Join-Path $script:Config.SavePath ($r.char + '.d2s')
    if (Test-Path -LiteralPath $d2s) {
        $info = Get-D2SInfo $d2s
        if ($info.Valid -and $info.ClassName -notmatch '^(Klasse|Class) \d+') {
            Write-Host ("  Klasse nachgetragen: {0} -> {1}" -f $r.char, $info.ClassName) -ForegroundColor DarkGray
            $r.className = $info.ClassName
        }
    }
}

$alle = @($script:Index.snapshots)
$alt  = @($alle | Where-Object { -not ($_.PSObject.Properties['pfad'] -and $_.pfad) })

Write-Host ("  Sicherungen gesamt: {0}, davon im alten Format: {1}" -f $alle.Count, $alt.Count)
Write-Host ''

if ($alt.Count -eq 0) {
    Write-Host '  Nichts zu tun - es liegt schon alles im neuen Format.' -ForegroundColor Green
    Write-Host ''
    exit 0
}

# ------------------------------------------------------------------ Vorschau

if ($Vorschau) {
    Write-Host '  VORSCHAU - es wird nichts verändert' -ForegroundColor Cyan
    Write-Host ''
    foreach ($r in ($alt | Select-Object -First 12)) {
        $ziel = if ($r.kind -eq 'char') {
            'Charaktere\{0}\{1} Lvl{2} {3}' -f $r.char, (Format-Timestamp $r.created 'yyyy-MM-dd_HHmmss'), $r.level, $r.className
        } else {
            'Gesamtstand\{0}' -f (Format-Timestamp $r.created 'yyyy-MM-dd_HHmmss')
        }
        Write-Host ("    {0,-28} -> {1}" -f $r.zip, $ziel)
    }
    if ($alt.Count -gt 12) { Write-Host ("    ... und {0} weitere" -f ($alt.Count - 12)) -ForegroundColor DarkGray }
    Write-Host ''
    Write-Host '  Zum Umstellen dasselbe Skript ohne -Vorschau aufrufen.' -ForegroundColor DarkGray
    Write-Host ''
    exit 0
}

# --------------------------------------------------------- Sicherheitskopie

$Kopie = '{0}_vor_Umstellung_{1}' -f $BackupPath.TrimEnd('\'), (Get-Date -Format 'yyyy-MM-dd_HHmm')
Write-Host "  Sicherheitskopie: $Kopie"
Copy-Item -LiteralPath $BackupPath -Destination $Kopie -Recurse -Force
Write-Host ("  angelegt ({0} Dateien)" -f @(Get-ChildItem -LiteralPath $Kopie -Recurse -File).Count) -ForegroundColor Green
Write-Host ''

# ------------------------------------------------------------------ Umstellen

$ok = 0; $fehler = @()
$neueListe = @()

foreach ($r in $alle) {
    if ($r.PSObject.Properties['pfad'] -and $r.pfad) { $neueListe += $r; continue }

    $zipPfad = Join-Path $AlteAblage $r.zip
    if (-not (Test-Path -LiteralPath $zipPfad)) {
        $fehler += "$($r.zip): Archiv fehlt"
        $neueListe += $r
        continue
    }

    try {
        $stempel = Format-Timestamp $r.created 'yyyy-MM-dd_HHmmss'
        if ($r.kind -eq 'char') {
            $basis = Join-Path (Get-CharsDir) (ConvertTo-SichererName $r.char)
            $name  = ConvertTo-SichererName ('{0} Lvl{1} {2}' -f $stempel, $r.level, $r.className)
        } else {
            $basis = Get-FullDir
            $name  = $stempel
        }
        $ordner = New-SnapshotOrdner -Basis $basis -Name $name

        $stream = [System.IO.File]::Open($zipPfad, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)
        try {
            $archiv = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Read)
            try {
                foreach ($e in $archiv.Entries) {
                    if (-not $e.Name) { continue }
                    $bereich = ($e.FullName -split '/')[0]
                    $unter   = if ($bereich -eq 'stash') { Join-Path $ordner 'SharedStash' } else { $ordner }
                    if (-not (Test-Path -LiteralPath $unter)) { New-Item -ItemType Directory -Path $unter -Force | Out-Null }
                    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, (Join-Path $unter $e.Name), $true)
                }
            } finally { $archiv.Dispose() }
        } finally { $stream.Dispose() }

        $relPfad = $ordner.Substring($BackupPath.TrimEnd('\').Length + 1)
        $r | Add-Member NoteProperty pfad $relPfad -Force
        $r.sizeBytes = [long](Get-ChildItem -LiteralPath $ordner -Recurse -File | Measure-Object Length -Sum).Sum
        $r.PSObject.Properties.Remove('zip')

        Write-SnapshotInfo $r
        $neueListe += $r
        $ok++
    } catch {
        $fehler += "$($r.zip): $($_.Exception.Message)"
        $neueListe += $r
    }
}

$script:Index.snapshots = $neueListe
Export-Index
Write-BackupLiesmich

Write-Host ("  Umgestellt: {0} von {1}" -f $ok, $alt.Count) -ForegroundColor $(if ($fehler.Count -eq 0) { 'Green' } else { 'Yellow' })
if ($fehler.Count -gt 0) {
    Write-Host ''
    Write-Host "  Nicht umgestellt ($($fehler.Count)):" -ForegroundColor Red
    $fehler | ForEach-Object { Write-Host "    $_" }
    Write-Host ''
    Write-Host '  Der alte Ordner snapshots\ bleibt deshalb liegen.' -ForegroundColor Yellow
} else {
    Remove-Item -LiteralPath $AlteAblage -Recurse -Force
    Write-Host '  Alter Ordner snapshots\ entfernt.' -ForegroundColor Green
}

Write-Host ''
Write-Host '  Bitte das Programm neu starten, damit es den neuen Stand liest.'
Write-Host "  Die Sicherheitskopie kann weg, sobald du dich überzeugt hast: $Kopie"
Write-Host ''
