# Baut eine vollstaendige Demo-Umgebung zum Screenshots machen.
#
# Erzeugt einen eigenstaendigen Ordner mit einer Kopie des Programms, erfundenen
# Charakteren, fertigen Sicherungen und einer eigenen config.json. Danach reicht
# ein Doppelklick auf "Start Demo.cmd" - das Fenster sieht aus wie im echten
# Betrieb, zeigt aber ausschliesslich ausgedachte Namen.
#
# WARUM: Screenshots fuers oeffentliche README duerfen keine echten
# Charakternamen, Projektnamen oder Sicherungszeiten zeigen.
#
# SICHERHEIT: Dieses Skript fasst den echten Spielstand-Ordner NICHT an. Es
# liest ausschliesslich die Programmdatei und schreibt nur in den Zielordner,
# der standardmaessig unter %TEMP% liegt. Es loescht den Zielordner vorher -
# deshalb nur auf einen Ordner zeigen lassen, der weg darf.

param(
    # Wohin die Demo gebaut wird. Muss ein Ordner sein, der geloescht werden darf.
    [string]$Ziel = (Join-Path $env:TEMP 'D2R-Demo'),

    # Oberflaeche auf Deutsch statt Englisch.
    [switch]$Deutsch,

    # Nur anzeigen, was passieren wuerde.
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework -EA SilentlyContinue

$Basis   = $PSScriptRoot
$Quelle  = Join-Path $Basis 'D2RCharBackupManager.ps1'
$Sprache = if ($Deutsch) { 'de' } else { 'en' }

if (-not (Test-Path -LiteralPath $Quelle)) { throw "Programmdatei nicht gefunden: $Quelle" }

# Sicherheitsnetz: niemals auf den echten Spielstand-Ordner oder das Projekt zeigen.
$verboten = @($Basis, (Join-Path $env:USERPROFILE 'Saved Games'))
foreach ($v in $verboten) {
    if ($Ziel -like "$v*") { throw "Zielordner liegt in einem geschuetzten Bereich: $Ziel" }
}

$saves  = Join-Path $Ziel 'saves'
$backup = Join-Path $Ziel 'backup'

if ($DryRun) {
    Write-Host ''
    Write-Host '  TROCKENLAUF - es wird nichts geschrieben.'
    Write-Host ''
    Write-Host "  Wuerde loeschen und neu anlegen : $Ziel"
    Write-Host "  Darin Spielstand-Ordner        : $saves"
    Write-Host "  Darin Backup-Ordner            : $backup"
    Write-Host "  Programmkopie aus              : $Quelle"
    Write-Host "  Sprache                        : $Sprache"
    Write-Host ''
    Write-Host '  16 aktive und 4 geparkte Charaktere, dazu je eine Sicherung.'
    Write-Host '  Der echte Spielstand-Ordner wird nicht angefasst.'
    Write-Host ''
    return
}

if (Test-Path -LiteralPath $Ziel) { Remove-Item -LiteralPath $Ziel -Recurse -Force }
New-Item -ItemType Directory -Path $saves, $backup -Force | Out-Null

# --- erfundene Spielstaende ------------------------------------------------
# Aufbau des .d2s-Kopfes siehe ENTWICKLUNG.md. Fuer die Anzeige genuegen Magic,
# Version, Status, Klasse, Level und der Zeitstempel.
function New-DemoSave {
    param([string]$Pfad, [int]$Klasse, [int]$Level, [int]$Status, [int]$TageHer)
    $b = New-Object byte[] 192
    [BitConverter]::GetBytes([uint32]2857740885).CopyTo($b, 0)
    [BitConverter]::GetBytes([uint32]105).CopyTo($b, 4)
    [BitConverter]::GetBytes([uint32]192).CopyTo($b, 8)
    $base = 0x14
    $b[$base] = $Status; $b[$base+4] = $Klasse; $b[$base+5] = 0x10; $b[$base+6] = 0x1E; $b[$base+7] = $Level
    [BitConverter]::GetBytes([uint32]([DateTimeOffset]::new((Get-Date).AddDays(-$TageHer)).ToUnixTimeSeconds())).CopyTo($b, $base+12)
    [System.IO.File]::WriteAllBytes($Pfad, $b)
}

$aktiv = @(
    @{n='Ironhide';    k=4; l=92; s=0x20; t=1},  @{n='Frostbite';   k=1; l=88; s=0x20; t=2}
    @{n='Nightshade';  k=2; l=76; s=0x20; t=3},  @{n='Sunhammer';   k=3; l=99; s=0x20; t=4}
    @{n='Stormcaller'; k=0; l=64; s=0x20; t=6},  @{n='Ashwalker';   k=5; l=41; s=0x20; t=7}
    @{n='Silentblade'; k=6; l=57; s=0x24; t=9},  @{n='Hollowvoice'; k=7; l=33; s=0x20; t=11}
    @{n='Ravenclaw';   k=2; l=84; s=0x20; t=13}, @{n='Thornfield';  k=3; l=71; s=0x24; t=15}
    @{n='Glacierborn'; k=1; l=95; s=0x20; t=18}, @{n='Wolfsbane';   k=5; l=60; s=0x20; t=22}
    @{n='Quickstrike'; k=6; l=48; s=0x20; t=26}, @{n='Longbow';     k=0; l=79; s=0x20; t=31}
    @{n='Warbringer';  k=4; l=66; s=0x24; t=38}, @{n='Duskcaller';  k=7; l=52; s=0x20; t=45}
)
foreach ($a in $aktiv) {
    New-DemoSave (Join-Path $saves "$($a.n).d2s") $a.k $a.l $a.s $a.t
    foreach ($e in '.ctl','.key','.ma0','.map') { [System.IO.File]::WriteAllText((Join-Path $saves "$($a.n)$e"), ('x' * 900)) }
}
foreach ($n in 'ModernSharedStashSoftCoreV2','ModernSharedStashHardCoreV2') {
    [System.IO.File]::WriteAllText((Join-Path $saves "$n.d2i"), ('s' * 4100))
}
[System.IO.File]::WriteAllText((Join-Path $saves 'Settings.json'), '{ "demo": true }')
foreach ($f in 'loot','endgame') { [System.IO.File]::WriteAllText((Join-Path $saves "$f.fltr"), 'demo') }

$geparkt = @(
    @{n='Grimward';  k=3; l=99; s=0x20; t=210; p='Old heroes'}
    @{n='Emberfall'; k=1; l=99; s=0x20; t=260; p='Old heroes'}
    @{n='Deadeye';   k=0; l=44; s=0x24; t=95;  p='Hardcore run'}
    @{n='Ironmaw';   k=4; l=38; s=0x24; t=110; p='Hardcore run'}
)
foreach ($g in $geparkt) {
    $po = Join-Path $saves "_Projekte\$($g.p)"
    if (-not (Test-Path -LiteralPath $po)) { New-Item -ItemType Directory -Path $po -Force | Out-Null }
    New-DemoSave (Join-Path $po "$($g.n).d2s") $g.k $g.l $g.s $g.t
    foreach ($e in '.ctl','.key','.ma0','.map') { [System.IO.File]::WriteAllText((Join-Path $po "$($g.n)$e"), ('x' * 900)) }
}

# --- Programmkopie ----------------------------------------------------------
# Der Mutex bekommt einen eigenen Namen, sonst laesst sich die Demo nicht
# starten, solange das echte Programm offen ist - und umgekehrt.
$text = [System.IO.File]::ReadAllText($Quelle)
$text = $text.Replace("'D2RCharBackupManager.Einzelinstanz'", "'D2RCharBackupManager.Demo'")
$demoSkript = Join-Path $Ziel 'D2RCharBackupManager.ps1'
[System.IO.File]::WriteAllText($demoSkript, $text, (New-Object System.Text.UTF8Encoding($true)))

foreach ($d in 'ANLEITUNG.md','INSTRUCTIONS.md','LICENSE') {
    $q = Join-Path $Basis $d
    if (Test-Path -LiteralPath $q) { Copy-Item -LiteralPath $q -Destination $Ziel -Force }
}

# --- Konfiguration ----------------------------------------------------------
# Haftungshinweis vorab bestaetigen, sonst steht er beim ersten Start im Bild.
# Die Fassungsnummer aus der Programmdatei lesen, damit sie nicht auseinanderlaeuft.
$fassung = 1
$m = [regex]::Match($text, '\$script:DisclaimerVersion\s*=\s*(\d+)')
if ($m.Success) { $fassung = [int]$m.Groups[1].Value }

@{
    SavePath   = $saves
    BackupPath = $backup
    Language   = $Sprache
    Disclaimer = @{ Version = $fassung; AcceptedAt = (Get-Date).ToString('o'); AppVersion = 'demo' }
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Ziel 'config.json') -Encoding UTF8

# --- Sicherungen anlegen ----------------------------------------------------
# Die Funktionen des Programms benutzen statt die Ordner von Hand zu bauen: so
# entsteht dieselbe Ablage wie im echten Betrieb, samt _INFO.txt und index.json.
$ast = [System.Management.Automation.Language.Parser]::ParseFile($demoSkript, [ref]$null, [ref]$null)
foreach ($a in $ast.FindAll({param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst]}, $false)) {
    if ($a.Left.Extent.Text -match '^\$script:(ExcludedExtensions|DefaultClassNames|AppName|AppVersion|TextsEn)$') {
        Invoke-Expression $a.Extent.Text
    }
}
foreach ($f in $ast.FindAll({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]}, $false)) {
    Invoke-Expression $f.Extent.Text
}
$script:Config = [pscustomobject]@{
    SavePath = $saves; BackupPath = $backup; Language = $Sprache; ClassNames = $script:DefaultClassNames
}
Import-Index

$label = @('Before Ubers','Level 90 reached','Trade backup','Before respec',
           'Ladder start','After Baal run','Good rolls kept','Pre-patch')
$tag   = @('manual','weekly','milestone')
$notiz = @('', 'runes moved to stash', '', 'looks stable', '', '', 'keep this one', '')
$i = 0
foreach ($c in @(Get-Characters)) {
    $null = New-Snapshot -Kind char -CharName $c.Name -Label $label[$i % $label.Count] `
                         -Tags @($tag[$i % $tag.Count]) -Note $notiz[$i % $notiz.Count]
    $i++
}
$null = New-Snapshot -Kind full -Label 'Full folder before patch 2.8' -Tags @('manual','patch')

# --- Starter ----------------------------------------------------------------
$cmd = @"
@echo off
rem Startet die Demo-Fassung. Eigene Spielstaende und Sicherungen liegen in
rem diesem Ordner - der echte Spielstand-Ordner wird nicht angefasst.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Sta -WindowStyle Hidden -File "%~dp0D2RCharBackupManager.ps1"
"@
[System.IO.File]::WriteAllText((Join-Path $Ziel 'Start Demo.cmd'), $cmd, (New-Object System.Text.ASCIIEncoding))

$hinweis = @"
DEMO-UMGEBUNG
=============

Alles in diesem Ordner ist erfunden. Weder die Charaktere noch die Sicherungen
haben etwas mit einem echten Spielstand zu tun, und das Programm hier greift
ausschliesslich auf diesen Ordner zu.

  Start Demo.cmd    startet das Programm gegen diese Demo-Daten
  saves\            die erfundenen Spielstaende, inklusive _Projekte\
  backup\           fertige Sicherungen mit Labels, Tags und Notizen

Gedacht zum Screenshots machen fuers README. Wenn du fertig bist, kann der
ganze Ordner geloescht werden - es haengt nichts daran.

Der Haftungshinweis ist hier vorab bestaetigt, damit er nicht im Bild steht.
"@
[System.IO.File]::WriteAllText((Join-Path $Ziel '_LIESMICH-DEMO.txt'), $hinweis, (New-Object System.Text.UTF8Encoding($true)))

Write-Host ''
Write-Host "  Demo-Umgebung steht: $Ziel"
Write-Host ''
Write-Host "    Sprache            : $Sprache"
Write-Host "    aktive Charaktere  : $(@(Get-Characters).Count)"
Write-Host "    geparkte Charaktere: $(@(Get-ParkedCharacters).Count) in $(@(Get-ProjectNames).Count) Projekten"
Write-Host "    Sicherungen        : $(@($script:Index.snapshots).Count)"
Write-Host ''
Write-Host '  Zum Starten:'
Write-Host "    $(Join-Path $Ziel 'Start Demo.cmd')"
Write-Host ''
