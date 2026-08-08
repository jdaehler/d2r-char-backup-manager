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
$script:AppVersion = '1.3'

# Fassung des Haftungshinweises. Wird die Nummer erhöht, muss jeder Nutzer den
# Hinweis erneut bestätigen - dafür ist sie da. Nur erhöhen, wenn sich der Text
# inhaltlich ändert, nicht bei Tippfehlern.
$script:DisclaimerVersion = 1
$script:ScriptPath = $MyInvocation.MyCommand.Path
$script:ScriptDir  = Split-Path -Parent $script:ScriptPath
$script:ConfigPath = Join-Path $script:ScriptDir 'config.json'
$script:RestartRequested = $false
$script:SkipViewSave     = $false   # nach "Ansicht zurücksetzen" gesetzt

# Dateiendungen, die NICHT gesichert werden - weder beim einzelnen Charakter
# noch beim kompletten Ordner.
#
# .bak    D2R legt selbst zeitgestempelte *.bak an (z.B. "Assassin182056.bak") -
#         die haben ohnehin einen anderen Basisnamen und werden durch den
#         exakten Namensvergleich schon ausgeschlossen. Hier nur zur Sicherheit.
# .ctlo   Steuerung und Tastenbelegung von ONLINE-Charakteren. Der Charakter
# .keyo   selbst liegt auf Blizzards Servern, hier steht nur seine Belegung.
#         D2R räumt diese Dateien nie auf: auch für längst gelöschte Online-
#         Charaktere bleiben sie liegen, oft mit 0 Byte. Nach zwei Jahren waren
#         das im echten Betrieb 97 von 114 Dateien - Ballast, der eine Sicherung
#         unübersichtlich macht. Schlimmer beim Zurückspielen: das Wieder-
#         herstellen eines kompletten Ordners würde die Belegung sämtlicher
#         Online-Charaktere auf den Stand von damals zurückdrehen, obwohl nur
#         ein lokaler Charakter gemeint war.
$script:ExcludedExtensions = @('.bak', '.ctlo', '.keyo')

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
        View        = $null   # Fenstergröße, Spaltenbreiten, Ausblenden-Haken
        # Bestätigter Haftungshinweis. Bewusst NICHT Teil von View: "Ansicht
        # zurücksetzen" darf die Bestätigung nicht löschen, sonst stünde der
        # Hinweis nach jedem Zurücksetzen wieder da.
        Disclaimer  = $null
    }
}

# Ansichtseinstellungen: alles, was sich das Programm nebenbei merkt, ohne dass
# man es in den Einstellungen einträgt. Genau das - und nur das - setzt der Knopf
# "Ansicht zurücksetzen" wieder auf Auslieferungszustand; Pfade und Sprache
# bleiben unberührt.
#
# Die Fenster*position* wird bewusst NICHT gemerkt: zieht man einen zweiten
# Monitor ab, startete das Fenster sonst außerhalb des sichtbaren Bereichs - und
# damit wäre ausgerechnet der Knopf unerreichbar, der das wieder geradezieht.
function New-DefaultView {
    [pscustomobject]@{
        WindowWidth  = $null
        WindowHeight = $null
        LeftWidth    = $null   # Breite der linken Hälfte (Splitter)
        ColsChars    = $null   # Spaltenbreiten der Charakterliste
        ColsSnaps    = $null   # Spaltenbreiten der Snapshot-Liste
        HideAuto     = $false
        HidePark     = $false
        TrashFilter  = 0
        OnlySelected = $false
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
            # Feld für Feld übernehmen statt den ganzen Block: eine ältere oder
            # von Hand verbogene config.json soll keine unbekannten Felder
            # einschleusen und keine fehlenden verursachen.
            if ($raw.PSObject.Properties['View'] -and $raw.View) {
                $view = New-DefaultView
                foreach ($p in $raw.View.PSObject.Properties) {
                    if ($view.PSObject.Properties[$p.Name]) { $view.($p.Name) = $p.Value }
                }
                $cfg.View = $view
            }
            if ($raw.PSObject.Properties['Disclaimer'] -and $raw.Disclaimer) {
                $cfg.Disclaimer = $raw.Disclaimer
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

# Datumsformat je Sprache. Deutsch bleibt 04.08.2026, Englisch bekommt
# 2026-08-04 - also ISO statt 08/04/2026, weil die amerikanische und die britische
# Schreibweise Tag und Monat vertauschen und man einem Datum nicht ansieht, welche
# gemeint ist.
#
# ACHTUNG: Diese Zeichenketten dienen nur der Anzeige. Sortiert wird niemals nach
# ihnen, sondern nach den typfesten Feldern LastPlayedSort, SortKey und SizeSort -
# sonst stuende "03.01.2019" zwischen den 2026ern.
function Get-DateFormat {
    param([switch]$WithSeconds)
    if ($script:Config -and $script:Config.Language -eq 'en') {
        if ($WithSeconds) { 'yyyy-MM-dd HH:mm:ss' } else { 'yyyy-MM-dd HH:mm' }
    } else {
        if ($WithSeconds) { 'dd.MM.yyyy HH:mm:ss' } else { 'dd.MM.yyyy HH:mm' }
    }
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

# Ein Listeneintrag, egal ob der Charakter im Spielstand-Ordner liegt oder in
# einem Projektordner geparkt ist. $Project leer bedeutet aktiv.
function New-CharacterRecord {
    param([object]$Save, [object[]]$Files = @(), [string]$Project = '')

    $name  = $Save.BaseName
    $info  = Get-D2SInfo $Save.FullName
    $snaps = @($script:Index.snapshots | Where-Object { $_.kind -eq 'char' -and $_.char -eq $name })

    [pscustomobject]@{
        Name          = $name
        ClassName     = if ($info.Valid) { $info.ClassName } else { '?' }
        Level         = if ($info.Valid) { $info.Level } else { 0 }
        Mode          = if (-not $info.Valid) { '?' } elseif ($info.Hardcore) { 'Hardcore' } else { 'Softcore' }
        LastPlayed    = $info.LastPlayed
        # Fester Typ zum Sortieren - $null und DateTime gemischt lässt WPF stolpern.
        LastPlayedSort = if ($info.LastPlayed) { $info.LastPlayed } else { [datetime]::MinValue }
        LastPlayedStr = if ($info.LastPlayed) { $info.LastPlayed.ToString((Get-DateFormat)) } else { '' }
        FileCount     = @($Files).Count
        SnapCount     = $snaps.Count
        Version       = $info.Version
        Hardcore      = $info.Hardcore
        Project       = $Project
        Parked        = [bool]$Project
        # Was in der Spalte steht: geparkte Charaktere zeigen ihr Projekt, aktive
        # bleiben leer - so sticht das Weggeräumte hervor statt umgekehrt.
        ProjectStr    = $Project
    }
}

function Get-Characters {
    if (-not (Test-Path -LiteralPath $script:Config.SavePath)) { return @() }

    $result = @()
    $saves  = @(Get-ChildItem -LiteralPath $script:Config.SavePath -File -Filter '*.d2s' -ErrorAction SilentlyContinue)

    foreach ($save in $saves) {
        $result += New-CharacterRecord -Save $save -Files (Get-CharacterFiles $save.BaseName)
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
# Eigener Papierkorb, ausdrücklich nicht der von Windows: aus dem legt ein
# "Wiederherstellen" im Explorer die Dateien direkt an den Ursprungsort zurück,
# der Charakter stünde also wieder in der D2R-Auswahl, ohne dass dieses Programm
# davon weiß. Er liegt neben den Sicherungen und nicht im Spielstand-Ordner -
# so bleibt der Save-Ordner sauber und der Papierkorb wandert beim Sichern des
# Backup-Ordners von selbst mit.
function Get-TrashDir { Join-Path $script:Config.BackupPath '_Papierkorb' }

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

    # Ein Papierkorb-Eintrag ist im Aufbau ein Charakter-Snapshot - nur dass hier
    # die Originaldateien liegen und nicht eine Kopie davon.
    $istPapierkorb = ($Record.kind -eq 'trash')

    if ($Record.kind -ne 'full') {
        $z += Zeile 'Charakter' $Record.char
        $z += Zeile 'Klasse'    $Record.className
        $z += Zeile 'Level'     $Record.level
        $z += Zeile 'Modus'     $(if ($Record.hardcore) { 'Hardcore' } else { 'Softcore' })
    } else {
        $z += Zeile 'Typ' (T 'Kompletter Ordner')
    }
    if ($istPapierkorb) {
        $z += Zeile 'Gelöscht am' (Format-Timestamp $Record.created)
        $z += ''
        $z += (T 'Dieser Charakter wurde gelöscht und liegt hier im Papierkorb.')
        $z += (T 'Die Dateien in diesem Ordner sind die Originale - keine Kopie.')
        $z += (T 'Zusätzlich wurde vor dem Löschen eine Sicherung angelegt; die')
        $z += (T 'bleibt auch dann bestehen, wenn der Papierkorb geleert wird.')
        $z += ''
    } else {
        $z += Zeile 'Gesichert am' (Format-Timestamp $Record.created)
    }
    if ($Record.label) { $z += Zeile 'Label' $Record.label }
    if (@($Record.tags).Count -gt 0) { $z += Zeile 'Tags' (@($Record.tags) -join ', ') }
    if ($Record.note)  { $z += Zeile 'Notiz' (($Record.note -split '\r?\n') -join ' / ') }
    $z += Zeile 'Quelle' $script:Config.SavePath
    if ($Record.d2rRunning) { $z += Zeile 'Hinweis' (T 'D2R lief beim Sichern - Stand ggf. nicht taufrisch') }

    $z += ''
    $z += (T 'VON HAND WIEDERHERSTELLEN')
    $z += '-' * 60
    $z += (T '1. D2R beenden.')
    if ($Record.kind -ne 'full') {
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
        $z += (T '   Achtung: das betrifft sämtliche lokalen Charaktere.')
        $z += (T '   Online-Charaktere sind nicht dabei - sie liegen bei Blizzard')
        $z += (T '   und bleiben von dieser Sicherung unberührt.')
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
        (T '    Eine Sicherung des kompletten Spielstand-Ordners. Ohne die'),
        (T '    Dateien der Online-Charaktere (*.ctlo, *.keyo) - die Charaktere'),
        (T '    selbst liegen bei Blizzard, hier stünde nur ihre Tastenbelegung.'),
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
    # Belegte Regel, am 08.08.2026 in der offiziellen Blizzard-Spielhilfe
    # nachgeschlagen (Arreat Summit) und gegen den echten Bestand geprüft:
    # 2-15 Zeichen, nur Buchstaben A-Z, dazu höchstens ein "_" oder "-", und
    # das weder als erstes noch als letztes Zeichen. Keine Ziffern, keine
    # Leerzeichen. Siehe ENTWICKLUNG.md, Abschnitt "Namensregeln".
    #
    # Wird hart durchgesetzt, nicht als Warnung: einen Namen, den D2R nicht
    # annimmt, schriebe das Programm zwar anstandslos auf die Platte, aber der
    # Charakter fehlte danach in der Charakterauswahl des Spiels.
    #
    # Gemeldet wird jeder Verstoß einzeln - eine Sammelmeldung "Name ungültig"
    # lässt den Benutzer raten, woran es lag.
    if ([string]::IsNullOrWhiteSpace($Name)) { return (T 'Der Name darf nicht leer sein.') }
    if ($Name.Length -lt 2 -or $Name.Length -gt 15) { return (T 'Der Name muss zwischen 2 und 15 Zeichen lang sein.') }
    if ($Name -notmatch '^[A-Za-z_-]+$') { return (T 'Erlaubt sind nur Buchstaben (A-Z) sowie ein "_" oder "-" - keine Ziffern, keine Leerzeichen.') }
    if (@($Name.ToCharArray() | Where-Object { $_ -eq '_' -or $_ -eq '-' }).Count -gt 1) { return (T 'D2R erlaubt höchstens ein "_" oder "-" im Namen.') }
    if ($Name -match '^[_-]' -or $Name -match '[_-]$') { return (T 'Das "_" oder "-" darf nicht am Anfang oder Ende des Namens stehen.') }
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

    # Ein Papierkorb-Eintrag ist im Aufbau ein Charakter-Snapshot und wird hier
    # genauso behandelt - deshalb "nicht full" statt "gleich char". Damit lässt
    # sich Gelöschtes über denselben Weg zurückholen, auch unter anderem Namen.
    $istChar = ($Snapshot.kind -ne 'full')

    # Sicherheitskopie des aktuellen Zustands, bevor irgendetwas überschrieben wird.
    if (-not $SkipSafetyBackup) {
        if ($istChar) {
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
            if ($istChar -and $TargetName) {
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
# Charaktere parken
# ---------------------------------------------------------------------------
# D2R listet in der Charakterauswahl nur die .d2s-Dateien, die unmittelbar im
# Spielstand-Ordner liegen; Unterordner sieht das Spiel nicht. Genau darauf
# beruht das Parken: Der Dateisatz eines Charakters wandert nach
# _Projekte\<Projekt>\ und verschwindet damit aus der Spielanzeige, ohne dass
# etwas gelöscht wird. Zurückholen ist derselbe Weg rückwärts.
#
# Nachgewiesen am eigenen Spielstand-Ordner: dort liegen in den Altordnern
# Backup, BAK20250510 und Temp zusammen 38 weitere .d2s-Dateien - das Spiel
# zeigt trotzdem nur die 28 aus dem Wurzelverzeichnis.
#
# GEPARKT IST NICHT GESICHERT. Ein Snapshot ist eine Kopie; geht er verloren,
# bleibt das Original. Ein geparkter Charakter IST das Original, nur an einem
# anderen Ort. Deshalb legt Move-CharacterToProject vor jedem Parken zwingend
# einen Snapshot an - dafür gibt es bewusst keinen Schalter.
#
# "_Projekte" ist wie "Charaktere" und "SharedStash" ein fester Ordnername und
# wird NICHT übersetzt - sonst entstünden beim Sprachwechsel zwei Bäume.
#
# Der Shared Stash wandert nie mit: er gilt für alle Charaktere, nicht für
# einen. Get-CharacterFiles liefert ihn ohnehin nicht (sein Dateiname stimmt
# nie mit einem Charakternamen überein), .d2i wird beim Verschieben zusätzlich
# ausdrücklich übersprungen.

function Get-ProjectsDir { Join-Path $script:Config.SavePath '_Projekte' }

function Get-ProjectNames {
    $wurzel = Get-ProjectsDir
    if (-not (Test-Path -LiteralPath $wurzel)) { return @() }
    @(Get-ChildItem -LiteralPath $wurzel -Directory -ErrorAction SilentlyContinue |
      ForEach-Object { $_.Name } | Sort-Object)
}

function Test-ProjectName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return (T 'Der Projektname darf nicht leer sein.') }
    if ($Name -ne $Name.Trim()) { return (T 'Der Projektname darf nicht mit einem Leerzeichen beginnen oder enden.') }
    if ($Name.Length -gt 40) { return (T 'Der Projektname darf höchstens 40 Zeichen lang sein.') }
    if ($Name -eq '.' -or $Name -eq '..') { return (T 'Dieser Projektname ist nicht erlaubt.') }
    $ungueltig = [System.IO.Path]::GetInvalidFileNameChars()
    if (@($Name.ToCharArray() | Where-Object { $ungueltig -contains $_ }).Count -gt 0) {
        return (T 'Im Projektnamen sind \ / : * ? " < > | nicht erlaubt.')
    }
    ''
}

function Get-ParkedCharacterFiles {
    param([string]$Project, [string]$CharName)
    $ordner = Join-Path (Get-ProjectsDir) $Project
    if (-not (Test-Path -LiteralPath $ordner)) { return @() }
    @(Get-ChildItem -LiteralPath $ordner -File -ErrorAction SilentlyContinue | Where-Object {
        [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -eq $CharName -and
        $_.Extension.ToLowerInvariant() -ne '.d2i'
    })
}

function Get-ParkedCharacters {
    $wurzel = Get-ProjectsDir
    if (-not (Test-Path -LiteralPath $wurzel)) { return @() }

    $result = @()
    foreach ($projekt in (Get-ProjectNames)) {
        $ordner = Join-Path $wurzel $projekt
        foreach ($save in @(Get-ChildItem -LiteralPath $ordner -File -Filter '*.d2s' -ErrorAction SilentlyContinue)) {
            $result += New-CharacterRecord -Save $save `
                                           -Files (Get-ParkedCharacterFiles -Project $projekt -CharName $save.BaseName) `
                                           -Project $projekt
        }
    }
    @($result)
}

# Aktive und geparkte Charaktere in einer Liste - die Oberfläche zeigt beide,
# sonst verliert man aus den Augen, was man weggeräumt hat.
function Get-AllCharacters {
    @(@(Get-Characters) + @(Get-ParkedCharacters) | Sort-Object Name)
}

# Liegt schon ein Charakter dieses Namens irgendwo? Aktiv im Spielstand-Ordner
# oder geparkt in einem Projekt - beides muss gefunden werden, sonst kollidiert
# ein neuer Name unbemerkt mit einem weggeräumten Dateisatz, und spätestens beim
# Zurückholen stehen zwei Charaktere gleichen Namens gegeneinander.
#
# Rückgabe: Kind ist 'active', 'parked' oder '' (frei). Bewusst ein Objekt statt
# eines Textes - ein Projekt darf auch 'aktiv' heißen.
function Get-NameKollision {
    param([string]$Name)

    if (@(Get-CharacterFiles $Name).Count -gt 0) {
        return [pscustomobject]@{ Kind = 'active'; Project = '' }
    }
    foreach ($p in (Get-ProjectNames)) {
        if (@(Get-ParkedCharacterFiles -Project $p -CharName $Name).Count -gt 0) {
            return [pscustomobject]@{ Kind = 'parked'; Project = $p }
        }
    }
    [pscustomobject]@{ Kind = ''; Project = '' }
}

# Benennt alle Dateien eines Charakters um. In die Spielstanddatei selbst wird
# nicht eingegriffen - der Name steht nur im Dateinamen, siehe "Warum Umbenennen
# gefahrlos ist". Damit ist das hier ein reines Umbenennen von Dateien.
#
# Nur für aktive Charaktere. Ein geparkter müsste erst zurückgeholt werden, weil
# der Pflicht-Snapshot ihn sonst nicht erfasst - New-Snapshot sieht nur in den
# Spielstand-Ordner, nicht in die Projektordner (siehe "Offene Punkte").
function Rename-Character {
    param([string]$CharName, [string]$NewName)

    if (-not $CharName) { throw (T 'Kein Charakter angegeben.') }
    $NewName = "$NewName".Trim()

    $fehler = Test-D2RName $NewName
    if ($fehler) { throw $fehler }

    # -ceq beachtet Groß-/Kleinschreibung: wirklich derselbe Name ist ein
    # Denkfehler des Benutzers, eine andere Schreibweise dagegen eine legitime
    # Absicht ("jdbarb" soll "jdBarb" heißen).
    if ($NewName -ceq $CharName) { throw (T 'Der neue Name ist derselbe wie der alte.') }

    # Windows unterscheidet in Dateinamen keine Groß-/Kleinschreibung. Wer nur
    # die Schreibweise ändert, kollidiert deshalb mit sich selbst - dieser Fall
    # wird von der Kollisionsprüfung ausgenommen und weiter unten über einen
    # Zwischennamen umbenannt.
    $nurSchreibweise = ($NewName -eq $CharName)

    if (Test-D2RRunning) { throw (T 'D2R läuft. Zum Umbenennen muss das Spiel beendet sein.') }

    if (-not $nurSchreibweise) {
        $kol = Get-NameKollision $NewName
        switch ($kol.Kind) {
            'active' { throw ((T 'Es gibt bereits einen Charakter namens {0}.') -f $NewName) }
            'parked' { throw ((T 'Im Projekt {0} ist bereits ein Charakter namens {1} geparkt.') -f $kol.Project, $NewName) }
        }
    }

    $dateien = @(Get-CharacterFiles $CharName | Where-Object { $_.Extension.ToLowerInvariant() -ne '.d2i' })
    if ($dateien.Count -eq 0) { throw ((T 'Zu diesem Charakter wurden keine Dateien gefunden:') + " $CharName") }

    # Pflicht-Snapshot, bevor die erste Datei angefasst wird. Nicht abschaltbar -
    # das ist die Begründung dafür, dass diese Aktion überhaupt in einem
    # Sicherungsprogramm sitzt.
    $snap = New-Snapshot -Kind char -CharName $CharName `
                         -Label (T 'Automatisch vor dem Umbenennen') -Tags @('auto','umbenannt') -Automatic
    if (-not $snap) { throw (T 'Die Sicherung vor dem Umbenennen ist fehlgeschlagen - es wurde nichts umbenannt.') }

    $ordner   = $script:Config.SavePath
    $umbenannt = @()

    # Bei reiner Schreibweisenänderung führt der Weg über einen Zwischennamen,
    # sonst lehnt Windows das Umbenennen als "Ziel existiert bereits" ab. Der
    # Zwischenname ist ein reiner Dateiname und muss keine D2R-Regel erfüllen -
    # er existiert nur für den Bruchteil einer Sekunde.
    $zwischen = if ($nurSchreibweise) { "$NewName~tmp$([guid]::NewGuid().ToString('N').Substring(0,6))" } else { '' }

    foreach ($f in $dateien) {
        $ziel = $NewName + $f.Extension
        if ($nurSchreibweise) {
            $tmp = $zwischen + $f.Extension
            Move-Item -LiteralPath $f.FullName -Destination (Join-Path $ordner $tmp) -Force
            Move-Item -LiteralPath (Join-Path $ordner $tmp) -Destination (Join-Path $ordner $ziel) -Force
        } else {
            Move-Item -LiteralPath $f.FullName -Destination (Join-Path $ordner $ziel) -Force
        }
        $umbenannt += $ziel
    }

    [pscustomobject]@{
        OldName          = $CharName
        NewName          = $NewName
        Files            = @($umbenannt)
        Snapshot         = $snap
        D2RStartedDuring = (Test-D2RRunning)
    }
}

# Kopiert den Dateisatz eines Charakters unter neuem Namen. Der Weg führt über
# einen Snapshot, der sofort unter dem neuen Namen zurückgeschrieben wird: so ist
# die Sicherung nicht Beiwerk, sondern der Mechanismus selbst, und es entsteht
# kein zweiter Kopierpfad neben dem längst erprobten Restore-Snapshot.
#
# Der Shared Stash wird nicht mitkopiert - er gehört allen Charakteren gemeinsam
# und existiert genau einmal. Das Original bleibt unangetastet.
function Copy-Character {
    param([string]$CharName, [string]$NewName)

    if (-not $CharName) { throw (T 'Kein Charakter angegeben.') }
    $NewName = "$NewName".Trim()

    $fehler = Test-D2RName $NewName
    if ($fehler) { throw $fehler }

    # Anders als beim Umbenennen gibt es hier keinen Sonderfall für die
    # Schreibweise: für Windows wäre "jdbarb" dieselbe Datei wie "jdBarb", die
    # Kopie überschriebe also das Original. `-eq` vergleicht ohne Rücksicht auf
    # Groß-/Kleinschreibung und fängt genau das ab.
    if ($NewName -eq $CharName) {
        throw (T 'Die Kopie braucht einen anderen Namen als das Original - auch eine andere Schreibweise reicht Windows nicht.')
    }

    if (Test-D2RRunning) { throw (T 'D2R läuft. Zum Duplizieren muss das Spiel beendet sein.') }

    $kol = Get-NameKollision $NewName
    switch ($kol.Kind) {
        'active' { throw ((T 'Es gibt bereits einen Charakter namens {0}.') -f $NewName) }
        'parked' { throw ((T 'Im Projekt {0} ist bereits ein Charakter namens {1} geparkt.') -f $kol.Project, $NewName) }
    }

    $dateien = @(Get-CharacterFiles $CharName | Where-Object { $_.Extension.ToLowerInvariant() -ne '.d2i' })
    if ($dateien.Count -eq 0) { throw ((T 'Zu diesem Charakter wurden keine Dateien gefunden:') + " $CharName") }

    $snap = New-Snapshot -Kind char -CharName $CharName `
                         -Label (T 'Automatisch vor dem Duplizieren') -Tags @('auto','dupliziert') -Automatic
    if (-not $snap) { throw (T 'Die Sicherung vor dem Duplizieren ist fehlgeschlagen - es wurde nichts kopiert.') }

    # SkipSafetyBackup: Der Zielname ist eben nachweislich frei, es gibt also
    # nichts zu überschreiben und damit nichts zu sichern.
    $geschrieben = @(Restore-Snapshot -Snapshot $snap -TargetName $NewName -SkipSafetyBackup)

    [pscustomobject]@{
        Source           = $CharName
        Copy             = $NewName
        Files            = @($geschrieben)
        Snapshot         = $snap
        D2RStartedDuring = (Test-D2RRunning)
    }
}

# Löscht einen Charakter, indem sein Dateisatz in den Papierkorb wandert. Damit
# ist es sicherer als das Löschen in D2R selbst, das endgültig ist und ohne
# Sicherung auskommt.
#
# Zwei Netze übereinander, mit Absicht: der Pflicht-Snapshot ist eine Kopie und
# bleibt auch dann liegen, wenn der Papierkorb geleert wird - der
# Papierkorb-Eintrag enthält die Originale und ist der schnelle Rückweg.
#
# Wer einen Charakter nur aus der Charakterauswahl haben will, parkt ihn. Das
# hier ist für "soll wirklich weg".
function Remove-CharacterToTrash {
    param([string]$CharName)

    if (-not $CharName) { throw (T 'Kein Charakter angegeben.') }
    if (Test-D2RRunning) { throw (T 'D2R läuft. Zum Löschen muss das Spiel beendet sein.') }

    # Ohne erreichbaren Backup-Ordner gäbe es weder Sicherung noch Papierkorb.
    # Dann wird gar nicht erst angefangen, statt auf halbem Weg zu scheitern.
    if (-not $script:Config.BackupPath -or -not (Test-Path -LiteralPath $script:Config.BackupPath)) {
        throw (T 'Der Backup-Ordner ist nicht erreichbar. Ohne ihn gibt es weder Sicherung noch Papierkorb, deshalb wird nicht gelöscht.')
    }

    $dateien = @(Get-CharacterFiles $CharName | Where-Object { $_.Extension.ToLowerInvariant() -ne '.d2i' })
    if ($dateien.Count -eq 0) { throw ((T 'Zu diesem Charakter wurden keine Dateien gefunden:') + " $CharName") }

    $snap = New-Snapshot -Kind char -CharName $CharName `
                         -Label (T 'Automatisch vor dem Löschen') -Tags @('auto','geloescht') -Automatic
    if (-not $snap) { throw (T 'Die Sicherung vor dem Löschen ist fehlgeschlagen - es wurde nichts gelöscht.') }

    # Zeitstempel muss in den Ordnernamen: derselbe Charakter kann mehrfach
    # gelöscht werden, etwa nachdem er zwischendurch zurückgeholt wurde.
    $stempel = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $wurzel  = Get-TrashDir
    if (-not (Test-Path -LiteralPath $wurzel)) { New-Item -ItemType Directory -Path $wurzel -Force | Out-Null }
    $ordner = New-SnapshotOrdner -Basis $wurzel -Name (ConvertTo-SichererName ("{0}_{1}" -f $stempel, $CharName))

    # Erst kopieren, prüfen, dann löschen - nie umgekehrt. Liegt der
    # Backup-Ordner auf einem anderen Laufwerk, ist das Verschieben ohnehin ein
    # Kopieren mit anschließendem Löschen; so ist die Reihenfolge in beiden
    # Fällen dieselbe und ein Abbruch mittendrin kostet keine Datei.
    $kopiert = @()
    foreach ($f in $dateien) {
        $ziel = Join-Path $ordner $f.Name
        Copy-Item -LiteralPath $f.FullName -Destination $ziel -Force
        if (-not (Test-Path -LiteralPath $ziel) -or (Get-Item -LiteralPath $ziel).Length -ne $f.Length) {
            throw ((T 'Eine Datei ließ sich nicht in den Papierkorb kopieren, es wurde nichts gelöscht:') + " $($f.Name)")
        }
        $kopiert += $f
    }

    $entfernt = @()
    foreach ($f in $kopiert) {
        Remove-Item -LiteralPath $f.FullName -Force
        $entfernt += $f.Name
    }

    $basisPfad = $script:Config.BackupPath.TrimEnd('\')
    $groesse   = (Get-ChildItem -LiteralPath $ordner -Recurse -File | Measure-Object Length -Sum).Sum

    # Als eigene Art im Index geführt, aber mit demselben Aufbau wie ein
    # Snapshot: dadurch holt Restore-Snapshot den Eintrag ohne Sonderweg zurück,
    # auch unter anderem Namen.
    $record = [pscustomobject]@{
        id            = '{0}-{1:x4}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), (Get-Random -Maximum 65535)
        kind          = 'trash'
        automatic     = $false
        char          = $CharName
        label         = (T 'Gelöscht')
        tags          = @('papierkorb')
        note          = ''
        created       = (Get-Date).ToString('o')
        pfad          = $ordner.Substring($basisPfad.Length + 1)
        sizeBytes     = [long]$groesse
        fileCount     = $entfernt.Count
        includesStash = $false
        d2rRunning    = (Test-D2RRunning)
        contentHash   = ''
        className     = $snap.className
        level         = $snap.level
        hardcore      = $snap.hardcore
        snapshotId    = $snap.id      # die Kopie, die auch ein geleerter Papierkorb nicht mitnimmt
    }

    $script:Index.snapshots += $record
    Export-Index
    Write-SnapshotInfo $record

    [pscustomobject]@{
        Char             = $CharName
        Files            = @($entfernt)
        Snapshot         = $snap
        Trash            = $record
        D2RStartedDuring = (Test-D2RRunning)
    }
}

# Zum Leeren des Papierkorbs gibt es bewusst keine eigene Funktion mehr: man
# filtert die Liste auf "nur Papierkorb", markiert alles und drückt Löschen.
# Das ist derselbe Weg wie bei jedem anderen Eintrag, und `Remove-Snapshot`
# räumt die leere `_Papierkorb`-Wurzel ohnehin mit weg.
#
# Es bleibt dabei: nichts wird von selbst aufgeräumt, es gibt keine Altersgrenze.

function Move-CharacterToProject {
    param([string]$CharName, [string]$Project)

    if (-not $CharName) { throw (T 'Kein Charakter angegeben.') }
    $fehler = Test-ProjectName $Project
    if ($fehler) { throw $fehler }
    # Blockierend, nicht nur warnend: D2R hält die Spielstanddateien offen und
    # schreibt sie beim Beenden zurück. Wer währenddessen verschiebt, riskiert
    # einen halb bewegten Dateisatz.
    if (Test-D2RRunning) { throw (T 'D2R läuft. Zum Parken muss das Spiel beendet sein.') }

    $dateien = @(Get-CharacterFiles $CharName | Where-Object { $_.Extension.ToLowerInvariant() -ne '.d2i' })
    if ($dateien.Count -eq 0) { throw ((T 'Zu diesem Charakter wurden keine Dateien gefunden:') + " $CharName") }

    $ordner = Join-Path (Get-ProjectsDir) $Project
    if (Test-Path -LiteralPath $ordner) {
        $belegt = @(Get-ChildItem -LiteralPath $ordner -File -ErrorAction SilentlyContinue | Where-Object {
            [System.IO.Path]::GetFileNameWithoutExtension($_.Name) -eq $CharName
        })
        if ($belegt.Count -gt 0) {
            throw ((T 'In diesem Projekt liegt bereits ein Charakter dieses Namens:') + " $CharName")
        }
    }

    # Pflicht-Snapshot, bevor die erste Datei bewegt wird. Ein geparkter
    # Charakter ist das Original - ohne Sicherung wäre das Parken die einzige
    # Kopie, und ein versehentlich gelöschter Projektordner wäre endgültig.
    $snap = New-Snapshot -Kind char -CharName $CharName `
                         -Label (T 'Automatisch vor dem Parken') -Tags @('auto','geparkt') -Automatic
    if (-not $snap) { throw (T 'Die Sicherung vor dem Parken ist fehlgeschlagen - es wurde nichts verschoben.') }

    if (-not (Test-Path -LiteralPath $ordner)) { New-Item -ItemType Directory -Path $ordner -Force | Out-Null }

    $verschoben = @()
    foreach ($f in $dateien) {
        Move-Item -LiteralPath $f.FullName -Destination (Join-Path $ordner $f.Name) -Force
        $verschoben += $f.Name
    }

    Write-ProjectInfo $ordner

    [pscustomobject]@{
        Char             = $CharName
        Project          = $Project
        Files            = @($verschoben)
        Snapshot         = $snap
        # Wurde D2R zwischen der Prüfung und dem letzten Move gestartet, ist der
        # Dateisatz zwar vollständig bewegt, das Spiel hat den Charakter aber
        # möglicherweise noch im Zugriff. Das wird gemeldet statt verschwiegen.
        D2RStartedDuring = (Test-D2RRunning)
    }
}

function Restore-CharacterFromProject {
    param([string]$Project, [string]$CharName, [string]$TargetName = '')

    if (Test-D2RRunning) { throw (T 'D2R läuft. Zum Zurückholen muss das Spiel beendet sein.') }

    $dateien = @(Get-ParkedCharacterFiles -Project $Project -CharName $CharName)
    if ($dateien.Count -eq 0) { throw ((T 'Im Projekt wurde kein solcher Charakter gefunden:') + " $CharName") }
    if (-not (Test-Path -LiteralPath $script:Config.SavePath)) {
        throw ((T 'Der Spielstand-Ordner existiert nicht:') + " $($script:Config.SavePath)")
    }

    $ziel = if ($TargetName) { $TargetName } else { $CharName }
    if (@(Get-CharacterFiles $ziel).Count -gt 0) {
        throw ((T 'Im Spielstand-Ordner gibt es bereits einen Charakter dieses Namens:') + " $ziel")
    }

    $zurueck = @()
    foreach ($f in $dateien) {
        # Der Name steckt nur im Dateinamen - Endung bleibt, Basisname wird ersetzt.
        $name = $ziel + $f.Extension
        Move-Item -LiteralPath $f.FullName -Destination (Join-Path $script:Config.SavePath $name) -Force
        $zurueck += $name
    }

    # War es der letzte Charakter des Projekts, bleibt sonst ein Ordner mit
    # nichts als _INFO.txt stehen.
    $ordner = Join-Path (Get-ProjectsDir) $Project
    $rest = @(Get-ChildItem -LiteralPath $ordner -File -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -ne '_INFO.txt' })
    if ($rest.Count -eq 0) {
        Remove-Item -LiteralPath $ordner -Recurse -Force
        $wurzel = Get-ProjectsDir
        if ((Test-Path -LiteralPath $wurzel) -and
            @(Get-ChildItem -LiteralPath $wurzel -Force).Count -eq 0) {
            Remove-Item -LiteralPath $wurzel -Force
        }
    } else {
        Write-ProjectInfo $ordner
    }

    [pscustomobject]@{
        Char             = $ziel
        Project          = $Project
        Files            = @($zurueck)
        D2RStartedDuring = (Test-D2RRunning)
    }
}

function Write-ProjectInfo {
    param([string]$Ordner)
    if (-not $Ordner -or -not (Test-Path -LiteralPath $Ordner)) { return }

    $projekt = Split-Path -Leaf $Ordner
    $saves   = @(Get-ChildItem -LiteralPath $Ordner -File -Filter '*.d2s' -ErrorAction SilentlyContinue)

    $z = @("$script:AppName $script:AppVersion", '')
    $z += '{0,-16}{1}' -f ((T 'Projekt') + ':'), $projekt
    $z += '{0,-16}{1}' -f ((T 'Geparkt am') + ':'), (Get-Date).ToString((Get-DateFormat))
    $z += '{0,-16}{1}' -f ((T 'Charaktere') + ':'), $saves.Count
    $z += ''
    foreach ($s in $saves) {
        $i = Get-D2SInfo $s.FullName
        $z += '  {0,-18}{1}' -f $s.BaseName, $(if ($i.Valid) {
            'Lvl {0} {1}{2}' -f $i.Level, $i.ClassName, $(if ($i.Hardcore) { ' (Hardcore)' } else { '' })
        } else { '?' })
    }

    $z += ''
    $z += (T 'WAS IST DAS HIER?')
    $z += '-' * 60
    $z += (T 'Diese Charaktere sind geparkt: sie liegen noch da, tauchen aber in')
    $z += (T 'der Charakterauswahl von D2R nicht mehr auf. Das Spiel sieht nur')
    $z += (T 'Dateien, die unmittelbar im Spielstand-Ordner liegen - alles in')
    $z += (T 'Unterordnern ist für D2R unsichtbar.')
    $z += ''
    $z += (T 'ACHTUNG: Das hier sind die Charaktere selbst, keine Sicherungen.')
    $z += (T 'Wird dieser Ordner gelöscht, sind sie weg. Beim Parken hat das')
    $z += (T 'Programm allerdings von jedem eine Sicherung angelegt.')
    $z += ''
    $z += (T 'VON HAND ZURÜCKHOLEN')
    $z += '-' * 60
    $z += (T '1. D2R beenden.')
    $z += (T '2. Die Dateien eines Charakters (ohne _INFO.txt) aus diesem Ordner')
    $z += (T '   in den Spielstand-Ordner verschieben:')
    $z += "   $($script:Config.SavePath)"
    $z += (T '3. D2R starten - der Charakter steht wieder in der Auswahl.')

    [System.IO.File]::WriteAllLines((Join-Path $Ordner '_INFO.txt'), $z, (New-Object System.Text.UTF8Encoding($true)))
}

# ---------------------------------------------------------------------------
# XAML
# ---------------------------------------------------------------------------

$MainXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="D2R Char Backup Manager" Height="800" Width="1520"
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
        <!-- Geparkte Charaktere blass und kursiv: sie sind da, aber im Spiel
             nicht sichtbar. Steht VOR dem Auswahl-Trigger, damit eine Auswahl
             die Farbe wieder überschreibt - sonst verschwindet die Markierung. -->
        <DataTrigger Binding="{Binding Parked}" Value="True">
          <Setter Property="Foreground" Value="#8A8A8A"/>
          <Setter Property="FontStyle"  Value="Italic"/>
        </DataTrigger>
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

    <!-- Ohne diesen Style zieht WPF jeden Tooltip zu einer einzigen Zeile
         auseinander, quer über den halben Bildschirm. Gilt ohne x:Key für alle
         Tooltips im Fenster, auch die schon vorhandenen. -->
    <Style TargetType="ToolTip">
      <Setter Property="MaxWidth" Value="320"/>
      <Setter Property="ContentTemplate">
        <Setter.Value>
          <DataTemplate>
            <TextBlock Text="{Binding}" TextWrapping="Wrap"/>
          </DataTemplate>
        </Setter.Value>
      </Setter>
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
          <Button x:Name="BtnAbout"    Style="{StaticResource QuietButton}" ToolTip="Hinweis, Lizenz und Anleitung">Über</Button>
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
        <!-- 700: die Charakterliste hat mit der Projekt-Spalte sieben Spalten und
             braucht gemessene rund 650 px, sonst schiebt sich die letzte aus dem
             Bild. Die Knopfgruppen darüber sitzen in einem WrapPanel und legen
             sich bei Bedarf in eine zweite Zeile. -->
        <ColumnDefinition x:Name="ColLinks" Width="700" MinWidth="300"/>
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
        <WrapPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,6">
          <GroupBox Header="Charaktere sichern" Padding="8,4,8,6" Margin="0,0,10,4">
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

          <GroupBox Header="Kompletter Ordner" Padding="8,4,8,6" Margin="0,0,10,4">
            <Button x:Name="BtnSnapFull" Style="{StaticResource NormalButton}" Margin="0,0,0,4"
                    ToolTip="Sichert den kompletten Spielstand-Ordner in einem Stück: alle Charaktere, den Shared Stash, die Einstellungen und die Item-Filter.">Alles sichern</Button>
          </GroupBox>

          <!-- Parken bewegt echte Spielstände, deshalb eine eigene Gruppe und
               nicht zwischen den Sichern-Knöpfen. -->
          <GroupBox Header="Spielanzeige" Padding="8,4,8,6">
            <WrapPanel Orientation="Horizontal">
              <Button x:Name="BtnPark" Style="{StaticResource NormalButton}" Margin="0,0,6,4"
                      ToolTip="Verschiebt die markierten Charaktere in einen Projektordner. Sie verschwinden damit aus der Charakterauswahl von D2R, bleiben aber erhalten.">Parken...</Button>
              <Button x:Name="BtnUnpark" Style="{StaticResource NormalButton}" Margin="0,0,6,4"
                      ToolTip="Holt die markierten geparkten Charaktere zurück in den Spielstand-Ordner. Danach stehen sie wieder in der Charakterauswahl.">Zurückholen</Button>
              <Border Width="1" Background="#D0D0D0" Margin="4,2,10,6"/>
              <CheckBox x:Name="ChkHidePark" Content="Geparkte ausblenden" VerticalAlignment="Center" Margin="0,0,0,4"
                        ToolTip="Blendet geparkte Charaktere aus der Liste aus. Am Parken selbst ändert das nichts - nur an der Anzeige."/>
            </WrapPanel>
          </GroupBox>

          <!-- Aktionen am Charakter selbst. Symbolknopf mit Tooltip, kein
               zweiter Textknopf - links löst weiterhin nur "Markierte sichern"
               mit Text aus. Vor jeder dieser Aktionen wird gesichert. -->
          <GroupBox Header="Charakter" Padding="8,4,8,6" Margin="10,0,0,4">
            <WrapPanel Orientation="Horizontal">
              <Button x:Name="BtnRename" Style="{StaticResource IconButton}" Content="&#xE8AC;" Margin="0,0,6,4"
                      ToolTip="Umbenennen. Alle Dateien wandern mit, vorher wird gesichert. Level und Ausrüstung bleiben unberührt."/>
              <Button x:Name="BtnCopy" Style="{StaticResource IconButton}" Content="&#xE8C8;" Margin="0,0,6,4"
                      ToolTip="Kopie unter neuem Namen anlegen. Das Original bleibt stehen, ohne Shared Stash."/>
              <!-- Löschen steht hinter einem Trenner und ist rot: es ist die
                   einzige Aktion hier, die etwas wegnimmt. -->
              <Border Width="1" Background="#D0D0D0" Margin="4,2,10,6"/>
              <Button x:Name="BtnDeleteChar" Style="{StaticResource IconButton}" Content="&#xE74D;" Foreground="#B00020" Margin="0,0,0,4"
                      ToolTip="Löschen - in den Papierkorb des Programms, nicht sofort weg. Vorher wird gesichert. Nur aus der Spielauswahl nehmen? Dann parken."/>
            </WrapPanel>
          </GroupBox>
        </WrapPanel>

      <GroupBox Grid.Row="1" Header="Charaktere">
        <DataGrid x:Name="GridChars" AutoGenerateColumns="False" IsReadOnly="True"
                  RowStyle="{StaticResource AuswahlZeile}" CellStyle="{StaticResource AuswahlZelle}"
                  SelectionMode="Extended" HeadersVisibility="Column"
                  GridLinesVisibility="Horizontal" RowHeaderWidth="0" Margin="2">
          <DataGrid.Columns>
            <DataGridTextColumn Header="Name"     Binding="{Binding Name}"          Width="*"  MinWidth="130"/>
            <DataGridTextColumn Header="Klasse"   Binding="{Binding ClassName}"     Width="110"/>
            <DataGridTextColumn Header="Lvl"      Binding="{Binding Level}"         Width="48"/>
            <DataGridTextColumn Header="Modus"    Binding="{Binding Mode}"          Width="78"/>
            <!-- SortMemberPath: sortiert nach dem echten Datum statt nach dem
                 formatierten Text, sonst landet 03.01.2019 zwischen 2026er Daten. -->
            <DataGridTextColumn Header="Zuletzt"  Binding="{Binding LastPlayedStr}" Width="118"
                                SortMemberPath="LastPlayedSort"/>
            <DataGridTextColumn Header="Snaps"    Binding="{Binding SnapCount}"     Width="62"/>
            <!-- Leer bei aktiven Charakteren: so sticht das Weggeräumte hervor. -->
            <DataGridTextColumn Header="Projekt"  Binding="{Binding ProjectStr}"    Width="110"/>
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

        <!-- Eine Gruppe, zwei Aktionen. Was passiert, entscheidet die Markierung
             in der Liste; die Filter darunter sind das Werkzeug, um die richtige
             Markierung hinzubekommen. Ein eigener Knopf "Papierkorb leeren"
             stand hier einmal daneben und war genau die Verdopplung, die man
             sich damit spart: Filter auf "nur Papierkorb", alles markieren,
             Löschen. -->
        <GroupBox Grid.Row="0" Header="Markierte Einträge" Padding="8,4,8,6" Margin="0,0,0,6">
          <WrapPanel Orientation="Horizontal">
            <Button x:Name="BtnRestore" Style="{StaticResource NormalButton}" Margin="0,0,6,4">Wiederherstellen...</Button>
            <Button x:Name="BtnDelete"  Style="{StaticResource DangerButton}" Margin="0,0,6,4" MinWidth="150">Löschen</Button>
            <Border Width="1" Background="#D0D0D0" Margin="4,2,10,6"/>
            <Button x:Name="BtnOpenBackup" Style="{StaticResource IconButton}" Content="&#xE838;" Margin="0,0,0,4"
                    ToolTip="Backup-Ordner im Explorer anzeigen"/>
          </WrapPanel>
        </GroupBox>

        <!-- WrapPanel statt StackPanel: mit dem dritten Häkchen passt die Zeile
             nicht mehr in jede Fensterbreite und wurde am rechten Rand
             abgeschnitten. So bricht sie um, statt etwas zu verstecken. -->
        <Border Grid.Row="1" Padding="4,2,4,6">
          <WrapPanel Orientation="Horizontal">
            <TextBlock Text="Suche:" VerticalAlignment="Center" Margin="0,2,6,2"/>
            <TextBox x:Name="TxtSearch" Width="120" VerticalAlignment="Center" Margin="0,2,0,2"
                     ToolTip="Sucht in Charaktername, Label, Tags und Notiz"/>
            <TextBlock Text="Tag:" VerticalAlignment="Center" Margin="10,2,6,2"/>
            <ComboBox x:Name="CmbTag" Width="115" VerticalAlignment="Center" Margin="0,2,0,2"/>
            <CheckBox x:Name="ChkOnlySelected" Content="nur dieser Charakter" VerticalAlignment="Center" Margin="10,2,0,2"/>
            <CheckBox x:Name="ChkHideAuto" Content="ohne Auto-Sicherungen" VerticalAlignment="Center" Margin="10,2,0,2"/>
            <!-- Dreiwertig, deshalb Auswahlfeld statt Häkchen: "ausblenden"
                 allein liess sich nicht umkehren, man kam also nie dahin, nur
                 die geloeschten zu sehen. Ohne Beschriftung davor - die
                 Einstellungen sagen selbst, was sie tun, und die gesparte
                 Breite haelt die Filterzeile einzeilig. Die Auswertung geht
                 ueber den Index, nicht ueber den Text: sonst braeche sie in der
                 englischen Oberflaeche. -->
            <ComboBox x:Name="CmbTrash" Width="130" VerticalAlignment="Center" Margin="10,2,0,2" SelectedIndex="0"
                      ToolTip="Steuert nur die Anzeige der gelöschten Charaktere in dieser Liste. Am Papierkorb selbst ändert das nichts.">
              <ComboBoxItem Content="alle Einträge"/>
              <ComboBoxItem Content="ohne Papierkorb"/>
              <ComboBoxItem Content="nur Papierkorb"/>
            </ComboBox>
          </WrapPanel>
        </Border>

        <GroupBox Grid.Row="2" Header="Snapshots">
          <DataGrid x:Name="GridSnaps" AutoGenerateColumns="False" IsReadOnly="True"
                    RowStyle="{StaticResource AuswahlZeile}" CellStyle="{StaticResource AuswahlZelle}"
                    SelectionMode="Extended" HeadersVisibility="Column"
                    GridLinesVisibility="Horizontal" RowHeaderWidth="0" Margin="2">
            <!-- Die Breiten sind knapp gerechnet: acht Spalten müssen in die
                 rechte Hälfte passen, sonst schiebt sich die letzte (Größe) aus
                 dem Bild und man sieht sie nur über den Rollbalken. Summe der
                 festen Spalten plus MinWidth von Label muss unter der Breite der
                 rechten Spalte bleiben. -->
            <DataGrid.Columns>
              <DataGridTextColumn Header="Erstellt"   Binding="{Binding CreatedStr}" Width="128"
                                  SortMemberPath="SortKey"/>
              <DataGridTextColumn Header="Typ"        Binding="{Binding KindStr}"    Width="120"/>
              <DataGridTextColumn Header="Charakter"  Binding="{Binding char}"       Width="106"/>
              <DataGridTextColumn Header="Lvl"        Binding="{Binding LevelStr}"   Width="44"
                                  SortMemberPath="LevelSort"/>
              <DataGridTextColumn Header="Label"      Binding="{Binding label}"      Width="*" MinWidth="90"/>
              <DataGridTextColumn Header="Tags"       Binding="{Binding TagStr}"     Width="110"/>
              <DataGridTextColumn Header="Notiz"      Binding="{Binding NoteShort}"  Width="100"/>
              <!-- 76: "102,4 KB" braucht die Breite, bei 66 fiel das B weg. -->
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
    <TextBlock x:Name="TxtNameError" TextWrapping="Wrap" FontSize="11" FontWeight="Bold"
               Visibility="Collapsed" Margin="0,0,0,6"/>
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

# Ein Fenster für Umbenennen und Duplizieren. Beide fragen dasselbe ab: einen
# neuen Namen, live geprüft. Was sich unterscheidet - Titel, Knopfbeschriftung
# und der Satz, der die Folgen beschreibt - setzt Show-NameDialog.
$NameDialogXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Charakter umbenennen" Height="330" Width="520"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize">
  <StackPanel Margin="14">
    <TextBlock x:Name="TxtInfo" TextWrapping="Wrap" Margin="0,0,0,12"/>

    <TextBlock Text="Neuer Name:" Margin="0,0,0,4"/>
    <TextBox x:Name="TxtName" Margin="0,0,0,4"/>
    <TextBlock x:Name="TxtNameError" TextWrapping="Wrap" FontSize="11" FontWeight="Bold"
               Visibility="Collapsed" Margin="0,0,0,6"/>
    <TextBlock x:Name="TxtNameHint" TextWrapping="Wrap" FontSize="11" Foreground="#666" Margin="0,0,0,12"
               Text="Erlaubt sind 2 bis 15 Buchstaben, dazu höchstens ein Unterstrich oder Bindestrich in der Mitte. Ziffern und Leerzeichen lässt D2R nicht zu."/>

    <TextBlock x:Name="TxtActionHint" TextWrapping="Wrap" FontSize="11" Foreground="#666" Margin="0,0,0,12"/>

    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
      <Button x:Name="BtnOk"     Width="120" Height="30" Margin="0,0,8,0" IsDefault="True">Umbenennen</Button>
      <Button x:Name="BtnCancel" Width="90"  Height="30" IsCancel="True">Abbrechen</Button>
    </StackPanel>
  </StackPanel>
</Window>
'@

$DisclaimerXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Wichtiger Hinweis" Height="620" Width="660"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
        ShowInTaskbar="True">
  <DockPanel Margin="18">

    <StackPanel DockPanel.Dock="Bottom">
      <CheckBox x:Name="ChkGelesen" Margin="0,14,0,12"
                Content="Ich habe diesen Hinweis gelesen und verstanden und benutze das Programm auf eigene Verantwortung."/>
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button x:Name="BtnAnleitung" Width="150" Height="32" Margin="0,0,8,0">Anleitung öffnen</Button>
        <Button x:Name="BtnOk" Width="200" Height="32" Margin="0,0,8,0" IsDefault="True" IsEnabled="False">Einverstanden, Programm starten</Button>
        <Button x:Name="BtnCancel" Width="110" Height="32" IsCancel="True">Beenden</Button>
      </StackPanel>
    </StackPanel>

    <ScrollViewer VerticalScrollBarVisibility="Auto">
      <StackPanel>
        <TextBlock x:Name="TxtKopf" FontSize="17" FontWeight="Bold" Margin="0,0,0,12"
                   Text="Bitte einmal lesen, bevor es losgeht"/>
        <TextBlock x:Name="TxtBestaetigt" TextWrapping="Wrap" Foreground="#2E7D32" Margin="0,0,0,12"
                   Visibility="Collapsed"/>

        <TextBlock TextWrapping="Wrap" Margin="0,0,0,10"
                   Text="Dieses Programm ist ein privates Werkzeug, das kostenlos und unentgeltlich weitergegeben wird. Es wird ohne jede Gewährleistung und ohne Garantie zur Verfügung gestellt - weder ausdrücklich noch stillschweigend, insbesondere nicht für Fehlerfreiheit, Eignung für einen bestimmten Zweck oder ununterbrochene Verfügbarkeit."/>

        <TextBlock TextWrapping="Wrap" Margin="0,0,0,10"
                   Text="Die Benutzung erfolgt ausschließlich auf eigene Verantwortung und eigenes Risiko. Eine Haftung für Schäden jeder Art - insbesondere für verlorene, beschädigte oder überschriebene Spielstände und Charaktere sowie für entgangene Spielzeit - ist ausgeschlossen, soweit gesetzlich zulässig. Zwingende gesetzliche Haftung, etwa bei Vorsatz oder grober Fahrlässigkeit oder nach dem Produkthaftungsgesetz, bleibt davon unberührt."/>

        <TextBlock FontWeight="Bold" TextWrapping="Wrap" Margin="0,6,0,6"
                   Text="Was das Programm an deinen Dateien tut"/>
        <TextBlock TextWrapping="Wrap" Margin="0,0,0,4"
                   Text="• Sichern liest nur und verändert nichts am Spielstand."/>
        <TextBlock TextWrapping="Wrap" Margin="0,0,0,4"
                   Text="• Wiederherstellen schreibt Dateien in den Spielstand-Ordner zurück und überschreibt dabei gleichnamige Dateien."/>
        <TextBlock TextWrapping="Wrap" Margin="0,0,0,4"
                   Text="• Parken verschiebt Charakterdateien in einen Unterordner des Spielstand-Ordners."/>
        <TextBlock TextWrapping="Wrap" Margin="0,0,0,10"
                   Text="• Snapshot löschen entfernt eine Sicherung, niemals einen Spielstand."/>

        <TextBlock FontWeight="Bold" TextWrapping="Wrap" Margin="0,6,0,6"
                   Text="Empfehlung: lege dir vorher selbst eine Kopie an"/>
        <TextBlock TextWrapping="Wrap" Margin="0,0,0,6"
                   Text="Unabhängig von diesem Programm kannst und solltest du vor der ersten Benutzung eine eigene Kopie deines Spielstand-Ordners anlegen. Dazu genügt der Windows-Explorer: D2R beenden, den Ordner kopieren und die Kopie an einem sicheren Ort ablegen, am besten auf einem anderen Laufwerk. Das dauert eine Minute und ist die zuverlässigste Rückfahrkarte, die es gibt - sie ist von diesem Programm völlig unabhängig."/>
        <TextBlock x:Name="TxtPfad" TextWrapping="Wrap" FontFamily="Consolas" Foreground="#444" Margin="0,0,0,10"/>

        <TextBlock TextWrapping="Wrap" Margin="0,0,0,10"
                   Text="Die Sicherungen dieses Programms liegen bewusst als gewöhnliche Ordner mit unkomprimierten Dateien vor. Du kommst also auch ohne dieses Programm an sie heran - in jeder Sicherung liegt eine _INFO.txt, die das Schritt für Schritt erklärt."/>

        <TextBlock TextWrapping="Wrap" Foreground="#666" FontSize="11" Margin="0,6,0,0"
                   Text="Dieses Programm steht in keiner Verbindung zu Blizzard Entertainment und wird von dort weder unterstützt noch geprüft. Diablo II: Resurrected und alle zugehörigen Bezeichnungen sind Marken ihrer jeweiligen Inhaber. Ausführliche Bedienhinweise stehen in der beiliegenden ANLEITUNG.md."/>

        <StackPanel x:Name="PnlLizenz" Visibility="Collapsed" Margin="0,16,0,0">
          <TextBlock FontWeight="Bold" Margin="0,0,0,6" Text="Lizenz"/>
          <TextBox x:Name="TxtLizenz" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True"
                   BorderThickness="1" BorderBrush="#DDD" Background="#FAFAFA" Padding="8"
                   FontFamily="Consolas" FontSize="11" Height="150"
                   VerticalScrollBarVisibility="Auto"/>
        </StackPanel>
      </StackPanel>
    </ScrollViewer>

  </DockPanel>
</Window>
'@

$ParkXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Charaktere parken" Height="420" Width="540"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize">
  <StackPanel Margin="14">
    <TextBlock x:Name="TxtInfo" TextWrapping="Wrap" Margin="0,0,0,12"/>

    <TextBlock Text="Projekt:" Margin="0,0,0,4"/>
    <ComboBox x:Name="CmbProject" IsEditable="True" Height="26" Margin="0,0,0,4"/>
    <TextBlock TextWrapping="Wrap" FontSize="11" Foreground="#666" Margin="0,0,0,12"
               Text="Ein vorhandenes Projekt auswählen oder einen neuen Namen eintippen. Der Name wird zum Ordnernamen im Spielstand-Ordner unter _Projekte."/>

    <TextBlock TextWrapping="Wrap" Margin="0,0,0,10"
               Text="Die Dateien werden verschoben, nicht kopiert: die Charaktere verschwinden aus der Charakterauswahl von D2R und bleiben trotzdem vollständig erhalten. Zurückholen geht jederzeit."/>

    <TextBlock TextWrapping="Wrap" FontWeight="Bold" Margin="0,0,0,10"
               Text="Von jedem Charakter wird vorher automatisch eine Sicherung angelegt. Das lässt sich nicht abschalten - ein geparkter Charakter ist das Original, keine Kopie."/>

    <TextBlock x:Name="TxtWarnBox" TextWrapping="Wrap" Foreground="#B00020" FontWeight="Bold" Margin="0,0,0,10"/>

    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
      <Button x:Name="BtnOk"     Width="120" Height="30" Margin="0,0,8,0" IsDefault="True">Parken</Button>
      <Button x:Name="BtnCancel" Width="90"  Height="30" IsCancel="True">Abbrechen</Button>
    </StackPanel>
  </StackPanel>
</Window>
'@

$SettingsXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Einstellungen" Height="380" Width="620"
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

    <Border BorderBrush="#E0E0E0" BorderThickness="0,1,0,0" Margin="0,4,0,12"/>

    <DockPanel Margin="0,0,0,12">
      <Button x:Name="BtnResetView" DockPanel.Dock="Left" Width="170" Height="28">Ansicht zurücksetzen</Button>
      <TextBlock FontSize="11" Foreground="#666" TextWrapping="Wrap" VerticalAlignment="Center" Margin="10,0,0,0"
                 Text="Setzt Fenstergröße, Spaltenbreiten, Sortierung und die Ausblenden-Haken auf den Auslieferungszustand. Pfade, Sprache und deine Sicherungen bleiben unberührt. Das Fenster startet dabei neu."/>
    </DockPanel>

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
    '   Achtung: das betrifft sämtliche lokalen Charaktere.' = '   Careful: this affects every local character.'
    '   Online-Charaktere sind nicht dabei - sie liegen bei Blizzard' = '   Online characters are not included - they live at Blizzard'
    '   und bleiben von dieser Sicherung unberührt.' = '   and this backup leaves them untouched.'
    'In diesem Ordner liegen die Sicherungen deiner D2R-Charaktere.' = 'This folder holds the backups of your D2R characters.'
    '    Eine Sicherung eines Charakters. Darin die Spielstanddateien,' = '    One backup of one character. Contains the save files,'
    '    im Unterordner SharedStash die gemeinsame Truhe, und _INFO.txt' = '    the shared stash in the SharedStash subfolder, and _INFO.txt'
    '    mit allen Angaben und einer Anleitung zum Zurückkopieren.' = '    with all details and instructions for copying it back.'
    '    Eine Sicherung des kompletten Spielstand-Ordners. Ohne die' = '    One backup of the entire save folder. Without the files'
    '    Dateien der Online-Charaktere (*.ctlo, *.keyo) - die Charaktere' = '    of the online characters (*.ctlo, *.keyo) - those characters'
    '    selbst liegen bei Blizzard, hier stünde nur ihre Tastenbelegung.' = '    live at Blizzard, only their key bindings would be here.'
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

    # --- Haftungshinweis ---
    'Wichtiger Hinweis' = 'Important notice'
    'Bitte einmal lesen, bevor es losgeht' = 'Please read this once before you start'
    'Dieses Programm ist ein privates Werkzeug, das kostenlos und unentgeltlich weitergegeben wird. Es wird ohne jede Gewährleistung und ohne Garantie zur Verfügung gestellt - weder ausdrücklich noch stillschweigend, insbesondere nicht für Fehlerfreiheit, Eignung für einen bestimmten Zweck oder ununterbrochene Verfügbarkeit.' = 'This program is a private tool, passed on free of charge. It comes with no warranty and no guarantee of any kind - neither express nor implied, in particular none as to correctness, fitness for a particular purpose or uninterrupted availability.'
    'Die Benutzung erfolgt ausschließlich auf eigene Verantwortung und eigenes Risiko. Eine Haftung für Schäden jeder Art - insbesondere für verlorene, beschädigte oder überschriebene Spielstände und Charaktere sowie für entgangene Spielzeit - ist ausgeschlossen, soweit gesetzlich zulässig. Zwingende gesetzliche Haftung, etwa bei Vorsatz oder grober Fahrlässigkeit oder nach dem Produkthaftungsgesetz, bleibt davon unberührt.' = 'You use it entirely on your own responsibility and at your own risk. Liability for damages of any kind - in particular for lost, damaged or overwritten save games and characters, and for lost playing time - is excluded as far as the law allows. Mandatory statutory liability, for example for intent or gross negligence or under product liability law, remains unaffected.'
    'Was das Programm an deinen Dateien tut' = 'What the program does to your files'
    '• Sichern liest nur und verändert nichts am Spielstand.' = '• Backing up only reads; it never changes your save games.'
    '• Wiederherstellen schreibt Dateien in den Spielstand-Ordner zurück und überschreibt dabei gleichnamige Dateien.' = '• Restoring writes files back into the save folder, overwriting files of the same name.'
    '• Parken verschiebt Charakterdateien in einen Unterordner des Spielstand-Ordners.' = '• Parking moves character files into a subfolder of the save folder.'
    '• Snapshot löschen entfernt eine Sicherung, niemals einen Spielstand.' = '• Deleting a snapshot removes a backup, never a save game.'
    'Empfehlung: lege dir vorher selbst eine Kopie an' = 'Recommended: make your own copy first'
    'Unabhängig von diesem Programm kannst und solltest du vor der ersten Benutzung eine eigene Kopie deines Spielstand-Ordners anlegen. Dazu genügt der Windows-Explorer: D2R beenden, den Ordner kopieren und die Kopie an einem sicheren Ort ablegen, am besten auf einem anderen Laufwerk. Das dauert eine Minute und ist die zuverlässigste Rückfahrkarte, die es gibt - sie ist von diesem Programm völlig unabhängig.' = 'Independently of this program you can and should make your own copy of your save folder before using it for the first time. Windows Explorer is all you need: quit D2R, copy the folder and put the copy somewhere safe, ideally on a different drive. It takes a minute and it is the most reliable way back there is - completely independent of this program.'
    'Die Sicherungen dieses Programms liegen bewusst als gewöhnliche Ordner mit unkomprimierten Dateien vor. Du kommst also auch ohne dieses Programm an sie heran - in jeder Sicherung liegt eine _INFO.txt, die das Schritt für Schritt erklärt.' = 'This program deliberately stores its backups as ordinary folders holding uncompressed files. So you can get at them without this program - every backup contains an _INFO.txt explaining it step by step.'
    'Dieses Programm steht in keiner Verbindung zu Blizzard Entertainment und wird von dort weder unterstützt noch geprüft. Diablo II: Resurrected und alle zugehörigen Bezeichnungen sind Marken ihrer jeweiligen Inhaber. Ausführliche Bedienhinweise stehen in der beiliegenden ANLEITUNG.md.' = 'This program is not associated with Blizzard Entertainment and is neither endorsed nor reviewed by them. Diablo II: Resurrected and all related names are trademarks of their respective owners. Detailed instructions are in the enclosed INSTRUCTIONS.md.'
    'Ich habe diesen Hinweis gelesen und verstanden und benutze das Programm auf eigene Verantwortung.' = 'I have read and understood this notice and use the program on my own responsibility.'
    'Einverstanden, Programm starten' = 'I agree, start the program'
    'Über' = 'About'; 'Schließen' = 'Close'
    'Das Programm läuft bereits.' = 'The program is already running.'
    'Ein zweites Fenster würde dieselbe Verwaltungsdatei beschreiben, und die Beschriftungen der anderen Instanz gingen verloren. Bitte das vorhandene Fenster benutzen.' = 'A second window would write to the same index file, and the labels of the other instance would be lost. Please use the window that is already open.'
    'Hinweis, Lizenz und Anleitung' = 'Notice, licence and instructions'
    'Anleitung öffnen' = 'Open instructions'
    'Lizenz' = 'Licence'
    'Dieser Hinweis wurde bestätigt am {0}.' = 'This notice was accepted on {0}.'
    'Die Lizenzdatei konnte nicht gelesen werden.' = 'The licence file could not be read.'
    'Die Datei LICENSE liegt nicht neben dem Programm.' = 'The LICENSE file is not next to the program.'
    'Die Anleitung wurde nicht gefunden:' = 'The instructions were not found:'

    # --- Parken ---
    'Charaktere' = 'Characters'; 'Projekt' = 'Project'; 'Projekt:' = 'Project:'
    'Spielanzeige' = 'Character selection'
    'Geparkte ausblenden' = 'hide parked'
    'Ansicht zurücksetzen' = 'Reset view'
    'Setzt Fenstergröße, Spaltenbreiten, Sortierung und die Ausblenden-Haken auf den Auslieferungszustand. Pfade, Sprache und deine Sicherungen bleiben unberührt. Das Fenster startet dabei neu.' = 'Resets window size, column widths, sorting and the hide checkboxes to their original state. Paths, language and your backups are left untouched. The window restarts in the process.'
    'Fenstergröße, Spaltenbreiten, Sortierung und die Ausblenden-Haken auf den Auslieferungszustand zurücksetzen?' = 'Reset window size, column widths, sorting and the hide checkboxes to their original state?'
    'Pfade, Sprache und deine Sicherungen bleiben unberührt. Das Fenster startet dabei neu.' = 'Paths, language and your backups are left untouched. The window restarts in the process.'
    'Blendet geparkte Charaktere aus der Liste aus. Am Parken selbst ändert das nichts - nur an der Anzeige.' = 'Hides parked characters from the list. This changes nothing about the parking itself - only the display.'
    'Parken...' = 'Park...'; 'Parken' = 'Park'; 'Zurückholen' = 'Bring back'
    'Charaktere parken' = 'Park characters'
    'Verschiebt die markierten Charaktere in einen Projektordner. Sie verschwinden damit aus der Charakterauswahl von D2R, bleiben aber erhalten.' = 'Moves the selected characters into a project folder. They disappear from the D2R character selection but stay intact.'
    'Holt die markierten geparkten Charaktere zurück in den Spielstand-Ordner. Danach stehen sie wieder in der Charakterauswahl.' = 'Moves the selected parked characters back into the save folder. They then show up in the character selection again.'
    'Ein vorhandenes Projekt auswählen oder einen neuen Namen eintippen. Der Name wird zum Ordnernamen im Spielstand-Ordner unter _Projekte.' = 'Pick an existing project or type a new name. The name becomes the folder name inside the save folder under _Projekte.'
    'Die Dateien werden verschoben, nicht kopiert: die Charaktere verschwinden aus der Charakterauswahl von D2R und bleiben trotzdem vollständig erhalten. Zurückholen geht jederzeit.' = 'The files are moved, not copied: the characters vanish from the D2R character selection and still stay fully intact. You can bring them back at any time.'
    'Von jedem Charakter wird vorher automatisch eine Sicherung angelegt. Das lässt sich nicht abschalten - ein geparkter Charakter ist das Original, keine Kopie.' = 'A backup of every character is created first. This cannot be switched off - a parked character is the original, not a copy.'
    "Charakter '{0}' aus der Charakterauswahl von D2R nehmen." = "Remove character '{0}' from the D2R character selection."
    '{0} Charaktere aus der Charakterauswahl von D2R nehmen:' = 'Remove {0} characters from the D2R character selection:'
    'D2R läuft gerade. Zum Parken muss das Spiel beendet sein.' = 'D2R is running. The game must be closed before parking.'
    'D2R läuft. Zum Parken muss das Spiel beendet sein.' = 'D2R is running. The game must be closed before parking.'
    'D2R läuft. Zum Zurückholen muss das Spiel beendet sein.' = 'D2R is running. The game must be closed before bringing characters back.'
    'D2R läuft gerade. Zum Zurückholen muss das Spiel beendet sein.' = 'D2R is running. The game must be closed before bringing characters back.'
    'Der Projektname darf nicht leer sein.' = 'The project name must not be empty.'
    'Der Projektname darf nicht mit einem Leerzeichen beginnen oder enden.' = 'The project name must not start or end with a space.'
    'Der Projektname darf höchstens 40 Zeichen lang sein.' = 'The project name must not be longer than 40 characters.'
    'Dieser Projektname ist nicht erlaubt.' = 'That project name is not allowed.'
    'Im Projektnamen sind \ / : * ? " < > | nicht erlaubt.' = 'The characters \ / : * ? " < > | are not allowed in a project name.'
    'Kein Charakter angegeben.' = 'No character given.'
    'Zu diesem Charakter wurden keine Dateien gefunden:' = 'No files were found for this character:'
    'In diesem Projekt liegt bereits ein Charakter dieses Namens:' = 'This project already holds a character with that name:'
    'Im Projekt wurde kein solcher Charakter gefunden:' = 'No such character was found in the project:'
    'Im Spielstand-Ordner gibt es bereits einen Charakter dieses Namens:' = 'The save folder already holds a character with that name:'
    'Der Spielstand-Ordner existiert nicht:' = 'The save folder does not exist:'
    'Automatisch vor dem Parken' = 'Automatic before parking'
    'Die Sicherung vor dem Parken ist fehlgeschlagen - es wurde nichts verschoben.' = 'The backup before parking failed - nothing was moved.'
    'Bitte links mindestens einen Charakter auswählen, der noch nicht geparkt ist.' = 'Please select at least one character on the left that is not parked yet.'
    'Bitte links mindestens einen geparkten Charakter auswählen. Geparkte stehen blass und kursiv in der Liste, mit ihrem Projekt in der letzten Spalte.' = 'Please select at least one parked character on the left. Parked ones appear greyed and italic, with their project in the last column.'
    'Es sind nur geparkte Charaktere markiert. Die liegen nicht im Spielstand-Ordner und lassen sich nicht sichern - beim Parken wurde von jedem bereits eine Sicherung angelegt.' = 'Only parked characters are selected. They are not in the save folder and cannot be backed up - a backup of each was created when it was parked.'
    'Parken abgebrochen.' = 'Parking cancelled.'
    'Zurückholen abgebrochen.' = 'Bringing back cancelled.'
    "{0} Charakter(e) nach '{1}' geparkt - sie stehen jetzt nicht mehr in der Charakterauswahl von D2R." = "{0} character(s) parked in '{1}' - they no longer appear in the D2R character selection."
    '{0} Charakter(e) zurückgeholt - sie stehen wieder in der Charakterauswahl von D2R.' = '{0} character(s) brought back - they appear in the D2R character selection again.'
    '{0} Charakter(e) zurückholen?' = 'Bring back {0} character(s)?'
    'Sie stehen danach wieder in der Charakterauswahl von D2R.' = 'They will show up in the D2R character selection afterwards.'
    'D2R wurde während des Parkens gestartet. Die Dateien sind vollständig verschoben, aber prüfe im Spiel, ob alles stimmt.' = 'D2R was started while parking was in progress. The files were moved completely, but please check in the game that everything is right.'

    # --- Projekt-Infodatei ---
    'Geparkt am' = 'Parked on'
    'WAS IST DAS HIER?' = 'WHAT IS THIS?'
    'Diese Charaktere sind geparkt: sie liegen noch da, tauchen aber in' = 'These characters are parked: they are still here, but they no'
    'der Charakterauswahl von D2R nicht mehr auf. Das Spiel sieht nur' = 'longer show up in the D2R character selection. The game only sees'
    'Dateien, die unmittelbar im Spielstand-Ordner liegen - alles in' = 'files that sit directly in the save folder - anything inside a'
    'Unterordnern ist für D2R unsichtbar.' = 'subfolder is invisible to D2R.'
    'ACHTUNG: Das hier sind die Charaktere selbst, keine Sicherungen.' = 'CAREFUL: these are the characters themselves, not backups.'
    'Wird dieser Ordner gelöscht, sind sie weg. Beim Parken hat das' = 'If this folder is deleted, they are gone. When parking, the'
    'Programm allerdings von jedem eine Sicherung angelegt.' = 'program did create a backup of each of them.'
    'VON HAND ZURÜCKHOLEN' = 'BRING BACK BY HAND'
    '2. Die Dateien eines Charakters (ohne _INFO.txt) aus diesem Ordner' = '2. Move one character''s files (except _INFO.txt) from this folder'
    '   in den Spielstand-Ordner verschieben:' = '   into the save folder:'
    '3. D2R starten - der Charakter steht wieder in der Auswahl.' = '3. Start D2R - the character is back in the selection.'

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
    'Erlaubt sind nur Buchstaben (A-Z) sowie ein "_" oder "-" - keine Ziffern, keine Leerzeichen.' = 'Only letters (A-Z) are allowed, plus one "_" or "-" - no digits, no spaces.'
    'D2R erlaubt höchstens ein "_" oder "-" im Namen.' = 'D2R allows at most one "_" or "-" in a name.'
    'Das "_" oder "-" darf nicht am Anfang oder Ende des Namens stehen.' = 'The "_" or "-" must not be the first or last character of the name.'
    'Im Projekt ''{0}'' ist bereits ein Charakter namens ''{1}'' geparkt. Es gäbe den Namen dann zweimal.' = 'Project ''{0}'' already holds a parked character named ''{1}''. The name would exist twice.'

    # Umbenennen
    'Charakter umbenennen' = 'Rename character'
    'Neuer Name:' = 'New name:'
    'Erlaubt sind 2 bis 15 Buchstaben, dazu höchstens ein Unterstrich oder Bindestrich in der Mitte. Ziffern und Leerzeichen lässt D2R nicht zu.' = 'Allowed are 2 to 15 letters, plus at most one underscore or hyphen in the middle. D2R does not accept digits or spaces.'
    'Vorher wird automatisch gesichert. Der Name steht nur im Dateinamen - in die Spielstanddatei selbst wird nicht eingegriffen, Level, Ausrüstung und Fortschritt bleiben unberührt.' = 'A backup is made first. The name only lives in the file name - the save file itself is not touched, so level, gear and progress stay as they are.'
    'Umbenennen' = 'Rename'
    # 'Charakter' steht schon weiter oben - der Gruppenkopf nutzt denselben Eintrag.
    'Umbenennen. Alle Dateien wandern mit, vorher wird gesichert. Level und Ausrüstung bleiben unberührt.' = 'Rename. All files come along, a backup is made first. Level and gear stay untouched.'
    "Charakter '{0}' umbenennen ({1}, Level {2})." = "Rename character '{0}' ({1}, level {2})."
    'Der neue Name ist derselbe wie der alte.' = 'The new name is the same as the old one.'
    'Das ist der bisherige Name.' = 'That is the current name.'
    'D2R läuft. Zum Umbenennen muss das Spiel beendet sein.' = 'D2R is running. The game must be closed before renaming.'
    'D2R läuft gerade. Zum Umbenennen muss das Spiel beendet sein.' = 'D2R is currently running. The game must be closed before renaming.'
    'Es gibt bereits einen Charakter namens {0}.' = 'There is already a character named {0}.'
    'Im Projekt {0} ist bereits ein Charakter namens {1} geparkt.' = 'Project {0} already holds a parked character named {1}.'
    'Automatisch vor dem Umbenennen' = 'Automatic, before rename'
    'Die Sicherung vor dem Umbenennen ist fehlgeschlagen - es wurde nichts umbenannt.' = 'The backup before renaming failed - nothing was renamed.'
    'Bitte links genau einen Charakter auswählen. Umbenannt wird immer einer nach dem anderen.' = 'Please select exactly one character on the left. Renaming is done one at a time.'
    'Dieser Charakter ist geparkt. Zum Umbenennen muss er erst zurückgeholt werden - nur dann greift die Sicherung, die vorher angelegt wird.' = 'This character is parked. Bring it back before renaming - only then does the backup made beforehand cover it.'
    'Umbenennen abgebrochen.' = 'Rename cancelled.'
    "'{0}' heißt jetzt '{1}' - {2} Datei(en) umbenannt, vorher gesichert." = "'{0}' is now called '{1}' - {2} file(s) renamed, backed up beforehand."
    'D2R wurde während des Umbenennens gestartet. Die Dateien sind vollständig umbenannt, aber prüfe im Spiel, ob alles stimmt.' = 'D2R was started while renaming. The files are fully renamed, but please check in the game that everything is right.'

    # Duplizieren
    'Charakter duplizieren' = 'Duplicate character'
    'Duplizieren' = 'Duplicate'
    'Kopie unter neuem Namen anlegen. Das Original bleibt stehen, ohne Shared Stash.' = 'Create a copy under a new name. The original stays as it is, without the shared stash.'
    "Charakter '{0}' unter neuem Namen kopieren ({1}, Level {2})." = "Copy character '{0}' under a new name ({1}, level {2})."
    'Das Original bleibt unverändert stehen. Der Shared Stash wird nicht mitkopiert - er gehört allen Charakteren gemeinsam.' = 'The original stays untouched. The shared stash is not copied along - it belongs to all characters at once.'
    'Die Kopie braucht einen anderen Namen als das Original - auch eine andere Schreibweise reicht Windows nicht.' = 'The copy needs a different name than the original - a different capitalisation is not enough for Windows.'
    'D2R läuft. Zum Duplizieren muss das Spiel beendet sein.' = 'D2R is running. The game must be closed before duplicating.'
    'D2R läuft gerade. Zum Duplizieren muss das Spiel beendet sein.' = 'D2R is currently running. The game must be closed before duplicating.'
    'Automatisch vor dem Duplizieren' = 'Automatic, before duplicating'
    'Die Sicherung vor dem Duplizieren ist fehlgeschlagen - es wurde nichts kopiert.' = 'The backup before duplicating failed - nothing was copied.'
    'Bitte links genau einen Charakter auswählen. Kopiert wird immer einer nach dem anderen.' = 'Please select exactly one character on the left. Copying is done one at a time.'
    'Dieser Charakter ist geparkt. Zum Duplizieren muss er erst zurückgeholt werden.' = 'This character is parked. Bring it back before duplicating.'
    'Duplizieren abgebrochen.' = 'Duplicating cancelled.'
    "Kopie von '{0}' liegt als '{1}' bereit - {2} Datei(en), Original unverändert." = "Copy of '{0}' is ready as '{1}' - {2} file(s), original unchanged."
    'D2R wurde während des Duplizierens gestartet. Die Kopie ist vollständig, aber prüfe im Spiel, ob alles stimmt.' = 'D2R was started while duplicating. The copy is complete, but please check in the game that everything is right.'

    # Löschen und Papierkorb
    'Papierkorb' = 'Recycle bin'
    'Charakter löschen' = 'Delete character'
    'Papierkorb leeren' = 'Empty the recycle bin'
    'alle Einträge' = 'all entries'
    'ohne Papierkorb' = 'without recycle bin'
    'nur Papierkorb' = 'recycle bin only'
    'Steuert nur die Anzeige der gelöschten Charaktere in dieser Liste. Am Papierkorb selbst ändert das nichts.' = 'Controls only how deleted characters appear in this list. It changes nothing about the recycle bin itself.'
    'Löschen - in den Papierkorb des Programms, nicht sofort weg. Vorher wird gesichert. Nur aus der Spielauswahl nehmen? Dann parken.' = 'Delete - into the program''s own recycle bin, not gone right away. A backup is made first. Only taking it out of the game''s list? Park it instead.'
    'Entfernt alles, was im Papierkorb liegt - unabhängig davon, was in der Liste markiert ist. Die Sicherungen von vor dem Löschen bleiben bestehen.' = 'Removes everything in the recycle bin - no matter what is selected in the list. The backups made before each deletion remain.'
    'Leeren' = 'Empty'
    'Markierte Einträge' = 'Selected entries'
    'Endgültig löschen' = 'Delete for good'
    'nur dieser Charakter' = 'this character only'
    'ohne Auto-Sicherungen' = 'without automatic backups'
    'Bitte mindestens einen Eintrag in der Liste auswählen.' = 'Please select at least one entry in the list.'
    'Diesen Eintrag endgültig löschen?' = 'Delete this entry for good?'
    '{0} markierte Einträge endgültig löschen? Zusammen {1}.' = 'Delete {0} selected entries for good? {1} in total.'
    '... und {0} weitere' = '... and {0} more'
    'Damit ist der schnelle Rückweg weg. Die Sicherungen, die vor dem Löschen angelegt wurden, bleiben bestehen.' = 'That removes the quick way back. The backups made before deleting remain.'
    'Darunter sind {0} Papierkorb-Eintrag/-Einträge - für die ist danach der schnelle Rückweg weg.' = 'Among them are {0} recycle bin entries - for those, the quick way back is gone afterwards.'
    'Aus dem Papierkorb löschen' = 'Delete from the recycle bin'
    '{0} Eintrag/Einträge gelöscht.' = '{0} entry/entries deleted.'
    'Papierkorb-Eintrag löschen' = 'Delete recycle bin entry'
    'Damit ist der schnelle Rückweg für diesen Charakter weg. Die Sicherung, die vor dem Löschen angelegt wurde, bleibt bestehen.' = 'That removes the quick way back for this character. The backup made before deleting remains.'
    'ist leer' = 'is empty'
    '{0} Charakter(e), {1}' = '{0} character(s), {1}'
    "Charakter '{0}' ({1}, Level {2}) wirklich löschen?" = "Really delete character '{0}' ({1}, level {2})?"
    'Vorher wird automatisch gesichert, und die Dateien wandern in den Papierkorb des Programms - sie sind also nicht sofort weg.' = 'A backup is made first, and the files move into the program''s own recycle bin - so they are not gone right away.'
    'Wer den Charakter nur aus der Charakterauswahl von D2R nehmen will, sollte ihn stattdessen parken.' = 'To only take the character out of the D2R character selection, park it instead.'
    'D2R läuft. Zum Löschen muss das Spiel beendet sein.' = 'D2R is running. The game must be closed before deleting.'
    'D2R läuft gerade. Zum Löschen muss das Spiel beendet sein.' = 'D2R is currently running. The game must be closed before deleting.'
    'Der Backup-Ordner ist nicht erreichbar. Ohne ihn gibt es weder Sicherung noch Papierkorb, deshalb wird nicht gelöscht.' = 'The backup folder cannot be reached. Without it there is neither a backup nor a recycle bin, so nothing is deleted.'
    'Automatisch vor dem Löschen' = 'Automatic, before deleting'
    'Die Sicherung vor dem Löschen ist fehlgeschlagen - es wurde nichts gelöscht.' = 'The backup before deleting failed - nothing was deleted.'
    'Eine Datei ließ sich nicht in den Papierkorb kopieren, es wurde nichts gelöscht:' = 'A file could not be copied into the recycle bin, nothing was deleted:'
    'Gelöscht' = 'Deleted'
    'Bitte links genau einen Charakter auswählen. Gelöscht wird immer einer nach dem anderen.' = 'Please select exactly one character on the left. Deleting is done one at a time.'
    'Dieser Charakter ist geparkt. Zum Löschen muss er erst zurückgeholt werden.' = 'This character is parked. Bring it back before deleting.'
    'Löschen abgebrochen.' = 'Deleting cancelled.'
    "'{0}' ist gelöscht - {1} Datei(en) im Papierkorb, Sicherung angelegt." = "'{0}' is deleted - {1} file(s) in the recycle bin, backup made."
    'D2R wurde während des Löschens gestartet. Die Dateien sind vollständig im Papierkorb, aber prüfe im Spiel, ob alles stimmt.' = 'D2R was started while deleting. The files are fully in the recycle bin, but please check in the game that everything is right.'
    'Der Papierkorb ist leer.' = 'The recycle bin is empty.'
    '{0} gelöschte(r) Charakter(e) liegen im Papierkorb, zusammen {1}.' = '{0} deleted character(s) are in the recycle bin, {1} in total.'
    'Es wird der gesamte Papierkorb geleert - unabhängig davon, was in der Liste markiert ist. Einen einzelnen Eintrag entfernst du mit "Löschen".' = 'The whole recycle bin is emptied - no matter what is selected in the list. To remove a single entry, use "Delete".'
    'Beim Leeren werden diese Dateien endgültig entfernt.' = 'Emptying removes those files for good.'
    'Die Sicherungen, die vor jedem Löschen angelegt wurden, bleiben bestehen - über sie lässt sich ein Charakter auch danach noch zurückholen.' = 'The backups made before each deletion remain - a character can still be brought back through them afterwards.'
    'Leeren abgebrochen.' = 'Emptying cancelled.'
    'Papierkorb geleert - {0} Eintrag/Einträge entfernt.' = 'Recycle bin emptied - {0} entry/entries removed.'
    'Gelöscht am' = 'Deleted on'
    'Dieser Charakter wurde gelöscht und liegt hier im Papierkorb.' = 'This character was deleted and is sitting here in the recycle bin.'
    'Die Dateien in diesem Ordner sind die Originale - keine Kopie.' = 'The files in this folder are the originals - not a copy.'
    'Zusätzlich wurde vor dem Löschen eine Sicherung angelegt; die' = 'A backup was made before deleting as well; that one'
    'bleibt auch dann bestehen, wenn der Papierkorb geleert wird.' = 'remains even when the recycle bin is emptied.'
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
    param($Value, [string]$Format = (Get-DateFormat -WithSeconds))
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
    $row | Add-Member NoteProperty CreatedStr $(if ($created) { $created.ToString((Get-DateFormat -WithSeconds)) } else { '' }) -Force
    # Auto-Kennzeichnung als Zusatz, nicht als eigener Typ: sonst erschiene eine
    # automatische Gesamtstand-Sicherung als "Gesamtstand", verschwände aber
    # trotzdem beim Filter "Auto-Sicherungen ausblenden".
    $kindStr = switch ($Record.kind) {
        'full'  { T 'Kompletter Ordner' }
        'trash' { T 'Papierkorb' }
        default { T 'Charakter' }
    }
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

# ---------------------------------------------------------------------------
# Nur eine Instanz gleichzeitig
# ---------------------------------------------------------------------------
# Zwei laufende Fenster schreiben beide in dieselbe index.json. Wer zuletzt
# speichert, gewinnt - Labels, Tags und Notizen der anderen Instanz waeren weg.
# Die Sicherungen selbst blieben heil, aber ihre Beschriftungen sind Handarbeit
# und sollen nicht still verschwinden.
#
# Bewusst ohne "Global\": der Konflikt entsteht zwischen zwei Fenstern desselben
# Benutzers. Zwei verschiedene Benutzer haben ohnehin getrennte Konfigurationen
# und Backup-Ordner und sollen sich nicht gegenseitig aussperren.
function Enter-EinzelInstanz {
    $script:Instanz = New-Object System.Threading.Mutex($false, 'D2RCharBackupManager.Einzelinstanz')
    try {
        # WaitOne(0): sofort zurueckkommen statt zu warten.
        return $script:Instanz.WaitOne(0)
    } catch [System.Threading.AbandonedMutexException] {
        # Die Vorgaengerinstanz ist abgestuerzt, ohne freizugeben. Der Mutex
        # gehoert damit uns - das ist kein Fehler, sondern der Normalfall nach
        # einem Absturz.
        return $true
    }
}

# Muss VOR jedem Neustart laufen (Sprachwechsel, Ansicht zuruecksetzen), sonst
# sperrt sich das Programm beim Wiederanlauf selbst aus: der neue Prozess
# startet, waehrend der alte den Mutex noch haelt.
function Exit-EinzelInstanz {
    if ($script:Instanz) {
        try { $script:Instanz.ReleaseMutex() } catch { }
        $script:Instanz.Dispose()
        $script:Instanz = $null
    }
}

if (-not (Enter-EinzelInstanz)) {
    [void][System.Windows.MessageBox]::Show(
        (T 'Das Programm läuft bereits.') + "`n`n" +
        (T 'Ein zweites Fenster würde dieselbe Verwaltungsdatei beschreiben, und die Beschriftungen der anderen Instanz gingen verloren. Bitte das vorhandene Fenster benutzen.'),
        $script:AppName, 'OK', 'Information')
    return
}

$win = ConvertFrom-Xaml $MainXaml

$GridChars       = $win.FindName('GridChars')
$GridSnaps       = $win.FindName('GridSnaps')
$TxtStatus       = $win.FindName('TxtStatus')
$TxtWarn         = $win.FindName('TxtWarn')
$TxtSearch       = $win.FindName('TxtSearch')
$CmbTag          = $win.FindName('CmbTag')
$ChkOnlySelected = $win.FindName('ChkOnlySelected')
$ChkHideAuto     = $win.FindName('ChkHideAuto')
$CmbTrash        = $win.FindName('CmbTrash')
$BtnDelete       = $win.FindName('BtnDelete')
$BtnRestore      = $win.FindName('BtnRestore')
$ChkHidePark     = $win.FindName('ChkHidePark')
$ColLinks        = $win.FindName('ColLinks')
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

# Spaltenbreiten als Text, damit sie in der config.json lesbar bleiben:
# "128" sind Pixel, "*1" ist eine Stern-Spalte mit Faktor 1 (dehnt sich mit dem
# Fenster). Der Unterschied MUSS erhalten bleiben - speichert man die Pixelbreite
# einer Stern-Spalte und setzt sie fest zurück, hört das Mitwachsen auf und
# rechts im Gitter bleibt beim Vergrößern ein leerer Streifen stehen.
#
# Bewusst ganze Zahlen: ein Dezimalpunkt wäre je nach Windows-Sprache mal Punkt,
# mal Komma, und das Zurücklesen schlüge auf dem anderen Rechner fehl.
function Get-ColWidths {
    param($Grid)
    @($Grid.Columns | ForEach-Object {
        if ($_.Width.IsStar) { '*' + [int]$_.Width.Value } else { [string][int]$_.ActualWidth }
    })
}

function Set-ColWidths {
    param($Grid, $Werte)
    $w = @($Werte)
    # Kamen seit dem Speichern Spalten dazu (etwa "Projekt" in 1.1), passt die
    # Zuordnung über den Index nicht mehr. Dann lieber die Vorgabe stehen lassen.
    if ($w.Count -ne $Grid.Columns.Count) { return }

    for ($i = 0; $i -lt $w.Count; $i++) {
        $s = [string]$w[$i]
        if (-not $s) { continue }
        if ($s.StartsWith('*')) {
            $faktor = 0
            if (-not [int]::TryParse($s.Substring(1), [ref]$faktor) -or $faktor -le 0) { $faktor = 1 }
            $Grid.Columns[$i].Width = New-Object System.Windows.Controls.DataGridLength(
                [double]$faktor, [System.Windows.Controls.DataGridLengthUnitType]::Star)
        } else {
            $px = 0
            # Grenzen gegen unbrauchbare Werte aus einer verbogenen config.json.
            if ([int]::TryParse($s, [ref]$px) -and $px -ge 20 -and $px -le 900) {
                $Grid.Columns[$i].Width = New-Object System.Windows.Controls.DataGridLength([double]$px)
            }
        }
    }
}

function Save-View {
    if (-not $script:Config.View) { $script:Config.View = New-DefaultView }
    $v = $script:Config.View

    # Nur im normalen Zustand messen: maximiert liefert die Bildschirmgröße, und
    # beim nächsten Start stünde ein bildschirmfüllendes Fenster da, das sich
    # nicht mehr verkleinern lässt, ohne es von Hand zu ziehen.
    if ($win.WindowState -eq 'Normal') {
        if ($win.ActualWidth  -ge 900) { $v.WindowWidth  = [int]$win.ActualWidth }
        if ($win.ActualHeight -ge 520) { $v.WindowHeight = [int]$win.ActualHeight }
        if ($ColLinks -and $ColLinks.ActualWidth -ge 300) { $v.LeftWidth = [int]$ColLinks.ActualWidth }
    }
    $v.ColsChars = Get-ColWidths $GridChars
    $v.ColsSnaps = Get-ColWidths $GridSnaps
    $v.HideAuto     = [bool]$ChkHideAuto.IsChecked
    $v.TrashFilter  = [int]$CmbTrash.SelectedIndex
    $v.HidePark     = [bool]$ChkHidePark.IsChecked
    $v.OnlySelected = [bool]$ChkOnlySelected.IsChecked
    try { Export-Config } catch { }
}

function Restore-View {
    $v = $script:Config.View
    if (-not $v) { return }

    # Gegen die sichtbare Arbeitsfläche begrenzen. Eine Größe, die von einem
    # größeren Monitor stammt, darf nicht dazu führen, dass Knöpfe hinter dem
    # Bildschirmrand liegen.
    $maxB = [double][System.Windows.SystemParameters]::WorkArea.Width
    $maxH = [double][System.Windows.SystemParameters]::WorkArea.Height
    if ($v.WindowWidth)  { $win.Width  = [math]::Max(900, [math]::Min([double]$v.WindowWidth,  $maxB)) }
    if ($v.WindowHeight) { $win.Height = [math]::Max(520, [math]::Min([double]$v.WindowHeight, $maxH)) }

    if ($v.LeftWidth -and $ColLinks) {
        # 420 ist die MinWidth der rechten Hälfte - so bleibt die Snapshot-Liste
        # bedienbar, egal was gespeichert war.
        $b = [math]::Max(300, [math]::Min([double]$v.LeftWidth, $win.Width - 420))
        $ColLinks.Width = New-Object System.Windows.GridLength($b)
    }

    Set-ColWidths $GridChars $v.ColsChars
    Set-ColWidths $GridSnaps $v.ColsSnaps

    if ($ChkHideAuto)     { $ChkHideAuto.IsChecked     = [bool]$v.HideAuto }
    # Aus 1.3.0 stammt noch das Haekchen HideTrash. Wer damit ausgeblendet
    # hatte, soll nach dem Update nicht ploetzlich alles sehen.
    if ($CmbTrash) {
        $idx = if ($v.PSObject.Properties['TrashFilter']) { [int]$v.TrashFilter }
               elseif ($v.PSObject.Properties['HideTrash'] -and $v.HideTrash) { 1 }
               else { 0 }
        if ($idx -lt 0 -or $idx -gt 2) { $idx = 0 }
        $CmbTrash.SelectedIndex = $idx
    }
    if ($ChkHidePark)     { $ChkHidePark.IsChecked     = [bool]$v.HidePark }
    if ($ChkOnlySelected) { $ChkOnlySelected.IsChecked = [bool]$v.OnlySelected }
}

# Nur die Ansicht - Pfade, Sprache und Klassennamen bleiben stehen.
function Reset-View {
    $script:Config.View      = $null
    $script:Config.SortChars = $null
    $script:Config.SortSnaps = $null
    Export-Config
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

# Die ganzen Datensätze statt nur der Namen - fürs Parken muss man wissen, ob
# ein Charakter aktiv ist oder schon in einem Projekt liegt.
function Get-SelectedCharRows {
    @($GridChars.SelectedItems | ForEach-Object { $_ })
}

# Der Knopf nennt immer die Anzahl - so ist vor dem Klick klar, wie viele
# Charaktere gleich gesichert werden.
function Update-SnapButtonLabel {
    $knopf = $win.FindName('BtnSnapChar')
    if (-not $knopf) { return }
    # Zählt nur die aktiven: geparkte Charaktere werden beim Sichern übergangen,
    # die Zahl im Knopf soll aber der Wahrheit entsprechen.
    $anzahl = @(Get-SelectedCharRows | Where-Object { -not $_.Parked }).Count
    $knopf.Content = (T 'Markierte sichern') + ' (' + $anzahl + ')'
}

function Get-SelectedSnapshotRecord {
    $row = $GridSnaps.SelectedItem
    if (-not $row) { return $null }
    $script:Index.snapshots | Where-Object { $_.id -eq $row.id } | Select-Object -First 1
}

# Alle markierten Einträge. Löschen arbeitet darauf, damit sich der Papierkorb
# über Filter plus Mehrfachauswahl leeren lässt, statt über einen eigenen Knopf.
function Get-SelectedSnapshotRecords {
    $ids = @($GridSnaps.SelectedItems | ForEach-Object { $_.id })
    if ($ids.Count -eq 0) { return @() }
    # Reihenfolge der Liste beibehalten, nicht die des Index - die Rückfrage
    # zählt sonst anders auf, als man markiert hat.
    @($ids | ForEach-Object { $id = $_; $script:Index.snapshots | Where-Object { $_.id -eq $id } | Select-Object -First 1 } | Where-Object { $_ })
}

function Update-TagFilter {
    $current = $CmbTag.SelectedItem
    $tags = @($script:Index.snapshots | ForEach-Object { @($_.tags) } | Where-Object { $_ } | Sort-Object -Unique)
    $CmbTag.Items.Clear()
    $CmbTag.Items.Add((T '(alle)')) | Out-Null
    foreach ($t in $tags) { $CmbTag.Items.Add($t) | Out-Null }
    if ($current -and $CmbTag.Items.Contains($current)) { $CmbTag.SelectedItem = $current } else { $CmbTag.SelectedIndex = 0 }
}

# Der Knopf nennt die Anzahl, sobald mehrere Zeilen markiert sind - sonst sieht
# man vor dem Klick nicht, wie weit die Markierung reicht. Sind es lauter
# Papierkorb-Einträge, sagt er zusätzlich, dass es diesmal wirklich endgültig
# ist: dort liegen die Originaldateien, nicht eine Kopie.
function Update-DeleteButtonLabel {
    $recs  = @(Get-SelectedSnapshotRecords)
    $trash = @($recs | Where-Object { $_.kind -eq 'trash' }).Count
    $text  = if ($recs.Count -gt 0 -and $trash -eq $recs.Count) { T 'Endgültig löschen' } else { T 'Löschen' }
    if ($recs.Count -gt 1) { $text += " ($($recs.Count))" }
    $BtnDelete.Content = $text
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

    switch ($CmbTrash.SelectedIndex) {
        1 { $rows = @($rows | Where-Object { $_.kind -ne 'trash' }) }
        2 { $rows = @($rows | Where-Object { $_.kind -eq 'trash' }) }
    }

    $GridSnaps.ItemsSource = @($rows | Sort-Object SortKey -Descending)
    Restore-GridSort $GridSnaps $script:Config.SortSnaps
    Set-Status ((T "{0} Snapshot(s) angezeigt, {1} insgesamt.") -f $GridSnaps.Items.Count, $script:Index.snapshots.Count)
}

function Update-All {
    # Mehrfachauswahl über das Neuladen hinweg erhalten.
    $selNamen = @(Get-SelectedChars)
    # Aktive UND geparkte Charaktere: was weggeräumt ist, soll man nicht aus
    # den Augen verlieren - sonst findet man es nie wieder. Wer viele dauerhaft
    # geparkt hat, blendet sie über die Checkbox aus; der Haken wird gemerkt
    # (siehe Save-View) und steht nach dem Neustart wieder so da.
    $alle = @(Get-AllCharacters)
    if ($ChkHidePark -and $ChkHidePark.IsChecked) {
        $alle = @($alle | Where-Object { -not $_.Parked })
    }
    $GridChars.ItemsSource = $alle
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

    $dlg.FindName('BtnResetView').Add_Click({
        $ans = [System.Windows.MessageBox]::Show(
            ((T 'Fenstergröße, Spaltenbreiten, Sortierung und die Ausblenden-Haken auf den Auslieferungszustand zurücksetzen?') + "`n`n" +
             (T 'Pfade, Sprache und deine Sicherungen bleiben unberührt. Das Fenster startet dabei neu.')),
            (T 'Ansicht zurücksetzen'), 'YesNo', 'Question')
        if ($ans -ne 'Yes') { return }

        Reset-View
        # Verhindert, dass das Schließen die eben gelöschten Werte gleich wieder
        # zurückschreibt - sonst bliebe der Knopf ohne Wirkung.
        $script:SkipViewSave     = $true
        $script:RestartRequested = $true
        $dlg.DialogResult = $false
        $win.Close()
    }.GetNewClosure())

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

# Live-Prüfung für ein Namensfeld: prüft bei jedem Tastendruck, färbt das Feld
# und sperrt den OK-Knopf, solange der Name nicht geht. Ein ungültiger Name soll
# auffallen, während man tippt - nicht erst, wenn man fertig zu sein glaubt und
# auf den Knopf drückt.
#
# $Extra ist eine zusätzliche Prüfung des Aufrufers, typischerweise auf
# Namenskollision. Sie bekommt den Namen und liefert '' für "in Ordnung" oder
# einen Text. Ob dieser Text nur warnt oder auch sperrt, entscheidet
# $ExtraBlocks: beim Umbenennen ist eine Kollision ein Abbruchgrund, beim
# Wiederherstellen dagegen eine erlaubte Entscheidung - dort wird überschrieben,
# wenn der Benutzer die Rückfrage bejaht.
#
# Farben: rot sperrt, orange warnt. Zwei Farben statt einer, weil "geht nicht"
# und "geht, aber überlege kurz" sonst gleich aussähen. Die Farbe der
# Zusatzprüfung richtet sich deshalb nach $ExtraBlocks - eine orange Meldung an
# einem gesperrten Knopf wäre ein Widerspruch.
function Register-NameCheck {
    param(
        [object]$Box,
        [object]$ErrBox,
        [object]$Ok,
        [scriptblock]$Extra = $null,
        [bool]$ExtraBlocks = $true
    )

    # Ausgangszustand merken, damit der Rahmen bei gültigem Namen wieder genau so
    # aussieht wie vorher - Farbe und Dicke kommen aus dem Windows-Design.
    $normalBrush = $Box.BorderBrush
    $normalThick = $Box.BorderThickness
    $rot    = [System.Windows.Media.Brushes]::Firebrick
    $orange = [System.Windows.Media.Brushes]::DarkOrange

    $pruefen = {
        $name    = $Box.Text.Trim()
        $fehler  = Test-D2RName $name
        $hinweis = ''
        if (-not $fehler -and $Extra) { $hinweis = & $Extra $name }

        if ($fehler) {
            $ErrBox.Text        = $fehler
            $ErrBox.Foreground  = $rot
            $ErrBox.Visibility  = 'Visible'
            $Box.BorderBrush    = $rot
            $Box.BorderThickness = [System.Windows.Thickness]::new(2)
            $Ok.IsEnabled       = $false
        } elseif ($hinweis) {
            $farbe = if ($ExtraBlocks) { $rot } else { $orange }
            $ErrBox.Text        = $hinweis
            $ErrBox.Foreground  = $farbe
            $ErrBox.Visibility  = 'Visible'
            $Box.BorderBrush    = $farbe
            $Box.BorderThickness = [System.Windows.Thickness]::new(2)
            $Ok.IsEnabled       = -not $ExtraBlocks
        } else {
            $ErrBox.Text        = ''
            $ErrBox.Visibility  = 'Collapsed'
            $Box.BorderBrush    = $normalBrush
            $Box.BorderThickness = $normalThick
            $Ok.IsEnabled       = $true
        }
    }.GetNewClosure()

    $Box.Add_TextChanged($pruefen)
    # Einmal sofort auslösen: der Dialog geht mit einem vorbelegten Namen auf,
    # und der kann schon beim Öffnen kollidieren.
    & $pruefen
}

function Show-RestoreDialog {
    param([object]$Record)

    $dlg = ConvertFrom-Xaml $RestoreXaml
    $dlg.Owner = $win
    $txtInfo  = $dlg.FindName('TxtInfo')
    $txtName  = $dlg.FindName('TxtName')
    $txtNameE = $dlg.FindName('TxtNameError')
    $chkStash = $dlg.FindName('ChkStash')
    $chkSafe  = $dlg.FindName('ChkSafety')
    $txtWarnB = $dlg.FindName('TxtWarnBox')
    $btnOk    = $dlg.FindName('BtnOk')

    $created = Format-Timestamp $Record.created (Get-DateFormat)

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

        # Live-Prüfung ans Namensfeld. Die Kollision warnt hier nur, sie sperrt
        # nicht: einen vorhandenen Charakter zu überschreiben ist an dieser
        # Stelle eine zulässige Absicht. Die Rückfrage vor dem Schreiben bleibt.
        Register-NameCheck -Box $txtName -ErrBox $txtNameE -Ok $btnOk -ExtraBlocks $false -Extra {
            param($n)
            if ($n -eq $Record.char) { return '' }
            $k = Get-NameKollision $n
            switch ($k.Kind) {
                'active' { (T 'Es gibt bereits einen Charakter namens ''{0}''. Seine Dateien werden überschrieben.') -f $n }
                'parked' { (T 'Im Projekt ''{0}'' ist bereits ein Charakter namens ''{1}'' geparkt. Es gäbe den Namen dann zweimal.') -f $k.Project, $n }
                default  { '' }
            }
        }.GetNewClosure()
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

# $Mode ist 'rename' oder 'copy'. Der Unterschied ist klein, aber wichtig: beim
# Umbenennen darf man die Schreibweise des eigenen Namens ändern, beim
# Duplizieren nicht - eine Kopie, die sich nur in der Schreibweise
# unterscheidet, wäre für Windows dieselbe Datei und überschriebe das Original.
function Show-NameDialog {
    param([object]$Row, [ValidateSet('rename','copy')][string]$Mode = 'rename')

    $dlg = ConvertFrom-Xaml $NameDialogXaml
    $dlg.Owner = $win
    $txtInfo  = $dlg.FindName('TxtInfo')
    $txtName  = $dlg.FindName('TxtName')
    $txtNameE = $dlg.FindName('TxtNameError')
    $txtHint  = $dlg.FindName('TxtActionHint')
    $btnOk    = $dlg.FindName('BtnOk')

    $alt   = $Row.Name
    $istKopie = ($Mode -eq 'copy')

    if ($istKopie) {
        $dlg.Title      = T 'Charakter duplizieren'
        $btnOk.Content  = T 'Duplizieren'
        $txtInfo.Text   = ((T "Charakter '{0}' unter neuem Namen kopieren ({1}, Level {2}).") -f $alt, $Row.ClassName, $Row.Level)
        $txtHint.Text   = T 'Das Original bleibt unverändert stehen. Der Shared Stash wird nicht mitkopiert - er gehört allen Charakteren gemeinsam.'
        # Vorbelegung leer lassen: beim Duplizieren ist der alte Name nie die
        # Antwort, und ein vorbelegtes Feld, das sofort rot wird, sieht nach
        # Fehler aus, obwohl man noch gar nichts getan hat.
        $txtName.Text = ''
    } else {
        $dlg.Title      = T 'Charakter umbenennen'
        $btnOk.Content  = T 'Umbenennen'
        $txtInfo.Text   = ((T "Charakter '{0}' umbenennen ({1}, Level {2}).") -f $alt, $Row.ClassName, $Row.Level)
        $txtHint.Text   = T 'Vorher wird automatisch gesichert. Der Name steht nur im Dateinamen - in die Spielstanddatei selbst wird nicht eingegriffen, Level, Ausrüstung und Fortschritt bleiben unberührt.'
        $txtName.Text = $alt
        $txtName.SelectAll()
    }
    $txtName.Focus() | Out-Null

    # Alles, was den Knopf sperrt, läuft durch diese eine Prüfung - auch das
    # laufende Spiel. Stünde die D2R-Sperre daneben, hübe der nächste Tastendruck
    # sie wieder auf. So gewinnt sie immer, und wer D2R bei offenem Dialog
    # beendet, bekommt den Knopf beim nächsten Tastendruck von selbst zurück.
    #
    # Die Kollision sperrt hart: einen vorhandenen Charakter zu überschreiben
    # ergibt hier keinen Sinn, das wäre nur ein Weg, ihn zu verlieren.
    Register-NameCheck -Box $txtName -ErrBox $txtNameE -Ok $btnOk -ExtraBlocks $true -Extra {
        param($n)
        if (Test-D2RRunning) {
            return $(if ($istKopie) { T 'D2R läuft gerade. Zum Duplizieren muss das Spiel beendet sein.' }
                     else           { T 'D2R läuft gerade. Zum Umbenennen muss das Spiel beendet sein.' })
        }
        if ($n -eq $alt) {
            # Beim Umbenennen ist eine andere Schreibweise des eigenen Namens
            # erlaubt - das ist keine Kollision mit einem fremden Charakter,
            # sondern mit sich selbst. Beim Duplizieren wäre genau das der Fall,
            # in dem die Kopie das Original überschriebe.
            if ($istKopie) { return (T 'Die Kopie braucht einen anderen Namen als das Original - auch eine andere Schreibweise reicht Windows nicht.') }
            if ($n -ceq $alt) { return (T 'Das ist der bisherige Name.') }
            return ''
        }
        $k = Get-NameKollision $n
        switch ($k.Kind) {
            'active' { (T 'Es gibt bereits einen Charakter namens {0}.') -f $n }
            'parked' { (T 'Im Projekt {0} ist bereits ein Charakter namens {1} geparkt.') -f $k.Project, $n }
            default  { '' }
        }
    }.GetNewClosure()

    $btnOk.Add_Click({
        $dlg.Tag = $txtName.Text.Trim()
        $dlg.DialogResult = $true
    }.GetNewClosure())

    if ($dlg.ShowDialog()) { return $dlg.Tag }
    $null
}

function Show-ParkDialog {
    param([string[]]$Names)

    $dlg = ConvertFrom-Xaml $ParkXaml
    $dlg.Owner = $win
    $txtInfo  = $dlg.FindName('TxtInfo')
    $cmb      = $dlg.FindName('CmbProject')
    $txtWarnB = $dlg.FindName('TxtWarnBox')
    $btnOk    = $dlg.FindName('BtnOk')

    $namen = @($Names)
    $txtInfo.Text = if ($namen.Count -eq 1) {
        (T "Charakter '{0}' aus der Charakterauswahl von D2R nehmen.") -f $namen[0]
    } else {
        ((T '{0} Charaktere aus der Charakterauswahl von D2R nehmen:') -f $namen.Count) + ' ' + ($namen -join ', ')
    }

    foreach ($p in (Get-ProjectNames)) { [void]$cmb.Items.Add($p) }
    if ($cmb.Items.Count -gt 0) { $cmb.SelectedIndex = 0 }

    # Blockierend statt warnend: D2R hält die Spielstanddateien im Zugriff und
    # schreibt sie beim Beenden zurück.
    if (Test-D2RRunning) {
        $txtWarnB.Text = T 'D2R läuft gerade. Zum Parken muss das Spiel beendet sein.'
        $btnOk.IsEnabled = $false
    }

    $btnOk.Add_Click({
        $name = ''
        if ($cmb.Text) { $name = ([string]$cmb.Text).Trim() }
        $err = Test-ProjectName $name
        if ($err) { $txtWarnB.Text = $err; return }
        # Zwischen Öffnen des Dialogs und dem Klick kann D2R gestartet worden sein.
        if (Test-D2RRunning) {
            $txtWarnB.Text = T 'D2R läuft gerade. Zum Parken muss das Spiel beendet sein.'
            return
        }
        $dlg.Tag = $name
        $dlg.DialogResult = $true
    }.GetNewClosure())

    if ($dlg.ShowDialog()) { return [string]$dlg.Tag }
    ''
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
    Update-DeleteButtonLabel
    $rec = Get-SelectedSnapshotRecord
    if (-not $rec) { Clear-Details; return }
    $TxtLabel.Text = [string]$rec.label
    $TxtTags.Text  = (@($rec.tags) -join ', ')
    $TxtNote.Text  = [string]$rec.note
})

$TxtSearch.Add_TextChanged({ Update-SnapshotGrid })
$CmbTag.Add_SelectionChanged({ Update-SnapshotGrid })
$ChkOnlySelected.Add_Click({ Update-SnapshotGrid; Save-View })
$ChkHideAuto.Add_Click({ Update-SnapshotGrid; Save-View })
$CmbTrash.Add_SelectionChanged({ Update-SnapshotGrid; Save-View })

# Update-All statt nur die Liste neu zu setzen: die Auswahl und die Zahl im
# Sichern-Knopf müssen mitziehen, wenn Zeilen verschwinden.
$ChkHidePark.Add_Click({ Update-All; Save-View })

$win.FindName('BtnRefresh').Add_Click({ Update-All })

$win.FindName('BtnAbout').Add_Click({ [void](Show-DisclaimerDialog -ReadOnly) })

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
    # Geparkte Charaktere liegen nicht im Spielstand-Ordner und lassen sich
    # deshalb nicht sichern. Beim Parken hat jeder von ihnen bereits einen
    # Pflicht-Snapshot bekommen.
    $rows      = @(Get-SelectedCharRows)
    $namen     = @($rows | Where-Object { -not $_.Parked } | ForEach-Object { $_.Name })
    $uebergang = @($rows | Where-Object { $_.Parked } | ForEach-Object { $_.Name })
    if ($namen.Count -eq 0) {
        $text = if ($uebergang.Count -gt 0) {
            T 'Es sind nur geparkte Charaktere markiert. Die liegen nicht im Spielstand-Ordner und lassen sich nicht sichern - beim Parken wurde von jedem bereits eine Sicherung angelegt.'
        } else {
            T 'Bitte links einen Charakter auswählen.'
        }
        [void][System.Windows.MessageBox]::Show($text, $script:AppName, 'OK', 'Information')
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

$win.FindName('BtnPark').Add_Click({
    # Nur aktive Charaktere lassen sich parken - schon geparkte werden
    # übergangen statt eine Fehlermeldung zu erzeugen.
    $rows  = @(Get-SelectedCharRows)
    $aktiv = @($rows | Where-Object { -not $_.Parked } | ForEach-Object { $_.Name })
    if ($aktiv.Count -eq 0) {
        [void][System.Windows.MessageBox]::Show(
            (T 'Bitte links mindestens einen Charakter auswählen, der noch nicht geparkt ist.'),
            $script:AppName, 'OK', 'Information')
        return
    }

    $projekt = Show-ParkDialog -Names $aktiv
    if (-not $projekt) { Set-Status (T 'Parken abgebrochen.'); return }

    $geparkt = 0; $fehler = @(); $lief = $false
    [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
    try {
        foreach ($n in $aktiv) {
            try {
                $erg = Move-CharacterToProject -CharName $n -Project $projekt
                $geparkt++
                if ($erg.D2RStartedDuring) { $lief = $true }
            } catch {
                $fehler += "$n : $($_.Exception.Message)"
            }
        }
    } finally {
        [System.Windows.Input.Mouse]::OverrideCursor = $null
    }

    Update-All
    Set-Status ((T "{0} Charakter(e) nach '{1}' geparkt - sie stehen jetzt nicht mehr in der Charakterauswahl von D2R.") -f $geparkt, $projekt)

    if ($lief) {
        [void][System.Windows.MessageBox]::Show(
            (T 'D2R wurde während des Parkens gestartet. Die Dateien sind vollständig verschoben, aber prüfe im Spiel, ob alles stimmt.'),
            $script:AppName, 'OK', 'Warning')
    }
    if ($fehler.Count -gt 0) {
        [void][System.Windows.MessageBox]::Show(
            ((T 'Bei {0} Charakter(en) hat es nicht geklappt:') -f $fehler.Count) + "`n`n" + [string]::Join([Environment]::NewLine, $fehler),
            $script:AppName, 'OK', 'Warning')
    }
})

$win.FindName('BtnRename').Add_Click({
    # Bewusst nur ein Charakter auf einmal: jeder braucht einen eigenen neuen
    # Namen, eine Sammelaktion gäbe es dafür nicht.
    $rows = @(Get-SelectedCharRows)
    if ($rows.Count -ne 1) {
        [void][System.Windows.MessageBox]::Show(
            (T 'Bitte links genau einen Charakter auswählen. Umbenannt wird immer einer nach dem anderen.'),
            $script:AppName, 'OK', 'Information')
        return
    }

    $row = $rows[0]
    if ($row.Parked) {
        [void][System.Windows.MessageBox]::Show(
            (T 'Dieser Charakter ist geparkt. Zum Umbenennen muss er erst zurückgeholt werden - nur dann greift die Sicherung, die vorher angelegt wird.'),
            $script:AppName, 'OK', 'Information')
        return
    }

    $neu = Show-NameDialog -Row $row -Mode rename
    if (-not $neu) { Set-Status (T 'Umbenennen abgebrochen.'); return }

    [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
    try {
        $erg = Rename-Character -CharName $row.Name -NewName $neu
    } catch {
        [System.Windows.Input.Mouse]::OverrideCursor = $null
        [void][System.Windows.MessageBox]::Show($_.Exception.Message, $script:AppName, 'OK', 'Warning')
        Update-All
        return
    } finally {
        [System.Windows.Input.Mouse]::OverrideCursor = $null
    }

    Update-All
    Set-Status ((T "'{0}' heißt jetzt '{1}' - {2} Datei(en) umbenannt, vorher gesichert.") -f $erg.OldName, $erg.NewName, $erg.Files.Count)

    if ($erg.D2RStartedDuring) {
        [void][System.Windows.MessageBox]::Show(
            (T 'D2R wurde während des Umbenennens gestartet. Die Dateien sind vollständig umbenannt, aber prüfe im Spiel, ob alles stimmt.'),
            $script:AppName, 'OK', 'Warning')
    }
})

$win.FindName('BtnCopy').Add_Click({
    $rows = @(Get-SelectedCharRows)
    if ($rows.Count -ne 1) {
        [void][System.Windows.MessageBox]::Show(
            (T 'Bitte links genau einen Charakter auswählen. Kopiert wird immer einer nach dem anderen.'),
            $script:AppName, 'OK', 'Information')
        return
    }

    $row = $rows[0]
    if ($row.Parked) {
        [void][System.Windows.MessageBox]::Show(
            (T 'Dieser Charakter ist geparkt. Zum Duplizieren muss er erst zurückgeholt werden.'),
            $script:AppName, 'OK', 'Information')
        return
    }

    $neu = Show-NameDialog -Row $row -Mode copy
    if (-not $neu) { Set-Status (T 'Duplizieren abgebrochen.'); return }

    [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
    try {
        $erg = Copy-Character -CharName $row.Name -NewName $neu
    } catch {
        [System.Windows.Input.Mouse]::OverrideCursor = $null
        [void][System.Windows.MessageBox]::Show($_.Exception.Message, $script:AppName, 'OK', 'Warning')
        Update-All
        return
    } finally {
        [System.Windows.Input.Mouse]::OverrideCursor = $null
    }

    Update-All
    Set-Status ((T "Kopie von '{0}' liegt als '{1}' bereit - {2} Datei(en), Original unverändert.") -f $erg.Source, $erg.Copy, $erg.Files.Count)

    if ($erg.D2RStartedDuring) {
        [void][System.Windows.MessageBox]::Show(
            (T 'D2R wurde während des Duplizierens gestartet. Die Kopie ist vollständig, aber prüfe im Spiel, ob alles stimmt.'),
            $script:AppName, 'OK', 'Warning')
    }
})

$win.FindName('BtnDeleteChar').Add_Click({
    $rows = @(Get-SelectedCharRows)
    if ($rows.Count -ne 1) {
        [void][System.Windows.MessageBox]::Show(
            (T 'Bitte links genau einen Charakter auswählen. Gelöscht wird immer einer nach dem anderen.'),
            $script:AppName, 'OK', 'Information')
        return
    }

    $row = $rows[0]
    if ($row.Parked) {
        [void][System.Windows.MessageBox]::Show(
            (T 'Dieser Charakter ist geparkt. Zum Löschen muss er erst zurückgeholt werden.'),
            $script:AppName, 'OK', 'Information')
        return
    }

    if (Test-D2RRunning) {
        [void][System.Windows.MessageBox]::Show(
            (T 'D2R läuft gerade. Zum Löschen muss das Spiel beendet sein.'),
            $script:AppName, 'OK', 'Warning')
        return
    }

    # Rückfrage mit Namen, Klasse und Level ausgeschrieben: bei einer
    # Mehrfachauswahl von Charakteren mit ähnlichen Namen ist der markierte
    # schnell ein anderer als der gemeinte.
    $frage = ((T "Charakter '{0}' ({1}, Level {2}) wirklich löschen?") -f $row.Name, $row.ClassName, $row.Level) + "`n`n" +
             (T 'Vorher wird automatisch gesichert, und die Dateien wandern in den Papierkorb des Programms - sie sind also nicht sofort weg.') + "`n`n" +
             (T 'Wer den Charakter nur aus der Charakterauswahl von D2R nehmen will, sollte ihn stattdessen parken.')
    if ([System.Windows.MessageBox]::Show($frage, (T 'Charakter löschen'), 'YesNo', 'Warning') -ne 'Yes') {
        Set-Status (T 'Löschen abgebrochen.')
        return
    }

    [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
    try {
        $erg = Remove-CharacterToTrash -CharName $row.Name
    } catch {
        [System.Windows.Input.Mouse]::OverrideCursor = $null
        [void][System.Windows.MessageBox]::Show($_.Exception.Message, $script:AppName, 'OK', 'Warning')
        Update-All
        return
    } finally {
        [System.Windows.Input.Mouse]::OverrideCursor = $null
    }

    Update-All
    Set-Status ((T "'{0}' ist gelöscht - {1} Datei(en) im Papierkorb, Sicherung angelegt.") -f $erg.Char, $erg.Files.Count)

    if ($erg.D2RStartedDuring) {
        [void][System.Windows.MessageBox]::Show(
            (T 'D2R wurde während des Löschens gestartet. Die Dateien sind vollständig im Papierkorb, aber prüfe im Spiel, ob alles stimmt.'),
            $script:AppName, 'OK', 'Warning')
    }
})

$win.FindName('BtnUnpark').Add_Click({
    $rows    = @(Get-SelectedCharRows)
    $geparkt = @($rows | Where-Object { $_.Parked })
    if ($geparkt.Count -eq 0) {
        [void][System.Windows.MessageBox]::Show(
            (T 'Bitte links mindestens einen geparkten Charakter auswählen. Geparkte stehen blass und kursiv in der Liste, mit ihrem Projekt in der letzten Spalte.'),
            $script:AppName, 'OK', 'Information')
        return
    }

    if (Test-D2RRunning) {
        [void][System.Windows.MessageBox]::Show(
            (T 'D2R läuft gerade. Zum Zurückholen muss das Spiel beendet sein.'),
            $script:AppName, 'OK', 'Warning')
        return
    }

    $namen = @($geparkt | ForEach-Object { $_.Name })
    $ans = [System.Windows.MessageBox]::Show(
        (((T '{0} Charakter(e) zurückholen?') -f $namen.Count) + "`n`n" + ($namen -join ', ') + "`n`n" +
         (T 'Sie stehen danach wieder in der Charakterauswahl von D2R.')),
        (T 'Zurückholen'), 'YesNo', 'Question')
    if ($ans -ne 'Yes') { Set-Status (T 'Zurückholen abgebrochen.'); return }

    $zurueck = 0; $fehler = @()
    [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
    try {
        foreach ($r in $geparkt) {
            try {
                $null = Restore-CharacterFromProject -Project $r.Project -CharName $r.Name
                $zurueck++
            } catch {
                $fehler += "$($r.Name) : $($_.Exception.Message)"
            }
        }
    } finally {
        [System.Windows.Input.Mouse]::OverrideCursor = $null
    }

    Update-All
    Set-Status ((T '{0} Charakter(e) zurückgeholt - sie stehen wieder in der Charakterauswahl von D2R.') -f $zurueck)

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
    $recs = @(Get-SelectedSnapshotRecords)
    if ($recs.Count -eq 0) {
        [void][System.Windows.MessageBox]::Show((T 'Bitte mindestens einen Eintrag in der Liste auswählen.'), $script:AppName, 'OK', 'Information')
        return
    }

    $ausPapierkorb = @($recs | Where-Object { $_.kind -eq 'trash' })

    if ($recs.Count -eq 1) {
        $rec     = $recs[0]
        $created = Format-Timestamp $rec.created (Get-DateFormat)
        $what    = switch ($rec.kind) {
            'full'  { T 'Kompletter Ordner' }
            'trash' { (T 'Papierkorb') + " - " + (T 'Charakter') + " '$($rec.char)'" }
            default { (T 'Charakter') + " '$($rec.char)'" }
        }
        $kopf = (T 'Diesen Eintrag endgültig löschen?') + "`n`n$what " + $created + "`n" + (T 'Label:') + " $($rec.label)"
    } else {
        $summe = [long](@($recs | ForEach-Object { [long]$_.sizeBytes }) | Measure-Object -Sum).Sum
        $kopf  = ((T '{0} markierte Einträge endgültig löschen? Zusammen {1}.') -f $recs.Count, (Format-Size $summe))
        # Die ersten Namen ausschreiben: bei Mehrfachauswahl sieht man sonst
        # nicht, ob versehentlich eine Zeile mehr markiert war.
        $namen = @($recs | ForEach-Object { if ($_.kind -eq 'full') { T 'Kompletter Ordner' } else { $_.char } } | Select-Object -First 8)
        $kopf += "`n`n" + ($namen -join ', ')
        if ($recs.Count -gt $namen.Count) { $kopf += ' ' + ((T '... und {0} weitere') -f ($recs.Count - $namen.Count)) }
    }

    # Bei Papierkorb-Einträgen liegen die Originaldateien im Ordner. "Die
    # Spielstände bleiben unberührt" wäre zwar wahr, klänge aber harmloser als
    # es ist: man wirft den Rückweg weg, nicht eine Kopie.
    $hinweis = if ($ausPapierkorb.Count -eq $recs.Count) {
        T 'Damit ist der schnelle Rückweg weg. Die Sicherungen, die vor dem Löschen angelegt wurden, bleiben bestehen.'
    } elseif ($ausPapierkorb.Count -gt 0) {
        ((T 'Darunter sind {0} Papierkorb-Eintrag/-Einträge - für die ist danach der schnelle Rückweg weg.') -f $ausPapierkorb.Count) +
        "`n" + (T 'Die Spielstände selbst bleiben unberührt.')
    } else {
        T 'Die Spielstände selbst bleiben unberührt.'
    }

    $titel = if ($ausPapierkorb.Count -eq $recs.Count -and $recs.Count -gt 0) { T 'Aus dem Papierkorb löschen' } else { T 'Löschen' }
    if ([System.Windows.MessageBox]::Show(($kopf + "`n`n" + $hinweis), $titel, 'YesNo', 'Warning') -ne 'Yes') { return }

    $weg = 0; $fehler = @()
    [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
    try {
        foreach ($rec in $recs) {
            try { Remove-Snapshot $rec; $weg++ }
            catch { $fehler += "$($rec.char): $($_.Exception.Message)" }
        }
    } finally {
        [System.Windows.Input.Mouse]::OverrideCursor = $null
    }

    Clear-Details
    Update-All
    Set-Status ((T '{0} Eintrag/Einträge gelöscht.') -f $weg)

    if ($fehler.Count -gt 0) {
        [void][System.Windows.MessageBox]::Show(
            ((T 'Löschen fehlgeschlagen:') + "`n`n" + [string]::Join([Environment]::NewLine, $fehler)),
            $script:AppName, 'OK', 'Error')
    }
})

# Rechtsklick auf die Liste. Die Einträge lösen dieselben Knöpfe aus, statt deren
# Logik ein zweites Mal hinzuschreiben - sonst laufen Menü und Knopfleiste über
# kurz oder lang auseinander.
$script:SnapMenu = New-Object System.Windows.Controls.ContextMenu

$mnuRestore = New-Object System.Windows.Controls.MenuItem
$mnuRestore.Header = T 'Wiederherstellen...'
$mnuRestore.Add_Click({
    $BtnRestore.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
})
[void]$script:SnapMenu.Items.Add($mnuRestore)

$script:MnuDelete = New-Object System.Windows.Controls.MenuItem
$script:MnuDelete.Header = T 'Löschen'
$script:MnuDelete.Add_Click({
    $BtnDelete.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
})
[void]$script:SnapMenu.Items.Add($script:MnuDelete)

$GridSnaps.ContextMenu = $script:SnapMenu

# WPF markiert beim Rechtsklick **nicht** von selbst die Zeile darunter. Ohne das
# hier stünde das Menü über einer Zeile, während die Markierung noch woanders
# liegt - und man löschte den falschen Eintrag. Deshalb erst markieren, dann das
# Menü aufgehen lassen.
$GridSnaps.Add_PreviewMouseRightButtonDown({
    param($sender, $e)
    $obj = $e.OriginalSource
    while ($obj -and -not ($obj -is [System.Windows.Controls.DataGridRow])) {
        if (-not ($obj -is [System.Windows.DependencyObject])) { break }
        $obj = [System.Windows.Media.VisualTreeHelper]::GetParent($obj)
    }
    if ($obj -is [System.Windows.Controls.DataGridRow]) {
        # Eine bestehende Mehrfachauswahl nicht zerstören: wer mehrere Zeilen
        # markiert hat und eine davon mit rechts anklickt, meint alle.
        if (-not $obj.IsSelected) { $GridSnaps.SelectedItem = $obj.Item }
    }
})

# Beschriftung erst beim Aufklappen setzen: dann stimmt sie auch, wenn die
# Markierung sich gerade eben geändert hat.
$script:SnapMenu.Add_Opened({
    $recs = @(Get-SelectedSnapshotRecords)
    Update-DeleteButtonLabel
    $script:MnuDelete.Header    = $BtnDelete.Content
    $script:MnuDelete.IsEnabled = ($recs.Count -gt 0)
    # Wiederherstellen geht immer nur für einen: der Dialog fragt nach Zielname
    # und Stash, und beides ist pro Charakter eine eigene Entscheidung.
    $mnuRestore.IsEnabled       = ($recs.Count -eq 1)
}.GetNewClosure())

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

# --- Haftungshinweis ---------------------------------------------------------
# Muss einmal bestätigt werden, sonst startet das Programm nicht. Die Bestätigung
# steht in der config.json und gilt für die jeweilige Fassung des Hinweises:
# ändert sich der Text inhaltlich, wird $script:DisclaimerVersion erhöht und
# jeder bestätigt erneut.

function Test-DisclaimerAccepted {
    $d = $script:Config.Disclaimer
    if (-not $d -or -not $d.PSObject.Properties['Version']) { return $false }
    $v = 0
    if (-not [int]::TryParse([string]$d.Version, [ref]$v)) { return $false }
    $v -ge $script:DisclaimerVersion
}

# Öffnet die Bedienungsanleitung im Standardprogramm für .md-Dateien. Gibt es
# keines, springt Windows nicht etwa auf den Editor, sondern meldet einen Fehler -
# deshalb der ausdrückliche Rückfall.
function Open-Anleitung {
    $datei = if ($script:Config.Language -eq 'en') { 'INSTRUCTIONS.md' } else { 'ANLEITUNG.md' }
    $pfad  = Join-Path $script:ScriptDir $datei
    if (-not (Test-Path -LiteralPath $pfad)) {
        [void][System.Windows.MessageBox]::Show(
            (T 'Die Anleitung wurde nicht gefunden:') + "`n`n$pfad", $script:AppName, 'OK', 'Information')
        return
    }
    try { Start-Process -FilePath $pfad } catch { Start-Process -FilePath 'notepad.exe' -ArgumentList "`"$pfad`"" }
}

# EIN Fenster, zwei Betriebsarten - damit der Hinweistext nur an einer Stelle im
# Code steht. Ohne -ReadOnly ist es die Sperre beim ersten Start (Haken +
# Einverstanden), mit -ReadOnly das Nachlesen über den Knopf "Über".
function Show-DisclaimerDialog {
    param([switch]$ReadOnly)

    $dlg    = ConvertFrom-Xaml $DisclaimerXaml
    $chk    = $dlg.FindName('ChkGelesen')
    $btnOk  = $dlg.FindName('BtnOk')
    $btnAbb = $dlg.FindName('BtnCancel')
    $btnAnl = $dlg.FindName('BtnAnleitung')

    # Den eigenen Pfad zeigen: aus "kopier deinen Spielstand-Ordner" wird damit
    # eine Anweisung, der man ohne Suchen folgen kann.
    $dlg.FindName('TxtPfad').Text = $script:Config.SavePath
    $btnAnl.Add_Click({ Open-Anleitung }.GetNewClosure())

    if ($ReadOnly) {
        $dlg.Owner   = $win
        $dlg.Title   = (T 'Über') + " - $script:AppName"
        $dlg.FindName('TxtKopf').Text = "$script:AppName $script:AppVersion"

        $d = $script:Config.Disclaimer
        if ($d -and $d.PSObject.Properties['AcceptedAt'] -and $d.AcceptedAt) {
            $txtB = $dlg.FindName('TxtBestaetigt')
            $txtB.Text = (T 'Dieser Hinweis wurde bestätigt am {0}.') -f (Format-Timestamp $d.AcceptedAt (Get-DateFormat))
            $txtB.Visibility = 'Visible'
        }

        # Die Lizenz liegt als eigene Datei neben dem Programm und wird beim Bauen
        # ins Weitergabe-Paket gelegt. Fehlt sie, wird das gesagt statt ein leeres
        # Feld zu zeigen.
        $lizPfad = Join-Path $script:ScriptDir 'LICENSE'
        $txtLiz  = $dlg.FindName('TxtLizenz')
        if (Test-Path -LiteralPath $lizPfad) {
            try { $txtLiz.Text = [System.IO.File]::ReadAllText($lizPfad) }
            catch { $txtLiz.Text = (T 'Die Lizenzdatei konnte nicht gelesen werden.') }
        } else {
            $txtLiz.Text = (T 'Die Datei LICENSE liegt nicht neben dem Programm.')
        }
        $dlg.FindName('PnlLizenz').Visibility = 'Visible'

        $chk.Visibility   = 'Collapsed'
        $btnOk.Visibility = 'Collapsed'
        $btnAbb.Content   = T 'Schließen'
        [void]$dlg.ShowDialog()
        return $true
    }

    # Sperre beim ersten Start: der Knopf bleibt grau, bis der Haken sitzt.
    $btnAnl.Visibility = 'Collapsed'
    $chk.Add_Click({ $btnOk.IsEnabled = [bool]$chk.IsChecked }.GetNewClosure())
    $btnOk.Add_Click({ $dlg.DialogResult = $true }.GetNewClosure())

    [bool]$dlg.ShowDialog()
}

function Confirm-Disclaimer {
    if (Test-DisclaimerAccepted) { return $true }
    if (-not (Show-DisclaimerDialog)) { return $false }
    $script:Config.Disclaimer = [pscustomobject]@{
        Version    = $script:DisclaimerVersion
        AcceptedAt = (Get-Date).ToString('o')
        AppVersion = $script:AppVersion
    }
    try { Export-Config } catch { }
    $true
}

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
Restore-View

# Beim Schließen merken, was der Nutzer eingestellt hat. Nach "Ansicht
# zurücksetzen" bewusst nicht - sonst schriebe genau dieses Speichern die eben
# gelöschten Werte wieder zurück, und der Knopf bliebe wirkungslos.
$win.Add_Closing({ if (-not $script:SkipViewSave) { Save-View } })

# Ohne Bestätigung des Haftungshinweises startet das Hauptfenster nicht.
if (Confirm-Disclaimer) {
    [void]$win.ShowDialog()
}

# Sprachwechsel und "Ansicht zurücksetzen": mit derselben PowerShell-Version neu
# starten, mit der wir laufen.
if ($script:RestartRequested -and $script:ScriptPath) {
    # ZUERST freigeben, dann starten. Andernfalls trifft der neue Prozess auf den
    # noch gehaltenen Mutex, haelt sich selbst fuer eine zweite Instanz und
    # beendet sich - der Sprachwechsel wuerde das Programm schliessen statt es
    # neu zu oeffnen.
    Exit-EinzelInstanz

    $exe = (Get-Process -Id $PID).Path
    Start-Process -FilePath $exe -ArgumentList @(
        '-NoProfile','-ExecutionPolicy','Bypass','-Sta','-WindowStyle','Hidden','-File',"`"$script:ScriptPath`""
    )
} else {
    Exit-EinzelInstanz
}
