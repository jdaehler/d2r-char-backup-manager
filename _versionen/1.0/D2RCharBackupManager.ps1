#requires -version 5.1
<#
    D2R Char Backup Manager
    Sichert lokale Charaktere von Diablo II: Resurrected und spielt sie zurück.
    Verwaltet werden die Sicherungen — die Charaktere selbst bleiben unberührt,
    bis ausdrücklich wiederhergestellt wird.

    - Snapshots pro Charakter (kompletter Dateisatz) oder vom gesamten Spielstand-Ordner
    - Shared Stash wird immer mitgesichert, beim Wiederherstellen optional
    - Labels, Tags und Notizen pro Snapshot
    - Wiederherstellen unter einem anderen Charakternamen
    - Vor jeder Wiederherstellung automatisch eine Sicherheitskopie

    Start über "Start D2R Char Backup Manager.cmd".
#>

$ErrorActionPreference = 'Stop'

foreach ($asm in 'PresentationFramework','PresentationCore','WindowsBase','System.Windows.Forms','System.Drawing','System.IO.Compression','System.IO.Compression.FileSystem') {
    try { Add-Type -AssemblyName $asm -ErrorAction Stop } catch { }
}

# ---------------------------------------------------------------------------
# Konstanten
# ---------------------------------------------------------------------------

# Der Name sagt bewusst "Backup Manager", nicht "Char Manager": verwaltet werden
# die Sicherungen der Charaktere, nicht die Charaktere selbst.
$script:AppName    = 'D2R Char Backup Manager'
# Versionsnummer: steht im Fenstertitel und in der Statuszeile beim Start.
# Bei Änderungen mitpflegen, die Liste dazu steht im README unter "Versionen".
$script:AppVersion = '1.0'
$script:ScriptPath = $MyInvocation.MyCommand.Path
$script:ScriptDir  = Split-Path -Parent $script:ScriptPath
$script:ConfigPath = Join-Path $script:ScriptDir 'config.json'
$script:RestartRequested = $false

# Dateiendungen, die NICHT zum Charakter-Dateisatz gehören.
# D2R legt selbst zeitgestempelte *.bak an (z.B. "Assassin182056.bak") - die
# haben ohnehin einen anderen Basisnamen und werden durch den exakten
# Namensvergleich schon ausgeschlossen. Hier nur zur Sicherheit.
$script:ExcludedExtensions = @('.bak')

# Klassen-IDs aus dem .d2s-Header. Über config.json erweiterbar, falls weitere
# Klassen dazukommen - unbekannte IDs erscheinen als "Klasse <n> (?)".
$script:DefaultClassNames = [ordered]@{
    '0' = 'Amazone'
    '1' = 'Zauberin'
    '2' = 'Totenbeschwörer'
    '3' = 'Paladin'
    '4' = 'Barbar'
    '5' = 'Druide'
    '6' = 'Assassine'
    '7' = 'Hexenbeschwörer'
}

# ---------------------------------------------------------------------------
# Konfiguration
# ---------------------------------------------------------------------------

# "Saved Games" ist ein bekannter Windows-Ordner und kann umgeleitet sein — auf
# diesem Rechner zeigt z. B. "Dokumente" nach D:\CloudData\... Sich auf
# %USERPROFILE% zu verlassen ginge dann schief. Die Registry kennt den echten
# Pfad: "User Shell Folders" enthält nur abweichende Einträge (mit
# Umgebungsvariablen), "Shell Folders" die aufgelösten.
function Get-SavedGamesRoot {
    $guid = '{4C5C32FF-BB9D-43B0-B5B4-2D72E54EAAA4}'   # FOLDERID_SavedGames
    foreach ($key in 'User Shell Folders', 'Shell Folders') {
        try {
            $pfad = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\$key"
            $wert = (Get-ItemProperty -LiteralPath $pfad -Name $guid -ErrorAction Stop).$guid
            if ($wert) {
                $wert = [Environment]::ExpandEnvironmentVariables($wert)
                if (Test-Path -LiteralPath $wert) { return $wert }
            }
        } catch { }
    }
    Join-Path $env:USERPROFILE 'Saved Games'
}

function Get-SavePathKandidaten {
    $liste = @((Join-Path (Get-SavedGamesRoot) 'Diablo II Resurrected'),
               (Join-Path $env:USERPROFILE 'Saved Games\Diablo II Resurrected'))
    if ($env:OneDrive) { $liste += Join-Path $env:OneDrive 'Saved Games\Diablo II Resurrected' }
    @($liste | Select-Object -Unique)
}

function Get-DefaultSavePath {
    $kandidaten = Get-SavePathKandidaten
    # Bevorzugt der Ordner, in dem wirklich Charaktere liegen.
    foreach ($k in $kandidaten) {
        if ((Test-Path -LiteralPath $k) -and
            @(Get-ChildItem -LiteralPath $k -Filter '*.d2s' -File -ErrorAction SilentlyContinue).Count -gt 0) {
            return $k
        }
    }
    foreach ($k in $kandidaten) { if (Test-Path -LiteralPath $k) { return $k } }
    $kandidaten[0]
}

# Beim allerersten Start die Anzeigesprache von Windows übernehmen: auf einem
# englischen System soll die Oberfläche gleich englisch sein, ohne dass jemand
# erst den Umschalter suchen muss. Sobald config.json existiert, gewinnt immer
# der dort gespeicherte Wert - eine bewusste Wahl wird also nie überstimmt.
function Get-DefaultLanguage {
    try {
        $kultur = [System.Globalization.CultureInfo]::CurrentUICulture
        if (-not $kultur -or -not $kultur.TwoLetterISOLanguageName) {
            $kultur = [System.Globalization.CultureInfo]::InstalledUICulture
        }
        if ($kultur.TwoLetterISOLanguageName -eq 'de') { return 'de' }
    } catch { }
    'en'
}

function New-DefaultConfig {
    [pscustomobject]@{
        SavePath    = Get-DefaultSavePath
        # Standardmäßig ein Unterordner dort, wo das Programm liegt. Damit
        # funktioniert ein ausgepacktes Paket sofort, ohne Nachfrage.
        BackupPath  = Join-Path $script:ScriptDir 'Backups'
        Language    = Get-DefaultLanguage   # 'de' oder 'en', siehe oben
        ClassNames  = $script:DefaultClassNames
        SortChars   = $null   # zuletzt benutzte Sortierung der Charakterliste
        SortSnaps   = $null   # zuletzt benutzte Sortierung der Snapshot-Liste
    }
}

function Import-Config {
    if (Test-Path -LiteralPath $script:ConfigPath) {
        try {
            $raw = Get-Content -LiteralPath $script:ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $cfg = New-DefaultConfig
            # Weitergegebene Konfiguration: zeigt der Pfad ins Leere (anderer
            # Rechner, anderer Benutzername), auf die Standardablage zurückfallen.
            if ($raw.PSObject.Properties['SavePath'] -and $raw.SavePath -and (Test-Path -LiteralPath $raw.SavePath)) {
                $cfg.SavePath = $raw.SavePath
            }
            # Backup-Pfad nur übernehmen, wenn sein Laufwerk existiert. Sonst
            # stammt die Konfiguration von einem anderen Rechner und die
            # Ersteinrichtung soll sich melden, statt beim Sichern zu scheitern.
            if ($raw.PSObject.Properties['BackupPath'] -and $raw.BackupPath) {
                $root = [System.IO.Path]::GetPathRoot($raw.BackupPath)
                if (-not $root -or (Test-Path -LiteralPath $root)) { $cfg.BackupPath = $raw.BackupPath }
            }
            if ($raw.PSObject.Properties['Language'] -and $raw.Language -in @('de','en')) { $cfg.Language = $raw.Language }
            if ($raw.PSObject.Properties['ClassNames'] -and $raw.ClassNames) {
                # Frühere Fassungen schrieben die Klassennamen ohne Umlaute. Die
                # Übersetzungstabelle kennt nur die heutige Schreibweise, deshalb
                # werden alte Einträge beim Laden angeglichen.
                $legacyClass = @{ 'Totenbeschwoerer' = 'Totenbeschwörer'; 'Hexenbeschwoerer' = 'Hexenbeschwörer' }
                foreach ($p in $raw.ClassNames.PSObject.Properties) {
                    $value = [string]$p.Value
                    if ($legacyClass.ContainsKey($value)) { $value = $legacyClass[$value] }
                    $cfg.ClassNames[$p.Name] = $value
                }
            }
            foreach ($k in 'SortChars','SortSnaps') {
                if ($raw.PSObject.Properties[$k] -and $raw.$k) { $cfg.$k = $raw.$k }
            }
            return $cfg
        } catch {
            return New-DefaultConfig
        }
    }
    New-DefaultConfig
}

function Export-Config {
    $script:Config | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $script:ConfigPath -Encoding UTF8
}

function Get-ClassName([int]$Id) {
    $key = [string]$Id
    if ($script:Config.ClassNames.Contains($key)) { return (T $script:Config.ClassNames[$key]) }
    # Kurz halten, sonst wird der Text in der Klassenspalte abgeschnitten.
    if ($script:Config.Language -eq 'en') { "Class $Id (?)" } else { "Klasse $Id (?)" }
}

# ---------------------------------------------------------------------------
# .d2s Header lesen
# ---------------------------------------------------------------------------
# Layout (empirisch gegen die vorhandenen Saves verifiziert):
#   0x00 Magic 0xAA55AA55 | 0x04 Version | 0x08 Dateigröße | 0x0C Prüfsumme
#   0x10 aktive Waffe
#   Ab Version 100 (D2R) ist das 16 Byte große Namensfeld entfernt, alle
#   folgenden Felder verschieben sich dadurch um 16 Bytes nach vorne.
#   base = 0x14 (ab v100) bzw. 0x24 (bis v99):
#     base+0  Status-Bits (Bit2 = Hardcore, Bit3 = gestorben, Bit5 = Erweiterung)
#     base+1  Fortschritt
#     base+4  Klassen-ID
#     base+7  Level
#     base+12 zuletzt gespielt (Unix-Zeit)
# Der Charaktername steht in D2R NICHT in der Datei - er ergibt sich
# ausschließlich aus dem Dateinamen. Deshalb ist Umbenennen gefahrlos.

function Get-D2SInfo {
    param([string]$Path)

    $info = [pscustomobject]@{
        Version    = 0
        ClassId    = -1
        ClassName  = ''
        Level      = 0
        Hardcore   = $false
        Dead       = $false
        Expansion  = $false
        LastPlayed = $null
        Valid      = $false
    }

    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        if ($bytes.Length -lt 64) { return $info }
        # 0xAA55AA55 bewusst dezimal: Windows PowerShell 5.1 liest das Hex-Literal
        # als negativen Int32, wodurch der Vergleich nie zutreffen würde.
        if ([BitConverter]::ToUInt32($bytes, 0) -ne 2857740885) { return $info }

        $info.Version = [int][BitConverter]::ToUInt32($bytes, 4)
        $base = if ($info.Version -ge 100) { 0x14 } else { 0x24 }

        $status         = $bytes[$base]
        $info.Hardcore  = (($status -band 0x04) -ne 0)
        $info.Dead      = (($status -band 0x08) -ne 0)
        $info.Expansion = (($status -band 0x20) -ne 0)
        $info.ClassId   = [int]$bytes[$base + 4]
        $info.ClassName = Get-ClassName $info.ClassId
        $info.Level     = [int]$bytes[$base + 7]

        $stamp = [BitConverter]::ToUInt32($bytes, $base + 12)
        if ($stamp -gt 0 -and $stamp -ne 0xFFFFFFFF) {
            $info.LastPlayed = [DateTimeOffset]::FromUnixTimeSeconds([int64]$stamp).LocalDateTime
        }
        $info.Valid = $true
    } catch { }

    $info
}

# ---------------------------------------------------------------------------
# Spielstand-Ordner einlesen
# ---------------------------------------------------------------------------

function Get-StashFiles {
    if (-not (Test-Path -LiteralPath $script:Config.SavePath)) { return @() }
    @(Get-ChildItem -LiteralPath $script:Config.SavePath -File -Filter '*.d2i' -ErrorAction SilentlyContinue)
}

function Get-CharacterFiles {
    param([string]$CharName)
    if (-not (Test-Path -LiteralPath $script:Config.SavePath)) { return @() }
    @(Get-ChildItem -LiteralPath $script:Config.SavePath -File -ErrorAction SilentlyContinue | Where-Object {
        [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -eq $CharName -and
        $script:ExcludedExtensions -notcontains $_.Extension.ToLowerInvariant()
    })
}

function Get-Characters {
    if (-not (Test-Path -LiteralPath $script:Config.SavePath)) { return @() }

    $result = @()
    $saves  = @(Get-ChildItem -LiteralPath $script:Config.SavePath -File -Filter '*.d2s' -ErrorAction SilentlyContinue)

    foreach ($save in $saves) {
        $name  = $save.BaseName
        $info  = Get-D2SInfo $save.FullName
        $files = Get-CharacterFiles $name
        $snaps = @($script:Index.snapshots | Where-Object { $_.kind -eq 'char' -and $_.char -eq $name })

        $result += [pscustomobject]@{
            Name          = $name
            ClassName     = if ($info.Valid) { $info.ClassName } else { '?' }
            Level         = if ($info.Valid) { $info.Level } else { 0 }
            Mode          = if (-not $info.Valid) { '?' } elseif ($info.Hardcore) { 'Hardcore' } else { 'Softcore' }
            LastPlayed    = $info.LastPlayed
            # Fester Typ zum Sortieren - $null und DateTime gemischt lässt WPF stolpern.
            LastPlayedSort = if ($info.LastPlayed) { $info.LastPlayed } else { [datetime]::MinValue }
            LastPlayedStr = if ($info.LastPlayed) { $info.LastPlayed.ToString('dd.MM.yyyy HH:mm') } else { '' }
            FileCount     = $files.Count
            SnapCount     = $snaps.Count
            Version       = $info.Version
            Hardcore      = $info.Hardcore
        }
    }

    @($result | Sort-Object Name)
}

# ---------------------------------------------------------------------------
# Snapshot-Index
# ---------------------------------------------------------------------------

function Get-IndexPath { Join-Path $script:Config.BackupPath 'index.json' }
function Get-SnapshotDir { Join-Path $script:Config.BackupPath 'snapshots' }

# Hinweis: Die Snapshot-Liste ist bewusst ein gewöhnliches Array.
# Windows PowerShell 5.1 wirft bei @(...) um eine generische List[object]
# eine ArgumentException ("Die Argumenttypen stimmen nicht überein").
function Import-Index {
    $script:Index = [pscustomobject]@{ version = 1; snapshots = @() }
    if (-not $script:Config.BackupPath) { return }

    $path = Get-IndexPath
    if (-not (Test-Path -LiteralPath $path)) { return }

    try {
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($raw.PSObject.Properties['snapshots'] -and $raw.snapshots) {
            $loaded = @()
            foreach ($s in @($raw.snapshots)) {
                if ($s.PSObject.Properties['tags']) { $s.tags = @($s.tags) } else { $s | Add-Member tags @() -Force }
                $loaded += $s
            }
            $script:Index.snapshots = $loaded
        }
    } catch {
        [void][System.Windows.MessageBox]::Show(
            "Die Datei index.json konnte nicht gelesen werden:`n`n$($_.Exception.Message)`n`nEs wird mit einem leeren Index weitergearbeitet. Die vorhandene Datei bleibt unverändert, bis ein neuer Snapshot angelegt wird.",
            $script:AppName, 'OK', 'Warning')
    }
}

function Export-Index {
    if (-not $script:Config.BackupPath) { return }
    if (-not (Test-Path -LiteralPath $script:Config.BackupPath)) {
        New-Item -ItemType Directory -Path $script:Config.BackupPath -Force | Out-Null
    }
    [pscustomobject]@{
        version   = 1
        snapshots = @($script:Index.snapshots)
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Get-IndexPath) -Encoding UTF8
}

# ---------------------------------------------------------------------------
# Ablage der Sicherungen
# ---------------------------------------------------------------------------
# Bewusst Ordner mit unkomprimierten Dateien statt ZIP-Archive: man soll im
# Explorer auf einen Blick sehen, was wann von wem gesichert wurde — und im
# Notfall ohne dieses Programm zurückkopieren können.
#
#   <Backup-Ordner>\
#     _LIESMICH.txt
#     index.json
#     Charaktere\<Name>\<Datum_Zeit> Lvl<n> <Klasse>\
#         _INFO.txt, <Spielstanddateien>, SharedStash\<*.d2i>
#     Kompletter Ordner\<Datum_Zeit>\
#         _INFO.txt, <alle Dateien>
#
# "Charaktere", "Kompletter Ordner" und "SharedStash" sind feste Ordnernamen und
# werden NICHT übersetzt — sonst entstünden beim Sprachwechsel zwei Bäume.

function Get-CharsDir { Join-Path $script:Config.BackupPath 'Charaktere' }
function Get-FullDir  { Join-Path $script:Config.BackupPath 'Kompletter Ordner' }

function Get-SnapshotOrdner {
    param([object]$Record)
    if ($Record.PSObject.Properties['pfad'] -and $Record.pfad) {
        return (Join-Path $script:Config.BackupPath $Record.pfad)
    }
    $null   # alter Datensatz, liegt noch als ZIP vor
}

function ConvertTo-SichererName {
    param([string]$Text)
    $ungueltig = [System.IO.Path]::GetInvalidFileNameChars()
    (-join ($Text.ToCharArray() | ForEach-Object { if ($ungueltig -contains $_) { '_' } else { $_ } })).Trim()
}

function New-SnapshotOrdner {
    param([string]$Basis, [string]$Name)
    $ziel = Join-Path $Basis $Name
    $n = 2
    while (Test-Path -LiteralPath $ziel) { $ziel = Join-Path $Basis ("$Name ($n)"); $n++ }
    New-Item -ItemType Directory -Path $ziel -Force | Out-Null
    $ziel
}

function Write-SnapshotInfo {
    param([object]$Record)
    $ordner = Get-SnapshotOrdner $Record
    if (-not $ordner -or -not (Test-Path -LiteralPath $ordner)) { return }

    $z = @("$script:AppName $script:AppVersion", '')
    function Zeile($k, $v) { '{0,-16}{1}' -f ((T $k) + ':'), $v }

    if ($Record.kind -eq 'char') {
        $z += Zeile 'Charakter' $Record.char
        $z += Zeile 'Klasse'    $Record.className
        $z += Zeile 'Level'     $Record.level
        $z += Zeile 'Modus'     $(if ($Record.hardcore) { 'Hardcore' } else { 'Softcore' })
    } else {
        $z += Zeile 'Typ' (T 'Kompletter Ordner')
    }
    $z += Zeile 'Gesichert am' (Format-Timestamp $Record.created)
    if ($Record.label) { $z += Zeile 'Label' $Record.label }
    if (@($Record.tags).Count -gt 0) { $z += Zeile 'Tags' (@($Record.tags) -join ', ') }
    if ($Record.note)  { $z += Zeile 'Notiz' (($Record.note -split '\r?\n') -join ' / ') }
    $z += Zeile 'Quelle' $script:Config.SavePath
    if ($Record.d2rRunning) { $z += Zeile 'Hinweis' (T 'D2R lief beim Sichern - Stand ggf. nicht taufrisch') }

    $z += ''
    $z += (T 'VON HAND WIEDERHERSTELLEN')
    $z += '-' * 60
    $z += (T '1. D2R beenden.')
    if ($Record.kind -eq 'char') {
        $z += (T '2. Die Dateien aus diesem Ordner (ohne _INFO.txt und ohne den')
        $z += (T '   Unterordner SharedStash) in den Spielstand-Ordner kopieren')
        $z += (T '   und vorhandene ersetzen.')
        $z += (T '3. Anderer Name gewünscht? Alle Dateien gleich umbenennen, etwa')
        $z += (T '   Held.d2s -> Neuer.d2s, Held.ctl -> Neuer.ctl und so weiter.')
        $z += (T '   Die Endungen bleiben. Der Name steht nur im Dateinamen,')
        $z += (T '   nicht in der Datei selbst.')
        $z += (T '4. SharedStash nur zurückkopieren, wenn auch der Truhen-Inhalt')
        $z += (T '   von damals gewünscht ist - der gilt für alle Charaktere.')
    } else {
        $z += (T '2. Alle Dateien aus diesem Ordner (ohne _INFO.txt) in den')
        $z += (T '   Spielstand-Ordner kopieren und vorhandene ersetzen.')
        $z += (T '   Achtung: das betrifft sämtliche Charaktere.')
    }
    [System.IO.File]::WriteAllLines((Join-Path $ordner '_INFO.txt'), $z, (New-Object System.Text.UTF8Encoding($true)))
}

function Write-BackupLiesmich {
    if (-not $script:Config.BackupPath -or -not (Test-Path -LiteralPath $script:Config.BackupPath)) { return }
    $z = @(
        "$script:AppName $script:AppVersion",
        '',
        (T 'In diesem Ordner liegen die Sicherungen deiner D2R-Charaktere.'),
        '',
        'Charaktere\<Name>\<Datum_Zeit> Lvl<n> <Klasse>\',
        (T '    Eine Sicherung eines Charakters. Darin die Spielstanddateien,'),
        (T '    im Unterordner SharedStash die gemeinsame Truhe, und _INFO.txt'),
        (T '    mit allen Angaben und einer Anleitung zum Zurückkopieren.'),
        '',
        'Kompletter Ordner\<Datum_Zeit>\',
        (T '    Eine Sicherung des kompletten Spielstand-Ordners.'),
        '',
        'index.json',
        (T '    Labels, Tags und Notizen für das Programm. Geht diese Datei'),
        (T '    verloren, sind die Sicherungen selbst weiterhin benutzbar —'),
        (T '    nur die Beschriftungen fehlen dann.'),
        '',
        (T 'Die Dateien liegen unkomprimiert. Du brauchst dieses Programm nicht,'),
        (T 'um an sie heranzukommen: D2R beenden, Dateien in den Spielstand-Ordner'),
        (T 'kopieren, fertig. Siehe _INFO.txt in der jeweiligen Sicherung.')
    )
    [System.IO.File]::WriteAllLines((Join-Path $script:Config.BackupPath '_LIESMICH.txt'), $z, (New-Object System.Text.UTF8Encoding($true)))
}

function Get-EntriesHash {
    param([hashtable]$Entries)
    # Fingerabdruck über alle Dateien eines Snapshots, damit inhaltlich
    # identische Sicherungen als solche erkannt werden können.
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $sb = New-Object System.Text.StringBuilder
        foreach ($key in ($Entries.Keys | Sort-Object)) {
            $fileHash = [BitConverter]::ToString($sha.ComputeHash([System.IO.File]::ReadAllBytes($Entries[$key]))).Replace('-','')
            [void]$sb.Append($key).Append(':').Append($fileHash).Append(';')
        }
        [BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($sb.ToString()))).Replace('-','')
    } finally { $sha.Dispose() }
}

function Expand-SnapshotEntry {
    param(
        [System.IO.Compression.ZipArchive]$Archive,
        [System.IO.Compression.ZipArchiveEntry]$Entry,
        [string]$TargetPath
    )
    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($Entry, $TargetPath, $true)
}

# ---------------------------------------------------------------------------
# Snapshot anlegen
# ---------------------------------------------------------------------------

function New-Snapshot {
    param(
        [ValidateSet('char','full')][string]$Kind,
        [string]$CharName = '',
        [string]$Label    = '',
        [string[]]$Tags   = @(),
        [string]$Note     = '',
        [switch]$Automatic,
        [switch]$SkipIfUnchanged   # gibt $null zurück, wenn es den Stand schon gibt
    )

    if (-not $script:Config.BackupPath) { throw 'Es ist kein Backup-Ordner konfiguriert.' }
    if (-not (Test-Path -LiteralPath $script:Config.BackupPath)) {
        New-Item -ItemType Directory -Path $script:Config.BackupPath -Force | Out-Null
    }

    $id = '{0}-{1:x4}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), (Get-Random -Maximum 65535)

    $entries   = @{}
    $fileNames = @()
    $stash     = Get-StashFiles

    $className = ''; $level = 0; $hardcore = $false

    if ($Kind -eq 'char') {
        if (-not $CharName) { throw 'Kein Charakter angegeben.' }
        $charFiles = Get-CharacterFiles $CharName
        if ($charFiles.Count -eq 0) { throw "Zu '$CharName' wurden keine Dateien gefunden." }

        foreach ($f in $charFiles) {
            $entries["char/$($f.Name)"] = $f.FullName
            $fileNames += $f.Name
        }
        # Shared Stash immer mitsichern - beim Wiederherstellen ist er optional.
        foreach ($f in $stash) {
            $entries["stash/$($f.Name)"] = $f.FullName
            $fileNames += $f.Name
        }

        $d2s = Join-Path $script:Config.SavePath "$CharName.d2s"
        if (Test-Path -LiteralPath $d2s) {
            $info = Get-D2SInfo $d2s
            if ($info.Valid) { $className = $info.ClassName; $level = $info.Level; $hardcore = $info.Hardcore }
        }
    } else {
        $all = @(Get-ChildItem -LiteralPath $script:Config.SavePath -File -ErrorAction SilentlyContinue |
                 Where-Object { $script:ExcludedExtensions -notcontains $_.Extension.ToLowerInvariant() })
        if ($all.Count -eq 0) { throw 'Im Spielstand-Ordner wurden keine Dateien gefunden.' }
        foreach ($f in $all) {
            $entries["full/$($f.Name)"] = $f.FullName
            $fileNames += $f.Name
        }
    }

    $contentHash = Get-EntriesHash $entries

    # Für Sammelsicherungen: unveränderte Charaktere nicht erneut ablegen.
    # Der Fingerabdruck steht fest, bevor überhaupt eine Datei geschrieben wird.
    if ($SkipIfUnchanged) {
        $twin = @($script:Index.snapshots | Where-Object {
            $_.kind -eq $Kind -and $_.char -eq $CharName -and
            $_.PSObject.Properties['contentHash'] -and $_.contentHash -eq $contentHash
        })
        if ($twin.Count -gt 0) { return $null }
    }

    # Zielordner: sprechender Name, damit man ihn im Explorer zuordnen kann.
    $stempel = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    if ($Kind -eq 'char') {
        $basis = Join-Path (Get-CharsDir) (ConvertTo-SichererName $CharName)
        $name  = ConvertTo-SichererName ('{0} Lvl{1} {2}' -f $stempel, $level, $className)
    } else {
        $basis = Get-FullDir
        $name  = $stempel
    }
    $ordner = New-SnapshotOrdner -Basis $basis -Name $name

    foreach ($key in $entries.Keys) {
        $teile = $key -split '/', 2
        $unter = if ($teile[0] -eq 'stash') { Join-Path $ordner 'SharedStash' } else { $ordner }
        if (-not (Test-Path -LiteralPath $unter)) { New-Item -ItemType Directory -Path $unter -Force | Out-Null }
        Copy-Item -LiteralPath $entries[$key] -Destination (Join-Path $unter $teile[1]) -Force
    }

    $basisPfad = $script:Config.BackupPath.TrimEnd('\')
    $relPfad   = $ordner.Substring($basisPfad.Length + 1)
    $groesse   = (Get-ChildItem -LiteralPath $ordner -Recurse -File | Measure-Object Length -Sum).Sum

    # Sichern bei laufendem Spiel ist ungefährlich, der Stand kann aber älter
    # sein als das aktuelle Spielgeschehen. Das wird vermerkt statt zu blockieren.
    $gameRunning = Test-D2RRunning
    if ($gameRunning -and @($Tags) -notcontains 'spiel-lief') { $Tags = @($Tags) + 'spiel-lief' }

    $record = [pscustomobject]@{
        id            = $id
        kind          = $Kind
        automatic     = [bool]$Automatic
        char          = $CharName
        label         = $Label
        tags          = @($Tags)
        note          = $Note
        created       = (Get-Date).ToString('o')
        pfad          = $relPfad
        sizeBytes     = [long]$groesse
        fileCount     = $fileNames.Count
        includesStash = ($Kind -eq 'char' -and $stash.Count -gt 0)
        d2rRunning    = $gameRunning
        contentHash   = $contentHash
        className     = $className
        level         = $level
        hardcore      = $hardcore
    }

    $script:Index.snapshots += $record
    Export-Index
    Write-SnapshotInfo $record
    Write-BackupLiesmich
    $record
}

# ---------------------------------------------------------------------------
# Snapshot wiederherstellen
# ---------------------------------------------------------------------------

function Test-D2RName {
    param([string]$Name)
    # D2R: 2-15 Zeichen, Beginn mit Buchstabe, danach Buchstaben/Ziffern sowie
    # maximal ein "_" oder "-". Wir prüfen bewusst etwas großzügiger und
    # warnen nur, statt hart zu blockieren.
    if ([string]::IsNullOrWhiteSpace($Name)) { return (T 'Der Name darf nicht leer sein.') }
    if ($Name.Length -lt 2 -or $Name.Length -gt 15) { return (T 'Der Name muss zwischen 2 und 15 Zeichen lang sein.') }
    if ($Name -notmatch '^[A-Za-z][A-Za-z0-9_-]*$') { return (T 'Erlaubt sind Buchstaben, Ziffern, "_" und "-"; das erste Zeichen muss ein Buchstabe sein.') }
    if (@($Name.ToCharArray() | Where-Object { $_ -eq '_' -or $_ -eq '-' }).Count -gt 1) { return (T 'D2R erlaubt höchstens ein "_" oder "-" im Namen.') }
    ''
}

function Test-D2RRunning {
    [bool](Get-Process -Name 'D2R' -ErrorAction SilentlyContinue)
}

# Weicht der gesicherte Shared Stash vom aktuellen ab? Damit lässt sich im
# Wiederherstellen-Dialog sagen, ob das Häkchen überhaupt einen Unterschied
# macht — der Stash gilt für alle Charaktere, deshalb ist das die heikelste
# Entscheidung in diesem Dialog.
#   $true  = gleich, $false = abweichend, $null = nicht feststellbar
function Test-StashUnveraendert {
    param([object]$Record)
    $ordner = Get-SnapshotOrdner $Record
    if (-not $ordner) { return $null }
    $stashOrdner = Join-Path $ordner 'SharedStash'
    if (-not (Test-Path -LiteralPath $stashOrdner)) { return $null }

    $gesichert = @(Get-ChildItem -LiteralPath $stashOrdner -File)
    $aktuell   = @(Get-StashFiles)
    if ($gesichert.Count -ne $aktuell.Count) { return $false }

    foreach ($g in $gesichert) {
        $a = @($aktuell | Where-Object { $_.Name -eq $g.Name })
        if ($a.Count -eq 0 -or $a[0].Length -ne $g.Length) { return $false }
        if ((Get-FileHash -LiteralPath $a[0].FullName -Algorithm SHA256).Hash -ne
            (Get-FileHash -LiteralPath $g.FullName    -Algorithm SHA256).Hash) { return $false }
    }
    $true
}

function Restore-Snapshot {
    param(
        [object]$Snapshot,
        [string]$TargetName = '',
        [switch]$RestoreStash,
        [switch]$SkipSafetyBackup
    )

    $ordner  = Get-SnapshotOrdner $Snapshot
    $zipPath = if ($Snapshot.PSObject.Properties['zip'] -and $Snapshot.zip) {
        Join-Path (Get-SnapshotDir) $Snapshot.zip
    } else { '' }

    $ausOrdner = $ordner -and (Test-Path -LiteralPath $ordner)
    $ausZip    = -not $ausOrdner -and $zipPath -and (Test-Path -LiteralPath $zipPath)
    if (-not $ausOrdner -and -not $ausZip) {
        throw "Die Sicherung fehlt: $(if ($ordner) { $ordner } else { $zipPath })"
    }
    if (-not (Test-Path -LiteralPath $script:Config.SavePath)) { throw "Der Spielstand-Ordner existiert nicht: $($script:Config.SavePath)" }

    # Sicherheitskopie des aktuellen Zustands, bevor irgendetwas überschrieben wird.
    if (-not $SkipSafetyBackup) {
        if ($Snapshot.kind -eq 'char') {
            $existing = if ($TargetName) { Get-CharacterFiles $TargetName } else { Get-CharacterFiles $Snapshot.char }
            if ($existing.Count -gt 0) {
                New-Snapshot -Kind char -CharName $(if ($TargetName) { $TargetName } else { $Snapshot.char }) `
                             -Label (T 'Automatisch vor Wiederherstellung') -Tags @('auto') -Automatic | Out-Null
            }
        } else {
            New-Snapshot -Kind full -Label (T 'Automatisch vor Wiederherstellung') -Tags @('auto') -Automatic | Out-Null
        }
    }

    $restored = @()

    if ($ausOrdner) {
        # Dateien direkt im Snapshot-Ordner sind der Charakter bzw. der
        # kompletten Ordner; SharedStash liegt im Unterordner und ist optional.
        foreach ($f in (Get-ChildItem -LiteralPath $ordner -File)) {
            if ($f.Name -eq '_INFO.txt') { continue }
            $ziel = $f.Name
            if ($Snapshot.kind -eq 'char' -and $TargetName) {
                # Der Name steckt nur im Dateinamen - Endung bleibt, Basisname wird ersetzt.
                $ziel = $TargetName + $f.Extension
            }
            Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $script:Config.SavePath $ziel) -Force
            $restored += $ziel
        }
        if ($RestoreStash) {
            $stashOrdner = Join-Path $ordner 'SharedStash'
            if (Test-Path -LiteralPath $stashOrdner) {
                foreach ($f in (Get-ChildItem -LiteralPath $stashOrdner -File)) {
                    Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $script:Config.SavePath $f.Name) -Force
                    $restored += $f.Name
                }
            }
        }
        return @($restored)
    }

    # Rückfalltür: Datensatz aus der Zeit vor der Ordner-Ablage.
    $stream = [System.IO.File]::Open($zipPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)
    try {
        $archive = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Read)
        try {
            foreach ($entry in $archive.Entries) {
                $section = ($entry.FullName -split '/')[0]
                $file    = $entry.Name
                if (-not $file) { continue }

                switch ($section) {
                    'char' {
                        $target = $file
                        if ($TargetName) {
                            # Der Name steckt nur im Dateinamen - Endung bleibt, Basisname wird ersetzt.
                            $target = $TargetName + [System.IO.Path]::GetExtension($file)
                        }
                        $dest = Join-Path $script:Config.SavePath $target
                        Expand-SnapshotEntry -Archive $archive -Entry $entry -TargetPath $dest
                        $restored += $target
                    }
                    'stash' {
                        if ($RestoreStash) {
                            $dest = Join-Path $script:Config.SavePath $file
                            Expand-SnapshotEntry -Archive $archive -Entry $entry -TargetPath $dest
                            $restored += $file
                        }
                    }
                    'full' {
                        $dest = Join-Path $script:Config.SavePath $file
                        Expand-SnapshotEntry -Archive $archive -Entry $entry -TargetPath $dest
                        $restored += $file
                    }
                }
            }
        } finally { $archive.Dispose() }
    } finally { $stream.Dispose() }

    @($restored)
}

function Remove-Snapshot {
    param([object]$Snapshot)

    $ordner = Get-SnapshotOrdner $Snapshot
    if ($ordner -and (Test-Path -LiteralPath $ordner)) {
        Remove-Item -LiteralPath $ordner -Recurse -Force
        # War es die letzte Sicherung dieses Charakters, bleibt sonst ein
        # leerer Ordner stehen.
        $eltern = Split-Path -Parent $ordner
        if ((Test-Path -LiteralPath $eltern) -and
            @(Get-ChildItem -LiteralPath $eltern -Force).Count -eq 0 -and
            $eltern -ne (Get-CharsDir) -and $eltern -ne (Get-FullDir)) {
            Remove-Item -LiteralPath $eltern -Force
        }
    } elseif ($Snapshot.PSObject.Properties['zip'] -and $Snapshot.zip) {
        $zipPath = Join-Path (Get-SnapshotDir) $Snapshot.zip
        if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    }

    $script:Index.snapshots = @($script:Index.snapshots | Where-Object { $_.id -ne $Snapshot.id })
    Export-Index
}

# ---------------------------------------------------------------------------
# XAML
# ---------------------------------------------------------------------------

$MainXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="D2R Char Backup Manager" Height="800" Width="1380"
        WindowStartupLocation="CenterScreen" MinHeight="520" MinWidth="900">

  <Window.Resources>
    <!-- Eigene Vorlage statt der flachen ToolBar-Optik: mit Rahmen, Fuellfarbe
         und sichtbarer Reaktion auf Maus und Klick sieht man, dass hier eine
         Aktion ausgeloest wird. -->
    <Style x:Key="ButtonBase" TargetType="Button">
      <Setter Property="Padding" Value="14,6"/>
      <Setter Property="Margin"  Value="0,0,6,0"/>
      <Setter Property="MinWidth" Value="86"/>
      <Setter Property="Cursor"  Value="Hand"/>
      <Setter Property="SnapsToDevicePixels" Value="True"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" CornerRadius="3" Padding="{TemplateBinding Padding}"
                    Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.85"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.65"/>
                <Setter TargetName="Bd" Property="Margin" Value="0,1,0,-1"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.45"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Auswahl in den Listen deutlich sichtbar halten.
         WPF färbt eine Auswahl hellgrau, sobald das Gitter den Tastaturfokus
         verliert - und das passiert bei jedem Klick auf einen Knopf. Dadurch
         sieht man im entscheidenden Moment kaum noch, was markiert ist.
         Die Trigger hängen an IsSelected, nicht am Fokus, also bleibt die
         Farbe gleich. Beide Ebenen nötig: die Zelle malt über die Zeile. -->
    <Style x:Key="AuswahlZeile" TargetType="DataGridRow">
      <Style.Triggers>
        <Trigger Property="IsSelected" Value="True">
          <Setter Property="Background" Value="#0E639C"/>
          <Setter Property="Foreground" Value="White"/>
        </Trigger>
        <MultiTrigger>
          <MultiTrigger.Conditions>
            <Condition Property="IsMouseOver" Value="True"/>
            <Condition Property="IsSelected"  Value="False"/>
          </MultiTrigger.Conditions>
          <Setter Property="Background" Value="#E8F1F8"/>
        </MultiTrigger>
      </Style.Triggers>
    </Style>

    <!-- Die Zelle malt über die Zeile, deshalb muss sie dieselbe Farbe führen.
         Eigene Vorlage, weil die Windows-Vorlage bei fehlendem Tastaturfokus
         auf ein blasses Grau umschaltet - genau der Fall nach einem Knopfdruck. -->
    <Style x:Key="AuswahlZelle" TargetType="DataGridCell">
      <Setter Property="Padding" Value="6,3"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="DataGridCell">
            <Border Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
              <ContentPresenter VerticalAlignment="Center"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="IsSelected" Value="True">
          <Setter Property="Background" Value="#0E639C"/>
          <Setter Property="Foreground" Value="White"/>
        </Trigger>
      </Style.Triggers>
    </Style>

    <Style x:Key="AccentButton" TargetType="Button" BasedOn="{StaticResource ButtonBase}">
      <Setter Property="Background"  Value="#0E639C"/>
      <Setter Property="BorderBrush" Value="#0B4F7D"/>
      <Setter Property="Foreground"  Value="White"/>
      <Setter Property="FontWeight"  Value="SemiBold"/>
    </Style>

    <Style x:Key="NormalButton" TargetType="Button" BasedOn="{StaticResource ButtonBase}">
      <Setter Property="Background"  Value="#FFFFFF"/>
      <Setter Property="BorderBrush" Value="#ADADAD"/>
      <Setter Property="Foreground"  Value="#1A1A1A"/>
    </Style>

    <Style x:Key="DangerButton" TargetType="Button" BasedOn="{StaticResource ButtonBase}">
      <Setter Property="Background"  Value="#FDECEA"/>
      <Setter Property="BorderBrush" Value="#C42B1C"/>
      <Setter Property="Foreground"  Value="#8B1F14"/>
    </Style>

    <!-- Nur-Symbol-Knöpfe: sparen Platz, die Erklärung steht im ToolTip.
         "Segoe MDL2 Assets" gehört zu Windows 10 und 11, ist also auch beim
         Empfänger da. -->
    <Style x:Key="IconButton" TargetType="Button" BasedOn="{StaticResource ButtonBase}">
      <Setter Property="Background"  Value="#FFFFFF"/>
      <Setter Property="BorderBrush" Value="#ADADAD"/>
      <Setter Property="Foreground"  Value="#1A1A1A"/>
      <Setter Property="FontFamily"  Value="Segoe MDL2 Assets"/>
      <Setter Property="FontSize"    Value="16"/>
      <Setter Property="MinWidth"    Value="44"/>
      <Setter Property="Padding"     Value="8,5"/>
    </Style>

    <Style x:Key="QuietButton" TargetType="Button" BasedOn="{StaticResource ButtonBase}">
      <Setter Property="Background"  Value="#F0F0F0"/>
      <Setter Property="BorderBrush" Value="#C6C6C6"/>
      <Setter Property="Foreground"  Value="#333333"/>
      <Setter Property="MinWidth"    Value="72"/>
    </Style>
  </Window.Resources>

  <DockPanel>

    <!-- Oben steht nur noch, was das Programm als Ganzes betrifft. Die Aktionen
         für Charaktere und Snapshots sitzen jeweils direkt über ihrer Liste. -->
    <Border DockPanel.Dock="Top" Background="#F3F3F3" BorderBrush="#D6D6D6" BorderThickness="0,0,0,1" Padding="12,7">
      <DockPanel LastChildFill="False">
        <!-- Kopfzeile statt einer Gruppe um drei Knöpfe: sonst schwebt ein
             Rahmen in einer fast leeren Leiste. Links steht, was das Programm
             ist, rechts die Knöpfe, die nichts an den Daten ändern. -->
        <StackPanel DockPanel.Dock="Left" Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock x:Name="TxtAppName" FontSize="14" FontWeight="SemiBold" Foreground="#1A1A1A" VerticalAlignment="Center"/>
          <TextBlock x:Name="TxtAppClaim" FontSize="11" Foreground="#6A6A6A" Margin="12,0,0,0" VerticalAlignment="Center"/>
        </StackPanel>
        <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
          <Button x:Name="BtnLang"     Style="{StaticResource QuietButton}" ToolTip="Auf Englisch umschalten">EN</Button>
          <Button x:Name="BtnSettings" Style="{StaticResource QuietButton}">Einstellungen</Button>
          <Button x:Name="BtnExit"     Style="{StaticResource QuietButton}" ToolTip="Programm beenden">Beenden</Button>
        </StackPanel>
      </DockPanel>
    </Border>

    <StatusBar DockPanel.Dock="Bottom">
      <StatusBarItem><TextBlock x:Name="TxtStatus" Text="Bereit."/></StatusBarItem>
      <StatusBarItem HorizontalAlignment="Right"><TextBlock x:Name="TxtWarn" Foreground="#B00020" FontWeight="Bold"/></StatusBarItem>
    </StatusBar>

    <Grid Margin="8">
      <Grid.ColumnDefinitions>
        <!-- 570: die beiden Gruppen darüber brauchen gemessene 427 + 124 px
             plus Abstand. Schmaler, und die Knöpfe rutschen in eine zweite Zeile. -->
        <ColumnDefinition Width="570" MinWidth="300"/>
        <ColumnDefinition Width="6"/>
        <ColumnDefinition Width="*" MinWidth="420"/>
      </Grid.ColumnDefinitions>

      <Grid Grid.Column="0">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <!-- Links löst genau EIN Knopf etwas aus: "Markierte sichern". Alles
             andere markiert nur, öffnet nur oder liest nur neu. Die Sicherung
             des ganzen Ordners ist eine andere Sache und steht deshalb in einer
             eigenen Gruppe daneben. -->
        <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,6">
          <GroupBox Header="Charaktere sichern" Padding="8,4,8,6" Margin="0,0,10,0">
            <WrapPanel Orientation="Horizontal">
              <!-- Die einzige Aktion steht ganz links und ist die einzige mit Text. -->
              <Button x:Name="BtnSnapChar" Style="{StaticResource AccentButton}" Margin="0,0,10,4" MinWidth="170"
                      ToolTip="Sichert die markierten Charaktere samt Shared Stash. Mehrere mit Strg-Klick oder Umschalt-Klick markieren.">Markierte sichern</Button>
              <Button x:Name="BtnSelectAll"   Style="{StaticResource IconButton}" Content="&#xE8B3;" Margin="0,0,6,4"
                      ToolTip="Alle Charaktere markieren (Strg+A)"/>
              <Button x:Name="BtnDeselectAll" Style="{StaticResource IconButton}" Content="&#xE8E6;" Margin="0,0,6,4"
                      ToolTip="Markierung aufheben"/>
              <Border Width="1" Background="#D0D0D0" Margin="4,2,10,6"/>
              <Button x:Name="BtnOpenSave" Style="{StaticResource IconButton}" Content="&#xE838;" Margin="0,0,6,4"
                      ToolTip="Spielstand-Ordner im Explorer anzeigen"/>
              <Button x:Name="BtnRefresh"  Style="{StaticResource IconButton}" Content="&#xE72C;" Margin="0,0,0,4"
                      ToolTip="Listen neu einlesen"/>
            </WrapPanel>
          </GroupBox>

          <GroupBox Header="Kompletter Ordner" Padding="8,4,8,6">
            <Button x:Name="BtnSnapFull" Style="{StaticResource NormalButton}" Margin="0,0,0,4"
                    ToolTip="Sichert den kompletten Spielstand-Ordner in einem Stück: alle Charaktere, den Shared Stash, die Einstellungen und die Item-Filter.">Alles sichern</Button>
          </GroupBox>
        </StackPanel>

      <GroupBox Grid.Row="1" Header="Charaktere im Spielstand-Ordner">
        <DataGrid x:Name="GridChars" AutoGenerateColumns="False" IsReadOnly="True"
                  RowStyle="{StaticResource AuswahlZeile}" CellStyle="{StaticResource AuswahlZelle}"
                  SelectionMode="Extended" HeadersVisibility="Column"
                  GridLinesVisibility="Horizontal" RowHeaderWidth="0" Margin="2">
          <DataGrid.Columns>
            <DataGridTextColumn Header="Name"     Binding="{Binding Name}"          Width="*"  MinWidth="130"/>
            <DataGridTextColumn Header="Klasse"   Binding="{Binding ClassName}"     Width="120"/>
            <DataGridTextColumn Header="Lvl"      Binding="{Binding Level}"         Width="48"/>
            <DataGridTextColumn Header="Modus"    Binding="{Binding Mode}"          Width="78"/>
            <!-- SortMemberPath: sortiert nach dem echten Datum statt nach dem
                 formatierten Text, sonst landet 03.01.2019 zwischen 2026er Daten. -->
            <DataGridTextColumn Header="Zuletzt"  Binding="{Binding LastPlayedStr}" Width="118"
                                SortMemberPath="LastPlayedSort"/>
            <DataGridTextColumn Header="Snaps"    Binding="{Binding SnapCount}"     Width="62"/>
          </DataGrid.Columns>
        </DataGrid>
      </GroupBox>
      </Grid>

      <GridSplitter Grid.Column="1" Width="6" HorizontalAlignment="Stretch" Background="Transparent"/>

      <Grid Grid.Column="2">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*" MinHeight="150"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <GroupBox Grid.Row="0" Header="Snapshots verwalten" Padding="8,4,8,6" Margin="0,0,0,6">
          <WrapPanel Orientation="Horizontal">
            <Button x:Name="BtnRestore" Style="{StaticResource NormalButton}" Margin="0,0,6,4">Wiederherstellen...</Button>
            <Button x:Name="BtnDelete"  Style="{StaticResource DangerButton}" Margin="0,0,6,4">Löschen</Button>
            <Border Width="1" Background="#D0D0D0" Margin="4,2,10,6"/>
            <Button x:Name="BtnOpenBackup" Style="{StaticResource IconButton}" Content="&#xE838;" Margin="0,0,0,4"
                    ToolTip="Backup-Ordner im Explorer anzeigen"/>
          </WrapPanel>
        </GroupBox>

        <Border Grid.Row="1" Padding="4,2,4,6">
          <StackPanel Orientation="Horizontal">
            <TextBlock Text="Suche:" VerticalAlignment="Center" Margin="0,0,6,0"/>
            <TextBox x:Name="TxtSearch" Width="180" VerticalAlignment="Center"
                     ToolTip="Sucht in Charaktername, Label, Tags und Notiz"/>
            <TextBlock Text="Tag:" VerticalAlignment="Center" Margin="14,0,6,0"/>
            <ComboBox x:Name="CmbTag" Width="150" VerticalAlignment="Center"/>
            <CheckBox x:Name="ChkOnlySelected" Content="nur gewählter Charakter" VerticalAlignment="Center" Margin="14,0,0,0"/>
            <CheckBox x:Name="ChkHideAuto" Content="Auto-Sicherungen ausblenden" VerticalAlignment="Center" Margin="14,0,0,0"/>
          </StackPanel>
        </Border>

        <GroupBox Grid.Row="2" Header="Snapshots">
          <DataGrid x:Name="GridSnaps" AutoGenerateColumns="False" IsReadOnly="True"
                    RowStyle="{StaticResource AuswahlZeile}" CellStyle="{StaticResource AuswahlZelle}"
                    SelectionMode="Single" HeadersVisibility="Column"
                    GridLinesVisibility="Horizontal" RowHeaderWidth="0" Margin="2">
            <DataGrid.Columns>
              <DataGridTextColumn Header="Erstellt"   Binding="{Binding CreatedStr}" Width="146"
                                  SortMemberPath="SortKey"/>
              <DataGridTextColumn Header="Typ"        Binding="{Binding KindStr}"    Width="132"/>
              <DataGridTextColumn Header="Charakter"  Binding="{Binding char}"       Width="128"/>
              <DataGridTextColumn Header="Lvl"        Binding="{Binding LevelStr}"   Width="48"
                                  SortMemberPath="LevelSort"/>
              <DataGridTextColumn Header="Label"      Binding="{Binding label}"      Width="*" MinWidth="110"/>
              <DataGridTextColumn Header="Tags"       Binding="{Binding TagStr}"     Width="140"/>
              <DataGridTextColumn Header="Notiz"      Binding="{Binding NoteShort}"  Width="150"/>
              <DataGridTextColumn Header="Größe"    Binding="{Binding SizeStr}"    Width="76"
                                  SortMemberPath="SizeSort"/>
            </DataGrid.Columns>
          </DataGrid>
        </GroupBox>

        <GroupBox Grid.Row="3" Header="Details zum gewählten Snapshot" Margin="0,6,0,0">
          <Grid Margin="4">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="Auto"/>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
              <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <TextBlock Grid.Row="0" Grid.Column="0" Text="Label:" VerticalAlignment="Center" Margin="0,0,8,4"/>
            <TextBox   Grid.Row="0" Grid.Column="1" x:Name="TxtLabel" Margin="0,0,8,4"/>

            <TextBlock Grid.Row="1" Grid.Column="0" Text="Tags:" VerticalAlignment="Center" Margin="0,0,8,4"/>
            <TextBox   Grid.Row="1" Grid.Column="1" x:Name="TxtTags" Margin="0,0,8,4"
                       ToolTip="Mehrere Tags durch Komma trennen"/>

            <TextBlock Grid.Row="2" Grid.Column="0" Text="Notiz:" VerticalAlignment="Top" Margin="0,4,8,0"/>
            <TextBox   Grid.Row="2" Grid.Column="1" x:Name="TxtNote" Height="62" Margin="0,0,8,0"
                       AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/>

            <Button Grid.Row="0" Grid.Column="2" Grid.RowSpan="3" x:Name="BtnSaveMeta"
                    Width="130" Height="30" VerticalAlignment="Center">Übernehmen</Button>
          </Grid>
        </GroupBox>
      </Grid>
    </Grid>
  </DockPanel>
</Window>
'@

$RestoreXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Wiederherstellen" Height="430" Width="540"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize">
  <StackPanel Margin="14">
    <TextBlock x:Name="TxtInfo" TextWrapping="Wrap" Margin="0,0,0,12"/>

    <TextBlock Text="Ziel-Charaktername:" Margin="0,0,0,4"/>
    <TextBox x:Name="TxtName" Margin="0,0,0,4"/>
    <TextBlock x:Name="TxtNameHint" TextWrapping="Wrap" FontSize="11" Foreground="#666" Margin="0,0,0,10"
               Text="Leer lassen bzw. Originalname stehen lassen, um den Charakter unter seinem alten Namen zurückzuholen. Ein anderer Name legt eine Kopie als neuen Charakter an."/>

    <CheckBox x:Name="ChkStash" Content="Shared Stash aus dem Snapshot mit wiederherstellen" Margin="0,0,0,4"/>
    <TextBlock x:Name="TxtStashHint" FontSize="11" Foreground="#666" TextWrapping="Wrap" Margin="18,0,0,10"/>

    <CheckBox x:Name="ChkSafety" Content="Vorher automatisch eine Sicherheitskopie anlegen" IsChecked="True" Margin="0,0,0,10"/>

    <TextBlock x:Name="TxtWarnBox" TextWrapping="Wrap" Foreground="#B00020" FontWeight="Bold" Margin="0,0,0,10"/>

    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
      <Button x:Name="BtnOk"     Width="120" Height="30" Margin="0,0,8,0" IsDefault="True">Wiederherstellen</Button>
      <Button x:Name="BtnCancel" Width="90"  Height="30" IsCancel="True">Abbrechen</Button>
    </StackPanel>
  </StackPanel>
</Window>
'@

$SettingsXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Einstellungen" Height="290" Width="620"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize">
  <StackPanel Margin="14">
    <TextBlock Text="Spielstand-Ordner (wo D2R die Charaktere ablegt):" Margin="0,0,0,4"/>
    <DockPanel Margin="0,0,0,12">
      <Button x:Name="BtnBrowseSave" DockPanel.Dock="Right" Width="90" Height="26" Margin="8,0,0,0">Durchsuchen</Button>
      <TextBox x:Name="TxtSave" Height="26" VerticalContentAlignment="Center"/>
    </DockPanel>

    <TextBlock Text="Backup-Ordner (wo die Snapshots gespeichert werden):" Margin="0,0,0,4"/>
    <DockPanel Margin="0,0,0,6">
      <Button x:Name="BtnBrowseBackup" DockPanel.Dock="Right" Width="90" Height="26" Margin="8,0,0,0">Durchsuchen</Button>
      <TextBox x:Name="TxtBackup" Height="26" VerticalContentAlignment="Center"/>
    </DockPanel>
    <TextBlock FontSize="11" Foreground="#666" TextWrapping="Wrap" Margin="0,0,0,14"
               Text="Empfehlung: ein Ordner auf einem anderen Laufwerk als die Spielstände. Enthält später index.json und den Unterordner snapshots."/>

    <TextBlock x:Name="TxtHint" TextWrapping="Wrap" Foreground="#B00020" Margin="0,0,0,10"/>

    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
      <Button x:Name="BtnOk"     Width="100" Height="30" Margin="0,0,8,0" IsDefault="True">Speichern</Button>
      <Button x:Name="BtnCancel" Width="90"  Height="30" IsCancel="True">Abbrechen</Button>
    </StackPanel>
  </StackPanel>
</Window>
'@

# ---------------------------------------------------------------------------
# Sprache
# ---------------------------------------------------------------------------
# Der deutsche Text ist zugleich der Schlüssel. Dadurch bleiben XAML und Code
# lesbar, und eine fehlende Übersetzung fällt auf Deutsch zurück statt zu
# verschwinden. Englische Texte bewusst ohne "&" - das müsste im XAML maskiert
# werden.

$script:TextsEn = @{
    # --- Aktionsleiste ---
    'Sichern' = 'Back up'; 'Snapshot' = 'Snapshot'; 'Ansicht' = 'View'
    'Charaktere sichern' = 'Back up characters'; 'System' = 'System'
    'Kompletter Ordner' = 'Whole folder'; 'Alles sichern' = 'Back up everything'
    'Alle Charaktere markieren (Strg+A)' = 'Select all characters (Ctrl+A)'
    'Markierung aufheben' = 'Clear selection'
    'Markierung aufgehoben.' = 'Selection cleared.'
    'Spielstand-Ordner im Explorer anzeigen' = 'Show the save folder in Explorer'
    'Backup-Ordner im Explorer anzeigen' = 'Show the backup folder in Explorer'
    # 'Listen neu einlesen' steht schon weiter oben
    'Sichert den kompletten Spielstand-Ordner in einem Stück: alle Charaktere, den Shared Stash, die Einstellungen und die Item-Filter.' = 'Backs up the entire save folder in one piece: all characters, the shared stash, the settings and the item filters.'
    'Snapshots verwalten' = 'Manage snapshots'
    'Sichert lokale Charaktere und spielt sie zurück' = 'Backs up local characters and restores them'

    # --- _INFO.txt und _LIESMICH.txt ---
    'Level' = 'Level'; 'Gesichert am' = 'Backed up on'; 'Quelle' = 'Source'; 'Hinweis' = 'Note'
    'D2R lief beim Sichern - Stand ggf. nicht taufrisch' = 'D2R was running - state may not be current'
    'VON HAND WIEDERHERSTELLEN' = 'RESTORING BY HAND'
    '1. D2R beenden.' = '1. Quit D2R.'
    '2. Die Dateien aus diesem Ordner (ohne _INFO.txt und ohne den' = '2. Copy the files from this folder (except _INFO.txt and the'
    '   Unterordner SharedStash) in den Spielstand-Ordner kopieren' = '   SharedStash subfolder) into the save folder, replacing'
    '   und vorhandene ersetzen.' = '   the existing ones.'
    '3. Anderer Name gewünscht? Alle Dateien gleich umbenennen, etwa' = '3. Want a different name? Rename every file the same way, e.g.'
    '   Held.d2s -> Neuer.d2s, Held.ctl -> Neuer.ctl und so weiter.' = '   Hero.d2s -> NewOne.d2s, Hero.ctl -> NewOne.ctl and so on.'
    '   Die Endungen bleiben. Der Name steht nur im Dateinamen,' = '   Keep the extensions. The name lives only in the file name,'
    '   nicht in der Datei selbst.' = '   not inside the file itself.'
    '4. SharedStash nur zurückkopieren, wenn auch der Truhen-Inhalt' = '4. Only copy SharedStash back if you also want the stash'
    '   von damals gewünscht ist - der gilt für alle Charaktere.' = '   contents from back then - it applies to every character.'
    '2. Alle Dateien aus diesem Ordner (ohne _INFO.txt) in den' = '2. Copy all files from this folder (except _INFO.txt) into'
    '   Spielstand-Ordner kopieren und vorhandene ersetzen.' = '   the save folder, replacing the existing ones.'
    '   Achtung: das betrifft sämtliche Charaktere.' = '   Careful: this affects every character.'
    'In diesem Ordner liegen die Sicherungen deiner D2R-Charaktere.' = 'This folder holds the backups of your D2R characters.'
    '    Eine Sicherung eines Charakters. Darin die Spielstanddateien,' = '    One backup of one character. Contains the save files,'
    '    im Unterordner SharedStash die gemeinsame Truhe, und _INFO.txt' = '    the shared stash in the SharedStash subfolder, and _INFO.txt'
    '    mit allen Angaben und einer Anleitung zum Zurückkopieren.' = '    with all details and instructions for copying it back.'
    '    Eine Sicherung des kompletten Spielstand-Ordners.' = '    One backup of the entire save folder.'
    '    Labels, Tags und Notizen für das Programm. Geht diese Datei' = '    Labels, tags and notes for the program. If this file is'
    '    verloren, sind die Sicherungen selbst weiterhin benutzbar —' = '    lost, the backups themselves remain usable — only the'
    '    nur die Beschriftungen fehlen dann.' = '    labels are gone.'
    'Die Dateien liegen unkomprimiert. Du brauchst dieses Programm nicht,' = 'The files are stored uncompressed. You do not need this program'
    'um an sie heranzukommen: D2R beenden, Dateien in den Spielstand-Ordner' = 'to get at them: quit D2R, copy the files into the save folder,'
    'kopieren, fertig. Siehe _INFO.txt in der jeweiligen Sicherung.' = 'done. See _INFO.txt inside each backup.'
    'Listen neu einlesen' = 'Reload the lists'
    'Öffnet den Ordner mit den Spielständen' = 'Opens the folder holding the save games'
    'Öffnet den Ordner mit den Snapshots' = 'Opens the folder holding the snapshots'
    'Charakter' = 'Character'; 'Alle' = 'All'
    'Wiederherstellen...' = 'Restore...'; 'Löschen' = 'Delete'; 'Aktualisieren' = 'Refresh'
    'Ordner' = 'Folders'; 'Spielstand-Ordner' = 'Save folder'; 'Backup-Ordner' = 'Backup folder'
    'Einstellungen' = 'Settings'; 'Beenden' = 'Exit'; 'Sprache' = 'Language'
    'Sichert den ausgewählten Charakter samt Shared Stash' = 'Backs up the selected character including the shared stash'
    'Markierte sichern' = 'Back up selected'
    'Sichert die markierten Charaktere samt Shared Stash. Mehrere mit Strg-Klick oder Umschalt-Klick markieren.' = 'Backs up the selected characters including the shared stash. Select several with Ctrl-click or Shift-click.'
    '{0} Charaktere gesichert ({1}){2}.' = '{0} characters backed up ({1}){2}.'
    '{0} Charaktere markiert.' = '{0} characters selected.'
    'Legt von jedem Charakter einen Snapshot an - unveränderte werden übersprungen' = 'Creates a snapshot of every character - unchanged ones are skipped'
    'Sichert den kompletten Spielstand-Ordner' = 'Backs up the entire save folder'
    'Auf Englisch umschalten' = 'Switch to German'
    'Programm beenden' = 'Close the program'

    # --- Listen ---
    'Charaktere im Spielstand-Ordner' = 'Characters in the save folder'
    'Name' = 'Name'; 'Klasse' = 'Class'; 'Lvl' = 'Lvl'; 'Modus' = 'Mode'
    'Zuletzt' = 'Last played'; 'Snaps' = 'Snaps'; 'Snapshots' = 'Snapshots'
    'Erstellt' = 'Created'; 'Typ' = 'Type'; 'Label' = 'Label'; 'Tags' = 'Tags'
    'Notiz' = 'Note'; 'Größe' = 'Size'
    'Suche:' = 'Search:'; 'Tag:' = 'Tag:'; 'Label:' = 'Label:'; 'Tags:' = 'Tags:'; 'Notiz:' = 'Note:'
    'Sucht in Charaktername, Label, Tags und Notiz' = 'Searches character name, label, tags and note'
    'nur gewählter Charakter' = 'selected character only'
    'Auto-Sicherungen ausblenden' = 'hide automatic backups'
    'Details zum gewählten Snapshot' = 'Details of the selected snapshot'
    'Mehrere Tags durch Komma trennen' = 'Separate multiple tags with commas'
    'Übernehmen' = 'Apply'; 'Bereit.' = 'Ready.'; '(alle)' = '(all)'

    # --- Klassen ---
    'Amazone' = 'Amazon'; 'Zauberin' = 'Sorceress'; 'Totenbeschwörer' = 'Necromancer'
    'Paladin' = 'Paladin'; 'Barbar' = 'Barbarian'; 'Druide' = 'Druid'
    'Assassine' = 'Assassin'; 'Hexenbeschwörer' = 'Warlock'

    # --- Wiederherstellen-Dialog ---
    'Wiederherstellen' = 'Restore'; 'Abbrechen' = 'Cancel'
    'Ziel-Charaktername:' = 'Target character name:'
    'Leer lassen bzw. Originalname stehen lassen, um den Charakter unter seinem alten Namen zurückzuholen. Ein anderer Name legt eine Kopie als neuen Charakter an.' = 'Leave the original name to restore the character under its old name. A different name creates a copy as a new character.'
    'Shared Stash aus dem Snapshot mit wiederherstellen' = 'Also restore the shared stash from this snapshot'
    'Der Stash gilt für alle Charaktere. Wird er mit wiederhergestellt, überschreibt er den aktuellen Stash-Inhalt aller Charaktere.' = 'The stash is shared by all characters. Restoring it overwrites the current stash contents for every character.'
    'Der Stash gehört allen Charakteren gemeinsam - Zurückspielen betrifft jeden von ihnen.' = 'The stash belongs to all characters together - restoring it affects every one of them.'
    'Er ist seit dieser Sicherung unverändert, das Häkchen macht also keinen Unterschied.' = 'It is unchanged since this backup, so the checkbox makes no difference.'
    'Er hat sich seit dieser Sicherung geändert: Zurückspielen verwirft alles, was seitdem eingelagert wurde.' = 'It has changed since this backup: restoring it discards everything stored there since.'
    'Vorher automatisch eine Sicherheitskopie anlegen' = 'Create a safety backup beforehand'
    'Snapshot enthält keinen Shared Stash' = 'This snapshot contains no shared stash'
    'Beim kompletten Ordner ist kein Umbenennen möglich.' = 'Renaming is not possible for a whole-folder snapshot.'

    # --- Einstellungen ---
    'Spielstand-Ordner (wo D2R die Charaktere ablegt):' = 'Save folder (where D2R stores the characters):'
    'Backup-Ordner (wo die Snapshots gespeichert werden):' = 'Backup folder (where snapshots are stored):'
    'Durchsuchen' = 'Browse'; 'Speichern' = 'Save'
    'Empfehlung: ein Ordner auf einem anderen Laufwerk als die Spielstände. Enthält später index.json und den Unterordner snapshots.' = 'Recommended: a folder on a different drive than the save games. Will contain index.json and the snapshots subfolder.'
    'Spielstand-Ordner von D2R wählen' = 'Select the D2R save folder'
    'Ordner für die Backups wählen' = 'Select the folder for backups'
    'Der Spielstand-Ordner existiert nicht.' = 'The save folder does not exist.'
    'Bitte einen Backup-Ordner angeben.' = 'Please specify a backup folder.'
    'Erster Start: Bitte lege fest, wo die Backups gespeichert werden sollen.' = 'First start: please choose where backups should be stored.'
    'Im Spielstand-Ordner wurden keine Charaktere gefunden:' = 'No characters were found in the save folder:'
    'Bitte den richtigen Ordner unter "Einstellungen" eintragen.' = 'Please set the correct folder under "Settings".'

    # --- Meldungen ---
    'Bitte links einen Charakter auswählen.' = 'Please select a character on the left.'
    'Bitte einen Snapshot auswählen.' = 'Please select a snapshot.'
    'Es sind keine Charaktere vorhanden.' = 'There are no characters.'
    'Im Spielstand-Ordner wurden keine Dateien gefunden.' = 'No files were found in the save folder.'
    'Sammelsicherung abgebrochen.' = 'Bulk backup cancelled.'
    'Sicherung des kompletten Ordners abgebrochen.' = 'Whole-folder backup cancelled.'
    'Snapshot gelöscht.' = 'Snapshot deleted.'
    'Label, Tags und Notiz gespeichert.' = 'Label, tags and note saved.'
    # 'Alles sichern' steht schon weiter oben - der Knopf und der Titel der
    # Rückfrage benutzen denselben Text.
    'Charakter sichern' = 'Back up character'; 'Snapshot löschen' = 'Delete snapshot'
    'D2R läuft' = 'D2R is running'; 'Name bereits vergeben' = 'Name already taken'
    'Sichern fehlgeschlagen:' = 'Backup failed:'
    'Wiederherstellen fehlgeschlagen:' = 'Restore failed:'
    'Löschen fehlgeschlagen:' = 'Deleting failed:'
    'Speichern fehlgeschlagen:' = 'Saving failed:'
    'D2R läuft - Wiederherstellen erst nach dem Beenden!' = 'D2R is running - restore only after quitting!'
    "{0} Snapshot(s) angezeigt, {1} insgesamt." = '{0} snapshot(s) shown, {1} in total.'
    "Snapshot von '{0}' angelegt ({1}){2}." = "Snapshot of '{0}' created ({1}){2}."
    'Kompletter Ordner gesichert ({0} Dateien, {1}){2}.' = 'Whole folder backed up ({0} files, {1}){2}.'
    'Sammelsicherung: {0} gesichert ({1}), {2} unverändert übersprungen, {3} fehlgeschlagen.' = 'Bulk backup: {0} saved ({1}), {2} unchanged and skipped, {3} failed.'
    " - D2R lief dabei, Stand ggf. nicht taufrisch (Tag 'spiel-lief')" = " - D2R was running, state may not be current (tag 'spiel-lief')"
    ' - inhaltlich identisch mit der Sicherung von {0}' = ' - identical in content to the backup from {0}'
    'Wiederhergestellt{0} - {1} Datei(en).' = 'Restored{0} - {1} file(s).'
    "Wiederherstellung abgeschlossen{0}.`n`n{1} Datei(en) geschrieben." = "Restore finished{0}.`n`n{1} file(s) written."
    'Von allen {0} Charakteren einen Snapshot anlegen?' = 'Create a snapshot of all {0} characters?'
    'Charaktere, deren Stand sich seit ihrer letzten Sicherung nicht geändert hat, werden übersprungen.' = 'Characters unchanged since their last backup are skipped.'
    'Den kompletten Spielstand-Ordner sichern?' = 'Back up the entire save folder?'
    '{0} Dateien, {1} unkomprimiert.' = '{0} files, {1} uncompressed.'
    'Das umfasst alle Charaktere, den Shared Stash und die Einstellungen.' = 'This includes all characters, the shared stash and the settings.'
    'Snapshot endgültig löschen?' = 'Delete this snapshot permanently?'
    'Die Spielstände selbst bleiben unberührt.' = 'The save games themselves remain untouched.'
    'Bei {0} Charakter(en) hat es nicht geklappt:' = 'It did not work for {0} character(s):'
    'Es gibt bereits einen Charakter namens ''{0}''. Seine Dateien werden überschrieben.' = "A character named '{0}' already exists. Its files will be overwritten."
    'Fortfahren?' = 'Continue?'
    'D2R läuft. Die Wiederherstellung wird vom laufenden Spiel höchstwahrscheinlich wieder überschrieben.' = 'D2R is running. The restore will most likely be overwritten again by the running game.'
    'Trotzdem fortfahren?' = 'Continue anyway?'
    'Ohne Backup-Ordner kann nicht gesichert werden. Du kannst ihn jederzeit unter "Einstellungen" nachtragen.' = 'Without a backup folder nothing can be saved. You can set it later under "Settings".'
    'Automatisch vor Wiederherstellung' = 'Automatic, before restore'
    'Kompletten Ordner vom {0} wiederherstellen. Alle Dateien aus dem Snapshot werden in den Spielstand-Ordner zurückgeschrieben und überschreiben gleichnamige Dateien.' = 'Restore whole folder from {0}. All files from the snapshot are written back into the save folder, overwriting files of the same name.'
    "Charakter '{0}' vom {1} wiederherstellen ({2}, Level {3})." = "Restore character '{0}' from {1} ({2}, level {3})."
    'Achtung: D2R läuft gerade. Das Spiel schreibt seinen Stand beim Beenden zurück und würde die Wiederherstellung überschreiben. Bitte zuerst D2R beenden.' = 'Warning: D2R is currently running. The game writes its state back on exit and would overwrite the restore. Please quit D2R first.'
    'Der Name darf nicht leer sein.' = 'The name must not be empty.'
    'Der Name muss zwischen 2 und 15 Zeichen lang sein.' = 'The name must be between 2 and 15 characters long.'
    'Erlaubt sind Buchstaben, Ziffern, "_" und "-"; das erste Zeichen muss ein Buchstabe sein.' = 'Allowed are letters, digits, "_" and "-"; the first character must be a letter.'
    'D2R erlaubt höchstens ein "_" oder "-" im Namen.' = 'D2R allows at most one "_" or "-" in a name.'
}

function T {
    param([string]$De)
    if (-not $script:Config -or $script:Config.Language -ne 'en') { return $De }
    if ($script:TextsEn.ContainsKey($De)) { return $script:TextsEn[$De] }
    $De
}

# Übersetzt nur Beschriftungen im XAML - niemals Bindungspfade oder Namen.
function Convert-XamlText([string]$Xaml) {
    $evaluator = { param($m) $m.Groups[1].Value + '="' + (T $m.Groups[2].Value) + '"' }
    $out = [regex]::Replace($Xaml, '\b(Header|Content|Text|ToolTip|Title)="([^"]*)"', $evaluator)
    $out = [regex]::Replace($out, '>([^<>]+)</Button>', { param($m) '>' + (T $m.Groups[1].Value) + '</Button>' })
    $out
}

function ConvertFrom-Xaml([string]$Xaml) {
    $text = if ($script:Config -and $script:Config.Language -eq 'en') { Convert-XamlText $Xaml } else { $Xaml }
    [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new([xml]$text))
}

# ---------------------------------------------------------------------------
# Anzeige-Helfer
# ---------------------------------------------------------------------------

function ConvertTo-DateTimeSafe {
    param($Value)
    # PowerShell 7 macht aus ISO-Strings beim ConvertFrom-Json bereits ein
    # DateTime, Windows PowerShell 5.1 lässt sie als String stehen. Ohne diese
    # Fallunterscheidung wandelt [datetime]::Parse das DateTime erst in die
    # invariante Schreibweise "08/03/2026" und liest sie deutsch als 8. März -
    # Tag und Monat wären vertauscht.
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return $Value }
    if ($Value -is [datetimeoffset]) { return $Value.LocalDateTime }
    try {
        [datetime]::Parse([string]$Value,
                          [System.Globalization.CultureInfo]::InvariantCulture,
                          [System.Globalization.DateTimeStyles]::RoundtripKind)
    } catch { $null }
}

function Format-Timestamp {
    param($Value, [string]$Format = 'dd.MM.yyyy HH:mm:ss')
    $dt = ConvertTo-DateTimeSafe $Value
    if ($dt) { $dt.ToString($Format) } else { '?' }
}

function Format-Size([long]$Bytes) {
    if ($Bytes -lt 1024) { return "$Bytes B" }
    if ($Bytes -lt 1048576) { return '{0:N1} KB' -f ($Bytes / 1024) }
    '{0:N1} MB' -f ($Bytes / 1048576)
}

function ConvertTo-SnapshotRow($Record) {
    $created = ConvertTo-DateTimeSafe $Record.created
    $note    = if ($Record.note) { [string]$Record.note } else { '' }
    $tags    = @($Record.tags) -join ', '

    $row = $Record.PSObject.Copy()
    # Mit Sekunden: mehrere Sicherungen derselben Minute wären sonst nicht
    # voneinander zu unterscheiden.
    $row | Add-Member NoteProperty CreatedStr $(if ($created) { $created.ToString('dd.MM.yyyy HH:mm:ss') } else { '' }) -Force
    # Auto-Kennzeichnung als Zusatz, nicht als eigener Typ: sonst erschiene eine
    # automatische Gesamtstand-Sicherung als "Gesamtstand", verschwände aber
    # trotzdem beim Filter "Auto-Sicherungen ausblenden".
    $kindStr = if ($Record.kind -eq 'full') { T 'Kompletter Ordner' } else { T 'Charakter' }
    if ($Record.automatic) { $kindStr += ' (Auto)' }
    $row | Add-Member NoteProperty KindStr $kindStr -Force
    $row | Add-Member NoteProperty TagStr     $tags -Force
    $row | Add-Member NoteProperty NoteShort  $(if ($note.Length -gt 40) { $note.Substring(0,40) + '...' } else { ($note -replace '\r?\n',' ') }) -Force
    $row | Add-Member NoteProperty SizeStr    (Format-Size ([long]$Record.sizeBytes)) -Force
    # Eigene Sortierfelder mit festem Typ. Aus index.json kommen Zahlen als Int32,
    # frisch erzeugte Datensätze tragen Int64 - WPF kann beides nicht miteinander
    # vergleichen und wirft beim Sortieren "Fehler beim Vergleichen von zwei
    # Elementen im Array".
    $row | Add-Member NoteProperty SizeSort   ([long]$Record.sizeBytes) -Force
    $row | Add-Member NoteProperty LevelSort  ([int]$Record.level) -Force
    # Ein Gesamtstand gehört zu keinem Charakter - dort wäre "0" irreführend.
    $row | Add-Member NoteProperty LevelStr   $(if ($Record.kind -eq 'full') { '' } else { [string]$Record.level }) -Force
    $row | Add-Member NoteProperty SortKey    $(if ($created) { $created } else { [datetime]::MinValue }) -Force
    $row
}

# ---------------------------------------------------------------------------
# Hauptfenster
# ---------------------------------------------------------------------------

$script:Config = Import-Config
$script:Index  = $null

$win = ConvertFrom-Xaml $MainXaml

$GridChars       = $win.FindName('GridChars')
$GridSnaps       = $win.FindName('GridSnaps')
$TxtStatus       = $win.FindName('TxtStatus')
$TxtWarn         = $win.FindName('TxtWarn')
$TxtSearch       = $win.FindName('TxtSearch')
$CmbTag          = $win.FindName('CmbTag')
$ChkOnlySelected = $win.FindName('ChkOnlySelected')
$ChkHideAuto     = $win.FindName('ChkHideAuto')
$TxtLabel        = $win.FindName('TxtLabel')
$TxtTags         = $win.FindName('TxtTags')
$TxtNote         = $win.FindName('TxtNote')

function Set-Status([string]$Text) { $TxtStatus.Text = $Text }

# --- Sortierung merken -------------------------------------------------------
# Beim Neubefüllen einer Liste verwirft WPF die Sortierung. Sie wird deshalb
# nach jedem Aktualisieren wieder gesetzt und zusätzlich in config.json abgelegt,
# damit sie den Programmstart überlebt.

function Save-GridSort {
    param($Grid, [string]$Key)
    $sorts = @($Grid.Items.SortDescriptions)
    if ($sorts.Count -gt 0) {
        $script:Config.$Key = [pscustomobject]@{
            Property  = $sorts[0].PropertyName
            Direction = [string]$sorts[0].Direction
        }
    } else {
        $script:Config.$Key = $null
    }
    try { Export-Config } catch { }
}

function Restore-GridSort {
    param($Grid, $Sort)
    $Grid.Items.SortDescriptions.Clear()
    foreach ($c in $Grid.Columns) { $c.SortDirection = $null }
    if (-not $Sort -or -not $Sort.Property) { return }

    # Gespeicherte Sortierungen älterer Fassungen auf die heutigen Sortierfelder
    # umbiegen, sonst verliert der Nutzer beim Aktualisieren seine Sortierung.
    $legacy = @{
        'sizeBytes' = 'SizeSort';    'SizeStr'       = 'SizeSort'
        'level'     = 'LevelSort';   'LevelStr'      = 'LevelSort'
        'created'   = 'SortKey';     'CreatedStr'    = 'SortKey'
        'LastPlayed'= 'LastPlayedSort'; 'LastPlayedStr' = 'LastPlayedSort'
    }
    $prop = $Sort.Property
    if ($legacy.ContainsKey($prop)) { $prop = $legacy[$prop] }
    $col  = $Grid.Columns | Where-Object { $_.SortMemberPath -eq $prop } | Select-Object -First 1

    # Aeltere Konfigurationen haben die Anzeigespalte gespeichert (z.B. "SizeStr"
    # statt "sizeBytes"). Dann würde weiter nach Text sortiert - also auf den
    # echten Sortierpfad der Spalte umbiegen.
    if (-not $col) {
        $col = $Grid.Columns | Where-Object {
            $_.Binding -and $_.Binding.Path -and $_.Binding.Path.Path -eq $prop
        } | Select-Object -First 1
        if ($col) { $prop = $col.SortMemberPath }
    }
    if (-not $col) { return }   # Spalte gibt es nicht mehr - unsortiert lassen

    $dir = if ($Sort.Direction -eq 'Descending') {
        [System.ComponentModel.ListSortDirection]::Descending
    } else {
        [System.ComponentModel.ListSortDirection]::Ascending
    }
    $Grid.Items.SortDescriptions.Add((New-Object System.ComponentModel.SortDescription($prop, $dir)))
    $col.SortDirection = $dir
    $Grid.Items.Refresh()
}

function Update-Warning {
    if (Test-D2RRunning) {
        $TxtWarn.Text = (T 'D2R läuft - Wiederherstellen erst nach dem Beenden!')
    } else {
        $TxtWarn.Text = ''
    }
}

function Get-SelectedChar {
    if ($GridChars.SelectedItem) { return $GridChars.SelectedItem.Name }
    ''
}

# Die Liste erlaubt Mehrfachauswahl (Strg- bzw. Umschalt-Klick).
#
# ACHTUNG: Bei genau einem markierten Charakter packt PowerShell das Array beim
# Rückgeben aus - der Aufrufer bekommt dann den blanken String, und [0] lieferte
# 'A' statt 'Amazone_Poison'. Deshalb steht an JEDER Aufrufstelle ein @() darum.
function Get-SelectedChars {
    @($GridChars.SelectedItems | ForEach-Object { $_.Name })
}

# Der Knopf nennt immer die Anzahl - so ist vor dem Klick klar, wie viele
# Charaktere gleich gesichert werden.
function Update-SnapButtonLabel {
    $knopf = $win.FindName('BtnSnapChar')
    if (-not $knopf) { return }
    $knopf.Content = (T 'Markierte sichern') + ' (' + @(Get-SelectedChars).Count + ')'
}

function Get-SelectedSnapshotRecord {
    $row = $GridSnaps.SelectedItem
    if (-not $row) { return $null }
    $script:Index.snapshots | Where-Object { $_.id -eq $row.id } | Select-Object -First 1
}

function Update-TagFilter {
    $current = $CmbTag.SelectedItem
    $tags = @($script:Index.snapshots | ForEach-Object { @($_.tags) } | Where-Object { $_ } | Sort-Object -Unique)
    $CmbTag.Items.Clear()
    $CmbTag.Items.Add((T '(alle)')) | Out-Null
    foreach ($t in $tags) { $CmbTag.Items.Add($t) | Out-Null }
    if ($current -and $CmbTag.Items.Contains($current)) { $CmbTag.SelectedItem = $current } else { $CmbTag.SelectedIndex = 0 }
}

function Update-SnapshotGrid {
    $rows = @($script:Index.snapshots | ForEach-Object { ConvertTo-SnapshotRow $_ })

    $search = $TxtSearch.Text
    if ($search) {
        $rows = @($rows | Where-Object {
            "$($_.char) $($_.label) $($_.TagStr) $($_.note)" -like "*$search*"
        })
    }

    $tag = $CmbTag.SelectedItem
    if ($tag -and $tag -ne (T '(alle)')) {
        $rows = @($rows | Where-Object { @($_.tags) -contains $tag })
    }

    if ($ChkOnlySelected.IsChecked) {
        $sel = @(Get-SelectedChars)
        if ($sel.Count -gt 0) { $rows = @($rows | Where-Object { $sel -contains $_.char }) }
    }

    if ($ChkHideAuto.IsChecked) {
        $rows = @($rows | Where-Object { -not $_.automatic })
    }

    $GridSnaps.ItemsSource = @($rows | Sort-Object SortKey -Descending)
    Restore-GridSort $GridSnaps $script:Config.SortSnaps
    Set-Status ((T "{0} Snapshot(s) angezeigt, {1} insgesamt.") -f $GridSnaps.Items.Count, $script:Index.snapshots.Count)
}

function Update-All {
    # Mehrfachauswahl über das Neuladen hinweg erhalten.
    $selNamen = @(Get-SelectedChars)
    $GridChars.ItemsSource = Get-Characters
    Restore-GridSort $GridChars $script:Config.SortChars
    if ($selNamen.Count -gt 0) {
        $GridChars.SelectedItems.Clear()
        foreach ($eintrag in $GridChars.Items) {
            if ($selNamen -contains $eintrag.Name) { [void]$GridChars.SelectedItems.Add($eintrag) }
        }
    }
    # Immer eine Vorauswahl treffen: ohne markierten Charakter wirkt der Knopf
    # "Charakter sichern" wie ein Fehlklick, weil er nur einen Hinweis zeigt.
    if ($GridChars.SelectedItems.Count -eq 0 -and $GridChars.Items.Count -gt 0) {
        $GridChars.SelectedIndex = 0
    }
    Update-SnapButtonLabel
    Update-TagFilter
    Update-SnapshotGrid
    Update-Warning
}

function Clear-Details {
    $TxtLabel.Text = ''
    $TxtTags.Text  = ''
    $TxtNote.Text  = ''
}

# --- Einstellungen -----------------------------------------------------------

function Show-SettingsDialog {
    param([switch]$FirstRun)

    $dlg = ConvertFrom-Xaml $SettingsXaml
    $dlg.Owner = $win
    $txtSave    = $dlg.FindName('TxtSave')
    $txtBackup  = $dlg.FindName('TxtBackup')
    $txtHint    = $dlg.FindName('TxtHint')
    $btnOk      = $dlg.FindName('BtnOk')

    $txtSave.Text   = $script:Config.SavePath
    $txtBackup.Text = $script:Config.BackupPath
    if ($FirstRun) {
        $txtHint.Text = T 'Erster Start: Bitte lege fest, wo die Backups gespeichert werden sollen.'
        # Vorschlag neben dem Programmordner statt fest verdrahtet: auf einem
        # anderen Rechner gäbe es den ursprünglichen Pfad sonst gar nicht.
        if (-not $txtBackup.Text) {
            $txtBackup.Text = Join-Path (Split-Path -Parent $script:ScriptDir) 'D2R-Backups'
        }
    }

    $browse = {
        param($TargetBox, $Description)
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog
        $fbd.Description = $Description
        if ($TargetBox.Text -and (Test-Path -LiteralPath $TargetBox.Text)) { $fbd.SelectedPath = $TargetBox.Text }
        if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $TargetBox.Text = $fbd.SelectedPath }
    }

    $dlg.FindName('BtnBrowseSave').Add_Click({   & $browse $txtSave   (T 'Spielstand-Ordner von D2R wählen') }.GetNewClosure())
    $dlg.FindName('BtnBrowseBackup').Add_Click({ & $browse $txtBackup (T 'Ordner für die Backups wählen') }.GetNewClosure())

    $btnOk.Add_Click({
        if (-not $txtSave.Text -or -not (Test-Path -LiteralPath $txtSave.Text)) {
            $txtHint.Text = T 'Der Spielstand-Ordner existiert nicht.'
            return
        }
        if (-not $txtBackup.Text) {
            $txtHint.Text = T 'Bitte einen Backup-Ordner angeben.'
            return
        }
        try {
            if (-not (Test-Path -LiteralPath $txtBackup.Text)) {
                New-Item -ItemType Directory -Path $txtBackup.Text -Force | Out-Null
            }
        } catch {
            $txtHint.Text = "Backup-Ordner konnte nicht angelegt werden: $($_.Exception.Message)"
            return
        }
        $dlg.DialogResult = $true
    }.GetNewClosure())

    if ($dlg.ShowDialog()) {
        $script:Config.SavePath   = $txtSave.Text
        $script:Config.BackupPath = $txtBackup.Text
        Export-Config
        Import-Index
        Update-All
        return $true
    }
    $false
}

# --- Wiederherstellen --------------------------------------------------------

function Show-RestoreDialog {
    param([object]$Record)

    $dlg = ConvertFrom-Xaml $RestoreXaml
    $dlg.Owner = $win
    $txtInfo  = $dlg.FindName('TxtInfo')
    $txtName  = $dlg.FindName('TxtName')
    $chkStash = $dlg.FindName('ChkStash')
    $chkSafe  = $dlg.FindName('ChkSafety')
    $txtWarnB = $dlg.FindName('TxtWarnBox')
    $btnOk    = $dlg.FindName('BtnOk')

    $created = Format-Timestamp $Record.created 'dd.MM.yyyy HH:mm'

    if ($Record.kind -eq 'full') {
        $txtInfo.Text = ((T 'Kompletten Ordner vom {0} wiederherstellen. Alle Dateien aus dem Snapshot werden in den Spielstand-Ordner zurückgeschrieben und überschreiben gleichnamige Dateien.') -f $created)
        $txtName.IsEnabled  = $false
        $chkStash.IsEnabled = $false
        $dlg.FindName('TxtNameHint').Text = T 'Beim kompletten Ordner ist kein Umbenennen möglich.'
    } else {
        $txtInfo.Text = ((T "Charakter '{0}' vom {1} wiederherstellen ({2}, Level {3}).") -f $Record.char, $created, $Record.className, $Record.level)
        $txtName.Text = $Record.char
        $chkStash.IsEnabled = [bool]$Record.includesStash
        if (-not $Record.includesStash) { $chkStash.Content = T 'Snapshot enthält keinen Shared Stash' }

        # Konkret sagen, ob das Häkchen im Moment überhaupt etwas bewirkt.
        $txtStash = $dlg.FindName('TxtStashHint')
        $satz = T 'Der Stash gehört allen Charakteren gemeinsam - Zurückspielen betrifft jeden von ihnen.'
        if ($Record.includesStash) {
            switch (Test-StashUnveraendert $Record) {
                $true {
                    $txtStash.Text = $satz + ' ' + (T 'Er ist seit dieser Sicherung unverändert, das Häkchen macht also keinen Unterschied.')
                }
                $false {
                    $txtStash.Text = $satz + ' ' + (T 'Er hat sich seit dieser Sicherung geändert: Zurückspielen verwirft alles, was seitdem eingelagert wurde.')
                    $txtStash.Foreground = [System.Windows.Media.Brushes]::Firebrick
                }
                default { $txtStash.Text = $satz }
            }
        } else {
            $txtStash.Text = $satz
        }
    }

    if (Test-D2RRunning) {
        $txtWarnB.Text = T 'Achtung: D2R läuft gerade. Das Spiel schreibt seinen Stand beim Beenden zurück und würde die Wiederherstellung überschreiben. Bitte zuerst D2R beenden.'
    }

    $btnOk.Add_Click({
        $target = ''
        if ($Record.kind -eq 'char') {
            $target = $txtName.Text.Trim()
            $err = Test-D2RName $target
            if ($err) { $txtWarnB.Text = $err; return }

            if ($target -ne $Record.char) {
                $existing = Get-CharacterFiles $target
                if ($existing.Count -gt 0) {
                    $ans = [System.Windows.MessageBox]::Show(
                        (((T 'Es gibt bereits einen Charakter namens ''{0}''. Seine Dateien werden überschrieben.') -f $target) + "`n`n" + (T 'Fortfahren?')),
                        (T 'Name bereits vergeben'), 'YesNo', 'Warning')
                    if ($ans -ne 'Yes') { return }
                }
            }
        }

        if (Test-D2RRunning) {
            $ans = [System.Windows.MessageBox]::Show(
                ((T 'D2R läuft. Die Wiederherstellung wird vom laufenden Spiel höchstwahrscheinlich wieder überschrieben.') + "`n`n" + (T 'Trotzdem fortfahren?')),
                (T 'D2R läuft'), 'YesNo', 'Warning')
            if ($ans -ne 'Yes') { return }
        }

        $dlg.Tag = [pscustomobject]@{
            TargetName   = $target
            RestoreStash = [bool]$chkStash.IsChecked
            Safety       = [bool]$chkSafe.IsChecked
        }
        $dlg.DialogResult = $true
    }.GetNewClosure())

    if ($dlg.ShowDialog()) { return $dlg.Tag }
    $null
}

# --- Ereignisse --------------------------------------------------------------

$GridChars.Add_SelectionChanged({
    Update-SnapButtonLabel
    if ($ChkOnlySelected.IsChecked) { Update-SnapshotGrid }
})

# Das Sorting-Ereignis feuert, BEVOR WPF sortiert hat - die neue Reihenfolge
# steht erst danach fest. Deshalb wird das Sichern nachgelagert eingeplant.
$GridChars.Add_Sorting({
    [void]$GridChars.Dispatcher.BeginInvoke(
        [System.Windows.Threading.DispatcherPriority]::Background,
        [action]{ Save-GridSort $GridChars 'SortChars' })
})

$GridSnaps.Add_Sorting({
    [void]$GridSnaps.Dispatcher.BeginInvoke(
        [System.Windows.Threading.DispatcherPriority]::Background,
        [action]{ Save-GridSort $GridSnaps 'SortSnaps' })
})

$GridSnaps.Add_SelectionChanged({
    $rec = Get-SelectedSnapshotRecord
    if (-not $rec) { Clear-Details; return }
    $TxtLabel.Text = [string]$rec.label
    $TxtTags.Text  = (@($rec.tags) -join ', ')
    $TxtNote.Text  = [string]$rec.note
})

$TxtSearch.Add_TextChanged({ Update-SnapshotGrid })
$CmbTag.Add_SelectionChanged({ Update-SnapshotGrid })
$ChkOnlySelected.Add_Click({ Update-SnapshotGrid })
$ChkHideAuto.Add_Click({ Update-SnapshotGrid })

$win.FindName('BtnRefresh').Add_Click({ Update-All })

# Markiert nur - sichert bewusst nichts. Strg+A in der Liste tut dasselbe, der
# Knopf macht es nur auffindbar.
$win.FindName('BtnSelectAll').Add_Click({
    $GridChars.SelectAll()
    Update-SnapButtonLabel
    Set-Status ((T '{0} Charaktere markiert.') -f @(Get-SelectedChars).Count)
})

$win.FindName('BtnDeselectAll').Add_Click({
    $GridChars.UnselectAll()
    Update-SnapButtonLabel
    Set-Status (T 'Markierung aufgehoben.')
})

$win.FindName('BtnSnapChar').Add_Click({
    # Arbeitet über die gesamte Auswahl. Anders als "Alle sichern" wird dabei
    # nichts übersprungen: wer gezielt markiert, meint es auch so.
    $namen = @(Get-SelectedChars)
    if ($namen.Count -eq 0) {
        [void][System.Windows.MessageBox]::Show((T 'Bitte links einen Charakter auswählen.'), $script:AppName, 'OK', 'Information')
        return
    }

    $angelegt = 0; $bytes = 0; $fehler = @(); $letzter = $null
    if ($namen.Count -gt 1) { [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait }
    try {
        foreach ($n in $namen) {
            try {
                $rec = New-Snapshot -Kind char -CharName $n
                $angelegt++; $bytes += [long]$rec.sizeBytes; $letzter = $rec
            } catch {
                $fehler += "$n : $($_.Exception.Message)"
            }
        }
    } finally {
        [System.Windows.Input.Mouse]::OverrideCursor = $null
    }

    Update-All

    # Eigener Schutz: stolpert das Zusammenbauen der Meldung, soll trotzdem
    # sichtbar bleiben, dass gesichert wurde. Ohne das verschluckt WPF die
    # Ausnahme und in der Statuszeile stünde weiter der alte Text.
    try {
        $hint = if ($letzter -and $letzter.d2rRunning) { T " - D2R lief dabei, Stand ggf. nicht taufrisch (Tag 'spiel-lief')" } else { '' }

        if ($namen.Count -eq 1 -and $letzter) {
            # Hinweis, wenn sich seit einer früheren Sicherung nichts geändert hat.
            # Nur bei einer Einzelsicherung sinnvoll - sonst wird die Zeile zu lang.
            $twin = @($script:Index.snapshots | Where-Object {
                $_.id -ne $letzter.id -and $_.kind -eq 'char' -and $_.char -eq $namen[0] -and
                $_.PSObject.Properties['contentHash'] -and $_.contentHash -eq $letzter.contentHash
            } | Sort-Object created | Select-Object -Last 1)
            if ($twin.Count -gt 0) {
                $hint += ((T ' - inhaltlich identisch mit der Sicherung von {0}') -f (Format-Timestamp $twin[0].created))
            }
            Set-Status ((T "Snapshot von '{0}' angelegt ({1}){2}.") -f $namen[0], (Format-Size $letzter.sizeBytes), $hint)
        } else {
            Set-Status ((T '{0} Charaktere gesichert ({1}){2}.') -f $angelegt, (Format-Size $bytes), $hint)
        }
    } catch {
        Set-Status ((T '{0} Charaktere gesichert ({1}){2}.') -f $angelegt, (Format-Size $bytes), '')
    }

    if ($fehler.Count -gt 0) {
        [void][System.Windows.MessageBox]::Show(
            ((T 'Bei {0} Charakter(en) hat es nicht geklappt:') -f $fehler.Count) + "`n`n" + [string]::Join([Environment]::NewLine, $fehler),
            $script:AppName, 'OK', 'Warning')
    }
})

$win.FindName('BtnSnapFull').Add_Click({
    # Sammelaktion: vorher zeigen, wie viel gleich angefasst wird.
    $all = @(Get-ChildItem -LiteralPath $script:Config.SavePath -File -ErrorAction SilentlyContinue |
             Where-Object { $script:ExcludedExtensions -notcontains $_.Extension.ToLowerInvariant() })
    if ($all.Count -eq 0) {
        [void][System.Windows.MessageBox]::Show((T 'Im Spielstand-Ordner wurden keine Dateien gefunden.'), $script:AppName, 'OK', 'Information')
        return
    }
    $raw = ($all | Measure-Object Length -Sum).Sum
    $ans = [System.Windows.MessageBox]::Show(
        ((T 'Den kompletten Spielstand-Ordner sichern?') + "`n`n" + ((T '{0} Dateien, {1} unkomprimiert.') -f $all.Count, (Format-Size $raw)) + "`n`n" + (T 'Das umfasst alle Charaktere, den Shared Stash und die Einstellungen.')),
        (T 'Alles sichern'), 'YesNo', 'Question')
    if ($ans -ne 'Yes') { Set-Status (T 'Sicherung des kompletten Ordners abgebrochen.'); return }

    try {
        $rec = New-Snapshot -Kind full
        Update-All
        $hint = if ($rec.d2rRunning) { T " - D2R lief dabei, Stand ggf. nicht taufrisch (Tag 'spiel-lief')" } else { '' }
        Set-Status ((T 'Kompletter Ordner gesichert ({0} Dateien, {1}){2}.') -f $rec.fileCount, (Format-Size $rec.sizeBytes), $hint)
    } catch {
        [void][System.Windows.MessageBox]::Show(((T 'Sichern fehlgeschlagen:') + "`n`n" + $_.Exception.Message), $script:AppName, 'OK', 'Error')
    }
})

$win.FindName('BtnRestore').Add_Click({
    $rec = Get-SelectedSnapshotRecord
    if (-not $rec) {
        [void][System.Windows.MessageBox]::Show((T 'Bitte einen Snapshot auswählen.'), $script:AppName, 'OK', 'Information')
        return
    }
    $opt = Show-RestoreDialog $rec
    if (-not $opt) { return }
    try {
        $files = Restore-Snapshot -Snapshot $rec -TargetName $opt.TargetName `
                    -RestoreStash:$opt.RestoreStash -SkipSafetyBackup:(-not $opt.Safety)
        Update-All
        $as = if ($opt.TargetName -and $opt.TargetName -ne $rec.char) { " als '$($opt.TargetName)'" } else { '' }
        Set-Status ((T 'Wiederhergestellt{0} - {1} Datei(en).') -f $as, $files.Count)
        [void][System.Windows.MessageBox]::Show(
            ((T "Wiederherstellung abgeschlossen{0}.`n`n{1} Datei(en) geschrieben.") -f $as, $files.Count), $script:AppName, 'OK', 'Information')
    } catch {
        [void][System.Windows.MessageBox]::Show(((T 'Wiederherstellen fehlgeschlagen:') + "`n`n" + $_.Exception.Message), $script:AppName, 'OK', 'Error')
    }
})

$win.FindName('BtnDelete').Add_Click({
    $rec = Get-SelectedSnapshotRecord
    if (-not $rec) {
        [void][System.Windows.MessageBox]::Show((T 'Bitte einen Snapshot auswählen.'), $script:AppName, 'OK', 'Information')
        return
    }
    $created = Format-Timestamp $rec.created 'dd.MM.yyyy HH:mm'
    $what = if ($rec.kind -eq 'full') { T 'Kompletter Ordner' } else { (T 'Charakter') + " '$($rec.char)'" }
    $ans = [System.Windows.MessageBox]::Show(
        ((T 'Snapshot endgültig löschen?') + "`n`n$what " + $created + "`n" + (T 'Label:') + " $($rec.label)`n`n" + (T 'Die Spielstände selbst bleiben unberührt.')),
        (T 'Snapshot löschen'), 'YesNo', 'Warning')
    if ($ans -ne 'Yes') { return }
    try {
        Remove-Snapshot $rec
        Clear-Details
        Update-All
        Set-Status (T 'Snapshot gelöscht.')
    } catch {
        [void][System.Windows.MessageBox]::Show(((T 'Löschen fehlgeschlagen:') + "`n`n" + $_.Exception.Message), $script:AppName, 'OK', 'Error')
    }
})

$win.FindName('BtnSaveMeta').Add_Click({
    $rec = Get-SelectedSnapshotRecord
    if (-not $rec) { return }
    $rec.label = $TxtLabel.Text
    $rec.note  = $TxtNote.Text
    $rec.tags  = @($TxtTags.Text -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    try {
        Export-Index
        Write-SnapshotInfo $rec   # _INFO.txt in der Sicherung mitziehen
        Update-TagFilter
        Update-SnapshotGrid
        Set-Status (T 'Label, Tags und Notiz gespeichert.')
    } catch {
        [void][System.Windows.MessageBox]::Show(((T 'Speichern fehlgeschlagen:') + "`n`n" + $_.Exception.Message), $script:AppName, 'OK', 'Error')
    }
})

$win.FindName('BtnOpenSave').Add_Click({
    if (Test-Path -LiteralPath $script:Config.SavePath) { Start-Process explorer.exe $script:Config.SavePath }
})

$win.FindName('BtnOpenBackup').Add_Click({
    if ($script:Config.BackupPath -and (Test-Path -LiteralPath $script:Config.BackupPath)) {
        Start-Process explorer.exe $script:Config.BackupPath
    }
})

$win.FindName('BtnSettings').Add_Click({ [void](Show-SettingsDialog) })

$win.FindName('BtnExit').Add_Click({ $win.Close() })

# Versionsnummer in den Fenstertitel. Nach dem Laden gesetzt, damit sie nicht
# durch die Übersetzung des XAML läuft.
$win.Title = "$script:AppName $script:AppVersion"
$win.FindName('TxtAppName').Text  = "$script:AppName $script:AppVersion"
$win.FindName('TxtAppClaim').Text = T 'Sichert lokale Charaktere und spielt sie zurück'

# Der Knopf zeigt immer die Sprache, in die gewechselt wird.
$win.FindName('BtnLang').Content = if ($script:Config.Language -eq 'en') { 'DE' } else { 'EN' }
$win.FindName('BtnLang').Add_Click({
    $script:Config.Language = if ($script:Config.Language -eq 'en') { 'de' } else { 'en' }
    Export-Config
    # Die Oberfläche wird beim Laden übersetzt - dafür muss sie neu aufgebaut
    # werden. Einfacher und verlässlicher als jedes Element einzeln umzubauen.
    $script:RestartRequested = $true
    $win.Close()
})

# --- Start -------------------------------------------------------------------

$win.Add_ContentRendered({
    Import-Index
    Update-All

    # Keine Ersteinrichtung mehr: der Backup-Ordner liegt standardmäßig neben
    # dem Programm. Nur wenn keine Charaktere gefunden werden, ist etwas zu tun.
    if ($GridChars.Items.Count -eq 0) {
        [void][System.Windows.MessageBox]::Show(
            (T 'Im Spielstand-Ordner wurden keine Charaktere gefunden:') + "`n`n" +
            $script:Config.SavePath + "`n`n" +
            (T 'Bitte den richtigen Ordner unter "Einstellungen" eintragen.'),
            $script:AppName, 'OK', 'Information')
    }
})

Import-Index
[void]$win.ShowDialog()

# Sprachwechsel: mit derselben PowerShell-Version neu starten, mit der wir laufen.
if ($script:RestartRequested -and $script:ScriptPath) {
    $exe = (Get-Process -Id $PID).Path
    Start-Process -FilePath $exe -ArgumentList @(
        '-NoProfile','-ExecutionPolicy','Bypass','-Sta','-WindowStyle','Hidden','-File',"`"$script:ScriptPath`""
    )
}
