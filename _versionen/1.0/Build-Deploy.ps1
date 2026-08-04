# Baut das Weitergabe-Paket für Freunde.
#
# Ergebnis: _deploy\D2R-Char-Backup-Manager-<Version>.zip
# Beim Auspacken entsteht ein Ordner mit Programm, Starter und beiden
# Anleitungen. Die Versionsnummer wird aus dem Skript gelesen, damit sie
# nicht doppelt gepflegt werden muss.
#
# Bewusst NICHT im Paket:
#   config.json      persönliche Pfade
#   Backups\         die eigenen Sicherungen
#   README.md        Entwicklerdoku
#   Test-Sandbox.ps1 Testskript
#   Build-Deploy.ps1 dieses Skript

$ErrorActionPreference = 'Stop'
# Beide nötig: ZipFile/ZipFileExtensions stecken in .FileSystem,
# ZipArchive/ZipArchiveMode in System.IO.Compression.
foreach ($asm in 'System.IO.Compression', 'System.IO.Compression.FileSystem') {
    try { Add-Type -AssemblyName $asm -ErrorAction Stop } catch { }
}

$Quelle  = $PSScriptRoot
$Skript  = Join-Path $Quelle 'D2RCharBackupManager.ps1'
$Inhalt  = @('D2RCharBackupManager.ps1', 'Start D2R Char Backup Manager.cmd',
             'ANLEITUNG.md', 'INSTRUCTIONS.md')

if (-not (Test-Path -LiteralPath $Skript)) {
    Write-Host "Fehler: $Skript nicht gefunden." -ForegroundColor Red
    exit 1
}

# Version aus dem Skript ziehen statt hier zu wiederholen.
$treffer = Select-String -LiteralPath $Skript -Pattern "AppVersion\s*=\s*'([^']+)'" | Select-Object -First 1
if (-not $treffer) {
    Write-Host 'Fehler: AppVersion nicht im Skript gefunden.' -ForegroundColor Red
    exit 1
}
$Version = $treffer.Matches[0].Groups[1].Value
$Name    = "D2R-Char-Backup-Manager-$Version"

$fehlt = @($Inhalt | Where-Object { -not (Test-Path -LiteralPath (Join-Path $Quelle $_)) })
if ($fehlt.Count -gt 0) {
    Write-Host "Fehler: es fehlen $($fehlt -join ', ')" -ForegroundColor Red
    exit 1
}

$DeployDir = Join-Path $Quelle '_deploy'
$Bauplatz  = Join-Path $DeployDir $Name
$Zip       = Join-Path $DeployDir "$Name.zip"

if (Test-Path -LiteralPath $Bauplatz) { Remove-Item -LiteralPath $Bauplatz -Recurse -Force }
if (Test-Path -LiteralPath $Zip)      { Remove-Item -LiteralPath $Zip -Force }
New-Item -ItemType Directory -Path $Bauplatz -Force | Out-Null

foreach ($datei in $Inhalt) {
    Copy-Item -LiteralPath (Join-Path $Quelle $datei) -Destination $Bauplatz
}

# Einträge einzeln setzen statt CreateFromDirectory: so liegt im Archiv genau
# ein sauberer Ordner, und es kann nichts Ungewolltes mit hineinrutschen.
$stream = [System.IO.File]::Open($Zip, [System.IO.FileMode]::Create)
try {
    $archiv = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($datei in $Inhalt) {
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $archiv, (Join-Path $Bauplatz $datei), "$Name/$datei",
                [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
        }
    } finally { $archiv.Dispose() }
} finally { $stream.Dispose() }

Remove-Item -LiteralPath $Bauplatz -Recurse -Force

$groesse = (Get-Item -LiteralPath $Zip).Length
Write-Host ''
Write-Host "  Paket erstellt: $Zip"
Write-Host ("  Version {0}, {1} Dateien, {2:N1} KB" -f $Version, $Inhalt.Count, ($groesse / 1KB))
Write-Host ''
Write-Host '  Beim Auspacken entsteht der Ordner:'
Write-Host "    $Name\"
foreach ($datei in $Inhalt) { Write-Host "      $datei" }
Write-Host ''
Write-Host '  Hinweis für den Empfänger: kommt das ZIP aus dem Internet, vor dem'
Write-Host '  Auspacken Rechtsklick auf die ZIP-Datei, Eigenschaften, "Zulassen".'
Write-Host ''
