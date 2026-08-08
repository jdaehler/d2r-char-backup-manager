$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework, System.IO.Compression, System.IO.Compression.FileSystem -EA SilentlyContinue

# Ohne STA laesst sich kein WPF-Fenster bauen, und die Pruefung der
# Live-Namenspruefung baut eines. Windows PowerShell 5.1 und PowerShell 7 starten
# auf Windows beide mit STA - am 08.08.2026 nachgemessen, in PS7 also kein
# Sonderfall. Wer aber mit -Mta startet, bekaeme sonst einen kryptischen Fehler
# aus der Tiefe von WPF statt einer Ansage, was fehlt.
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    throw 'Dieser Testlauf braucht STA. Bitte mit dem Schalter -Sta starten.'
}

$src = Join-Path $PSScriptRoot 'D2RCharBackupManager.ps1'
$ast = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$null, [ref]$null)
foreach ($a in $ast.FindAll({param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst]}, $false)) {
  # $RestoreXaml ohne script:-Praefix, damit der Dialog fuer die Pruefung der
  # Live-Namenspruefung wirklich gebaut werden kann - ohne ihn anzuzeigen.
  if ($a.Left.Extent.Text -match '^\$script:(ExcludedExtensions|DefaultClassNames|AppName|AppVersion|TextsEn)$' -or
      $a.Left.Extent.Text -eq '$RestoreXaml') { Invoke-Expression $a.Extent.Text }
}
foreach ($f in $ast.FindAll({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]}, $false)) {
  Invoke-Expression $f.Extent.Text
}

# Die D2R-Erkennung wird fuer den Testlauf ersetzt. Die Sandbox arbeitet in
# einem Wegwerf-Ordner unter TEMP und hat mit dem echten Spiel nichts zu tun -
# ohne diesen Ersatz braeche der Testlauf ab, sobald jemand gerade spielt, und
# der Fall "D2R laeuft" waere ueberhaupt nicht pruefbar, weil man ihn nicht auf
# Kommando herstellen kann. Im Programm bleibt der Schutz unangetastet: dort
# fuehrt der einzige Get-Process-Aufruf durch genau diese eine Funktion, ueber
# die auch alle Aufrufstellen laufen.
$script:FakeD2RRunning = $false
function Test-D2RRunning { $script:FakeD2RRunning }

# Feste Sandbox neben dem Skript statt eines Wegwerf-Ordners unter TEMP: sie
# bleibt nach dem Lauf stehen, damit man hineinsehen kann, was die Tests gebaut
# haben. Zu Beginn wird sie geleert - die Tests brauchen einen bekannten
# Ausgangszustand, sonst faenden sie Snapshots vom letzten Durchlauf vor.
$root   = Join-Path $PSScriptRoot '_sandbox'
$saves  = Join-Path $root 'saves'
$backup = Join-Path $root 'backup'

# Sicherung gegen ein falsch gesetztes $root: hier wird rekursiv geloescht, und
# das darf ausschliesslich den Ordner "_sandbox" neben diesem Skript treffen.
if ((Split-Path $root -Leaf) -ne '_sandbox' -or (Split-Path $root -Parent) -ne $PSScriptRoot) {
    throw "Sandbox-Pfad sieht falsch aus, es wird nichts geloescht: $root"
}
if (Test-Path -LiteralPath $root) { [System.IO.Directory]::Delete($root, $true) }
New-Item -ItemType Directory -Path $saves, $backup -Force | Out-Null

function New-FakeD2S($Path, $Version, $ClassId, $Level, $Status) {
  $b = New-Object byte[] 128
  [BitConverter]::GetBytes([uint32]2857740885).CopyTo($b, 0)
  [BitConverter]::GetBytes([uint32]$Version).CopyTo($b, 4)
  [BitConverter]::GetBytes([uint32]128).CopyTo($b, 8)
  $base = if ($Version -ge 100) { 0x14 } else { 0x24 }
  $b[$base] = $Status; $b[$base+4] = $ClassId; $b[$base+5] = 0x10; $b[$base+6] = 0x1E; $b[$base+7] = $Level
  [BitConverter]::GetBytes([uint32]1785000000).CopyTo($b, $base+12)
  [System.IO.File]::WriteAllBytes($Path, $b)
}

$stashPath = Join-Path $saves 'ModernSharedStashSoftCoreV2.d2i'
New-FakeD2S (Join-Path $saves 'TestBarb.d2s') 105 4 42 0x20
New-FakeD2S (Join-Path $saves 'TestHC.d2s')    99 6 88 0x24
foreach ($e in '.ctl','.key','.ma0','.map') { [System.IO.File]::WriteAllText((Join-Path $saves "TestBarb$e"), 'x') }
[System.IO.File]::WriteAllText($stashPath, 'stash-soft')
[System.IO.File]::WriteAllText((Join-Path $saves 'TestBarb143022.bak'), 'nicht-teil-des-chars')
# Reste von Online-Charakteren: einmal unter fremdem Namen (so sieht es im echten
# Ordner aus), einmal unter dem Namen eines lokalen Charakters - Letzteres prueft
# den Filter auch im Charakter-Dateisatz.
[System.IO.File]::WriteAllText((Join-Path $saves 'OnlineHeld176365355.ctlo'), 'online-steuerung')
[System.IO.File]::WriteAllText((Join-Path $saves 'OnlineHeld176365355.keyo'), 'online-belegung')
[System.IO.File]::WriteAllText((Join-Path $saves 'Geloescht99999999.ctlo'), '')
[System.IO.File]::WriteAllText((Join-Path $saves 'TestBarb.ctlo'), 'gleicher-name-aber-online')

$script:Config = [pscustomobject]@{ SavePath = $saves; BackupPath = $backup; ClassNames = $script:DefaultClassNames }
Import-Index

$pass = 0; $fail = 0
function Check($name, $cond, $detail = '') {
  if ($cond) { $script:pass++; "  [ok]   $name" } else { $script:fail++; "  [FAIL] $name  $detail" }
}

"--- Header-Parsing ---"
$i1 = Get-D2SInfo (Join-Path $saves 'TestBarb.d2s')
$i2 = Get-D2SInfo (Join-Path $saves 'TestHC.d2s')
Check "v105 Klasse=Barbar"    ($i1.ClassName -eq 'Barbar') $i1.ClassName
Check "v105 Level=42"         ($i1.Level -eq 42)           $i1.Level
Check "v105 Softcore"         (-not $i1.Hardcore)
Check "v99  Klasse=Assassine" ($i2.ClassName -eq 'Assassine') $i2.ClassName
Check "v99  Level=88"         ($i2.Level -eq 88)           $i2.Level
Check "v99  Hardcore erkannt" ($i2.Hardcore)

"--- Dateisatz-Erkennung ---"
$files = Get-CharacterFiles 'TestBarb'
Check "5 Dateien erkannt" ($files.Count -eq 5) $files.Count
Check "zeitgestempelte .bak ausgeschlossen" (@($files | Where-Object { $_.Extension -eq '.bak' }).Count -eq 0)
Check "gleichnamige .ctlo ausgeschlossen" (@($files | Where-Object { $_.Extension -eq '.ctlo' }).Count -eq 0)
Check "2 Charaktere gelistet" ((Get-Characters).Count -eq 2)
Check "Online-Reste sind keine Charaktere" (@(Get-Characters | Where-Object { $_.Name -like 'OnlineHeld*' -or $_.Name -like 'Geloescht*' }).Count -eq 0)

"--- Snapshot anlegen ---"
$snap = New-Snapshot -Kind char -CharName 'TestBarb' -Label 'Vor Uber' -Tags @('hardcore','test') -Note 'Notiz'
$ordner = Join-Path $backup $snap.pfad
Check "Snapshot-Ordner existiert" (Test-Path $ordner) $snap.pfad
Check "Stash mitgesichert"     ($snap.includesStash)
Check "Metadaten Level 42"     ($snap.level -eq 42)
Check "Tags gespeichert"       ((@($snap.tags) -contains 'hardcore') -and (@($snap.tags) -contains 'test'))
Check "index.json geschrieben" (Test-Path (Join-Path $backup 'index.json'))

"--- Ablage im Explorer nachvollziehbar? ---"
Check "liegt unter Charaktere\TestBarb" ($snap.pfad -like 'Charaktere\TestBarb\*') $snap.pfad
Check "Ordnername nennt Level und Klasse" ((Split-Path -Leaf $ordner) -match 'Lvl42 Barbar') (Split-Path -Leaf $ordner)
Check "Ordnername beginnt mit Datum" ((Split-Path -Leaf $ordner) -match '^\d{4}-\d{2}-\d{2}_\d{6}')
$dateien = @(Get-ChildItem $ordner -File | ForEach-Object { $_.Name })
Check "5 Charakterdateien + _INFO.txt" ($dateien.Count -eq 6) ($dateien -join ' ')
Check "_INFO.txt vorhanden" ($dateien -contains '_INFO.txt')
Check "Spielstanddatei direkt greifbar" ($dateien -contains 'TestBarb.d2s')
Check "SharedStash als Unterordner" (Test-Path (Join-Path $ordner 'SharedStash\ModernSharedStashSoftCoreV2.d2i'))
Check "_LIESMICH.txt im Backup-Ordner" (Test-Path (Join-Path $backup '_LIESMICH.txt'))
$info = Get-Content (Join-Path $ordner '_INFO.txt') -Raw
Check "_INFO nennt Charakter und Label" ($info -match 'TestBarb' -and $info -match 'Vor Uber')
Check "_INFO enthaelt Handanleitung" ($info -match 'VON HAND WIEDERHERSTELLEN')
Check "unkomprimiert ablegt" (((Get-Item (Join-Path $ordner 'TestBarb.d2s')).Length) -eq ((Get-Item (Join-Path $saves 'TestBarb.d2s')).Length))

"--- Wiederherstellen unter anderem Namen ---"
[System.IO.File]::WriteAllText($stashPath, 'STASH-VERAENDERT')
$restored = Restore-Snapshot -Snapshot $snap -TargetName 'NeuerBarb' -SkipSafetyBackup
Check "5 Dateien zurueckgeschrieben" ($restored.Count -eq 5) $restored.Count
Check "NeuerBarb.d2s angelegt" (Test-Path (Join-Path $saves 'NeuerBarb.d2s'))
Check "NeuerBarb.ma0 angelegt" (Test-Path (Join-Path $saves 'NeuerBarb.ma0'))
Check "Original bleibt bestehen" (Test-Path (Join-Path $saves 'TestBarb.d2s'))
$ni = Get-D2SInfo (Join-Path $saves 'NeuerBarb.d2s')
Check "Kopie intakt (Barbar Lvl 42)" ($ni.Valid -and $ni.ClassName -eq 'Barbar' -and $ni.Level -eq 42)
Check "Stash NICHT angefasst" ([System.IO.File]::ReadAllText($stashPath) -eq 'STASH-VERAENDERT')

"--- Wiederherstellen MIT Stash ---"
$null = Restore-Snapshot -Snapshot $snap -TargetName 'TestBarb' -RestoreStash -SkipSafetyBackup
Check "Stash jetzt zurueckgesetzt" ([System.IO.File]::ReadAllText($stashPath) -eq 'stash-soft')

"--- Automatische Sicherheitskopie ---"
$before = $script:Index.snapshots.Count
$null = Restore-Snapshot -Snapshot $snap -TargetName 'TestBarb'
Check "Sicherheitskopie angelegt" ($script:Index.snapshots.Count -eq $before + 1) $script:Index.snapshots.Count
Check "als Auto markiert" (@($script:Index.snapshots)[-1].automatic)

"--- Gesamtstand ---"
$alleImOrdner = @(Get-ChildItem $saves -File)
$expected = @($alleImOrdner | Where-Object { $script:ExcludedExtensions -notcontains $_.Extension.ToLowerInvariant() }).Count
$full = New-Snapshot -Kind full -Label 'Alles'
Check "enthaelt alle nicht ausgeschlossenen Dateien ($expected)" ($full.fileCount -eq $expected) $full.fileCount
Check "Ordner enthielt ueberhaupt Ausschlussware" (@($alleImOrdner).Count -gt $expected) "$(@($alleImOrdner).Count) vs $expected"
$vollOrdner = Join-Path $backup $full.pfad
Check "keine .ctlo in der Komplettsicherung" (@(Get-ChildItem $vollOrdner -File -Filter '*.ctlo').Count -eq 0)
Check "keine .keyo in der Komplettsicherung" (@(Get-ChildItem $vollOrdner -File -Filter '*.keyo').Count -eq 0)
$vollInfo = Get-Content (Join-Path $vollOrdner '_INFO.txt') -Raw
Check "_INFO nennt die Online-Ausnahme" ($vollInfo -match 'Online-Charaktere sind nicht dabei')

"--- Namenspruefung ---"
# Regel laut Arreat Summit: 2-15 Zeichen, nur A-Z, hoechstens ein "_" oder "-"
# und das nicht am Rand. Die Grenzfaelle unten stammen aus dem echten Bestand
# des Captains - alle 33 Namen muessen die Pruefung passieren.
Check "'Ab' gueltig"              ((Test-D2RName 'Ab') -eq '')
Check "'Neuer_Barb' gueltig"      ((Test-D2RName 'Neuer_Barb') -eq '')
Check "'Amazone_Poison' gueltig"  ((Test-D2RName 'Amazone_Poison') -eq '')
Check "'HM-ONE' gueltig"          ((Test-D2RName 'HM-ONE') -eq '')
Check "'jdASSA-One' gueltig"      ((Test-D2RName 'jdASSA-One') -eq '')
Check "15 Zeichen gueltig"        ((Test-D2RName 'Abcdefghijklmno') -eq '')
Check "'1Barb' abgelehnt"         ((Test-D2RName '1Barb') -ne '')
Check "'A' abgelehnt"             ((Test-D2RName 'A') -ne '')
Check "'a_b-c' abgelehnt"         ((Test-D2RName 'a_b-c') -ne '')
Check "16 Zeichen abgelehnt"      ((Test-D2RName 'Abcdefghijklmnop') -ne '')
# Neu ab 08.08.2026: die alte Regel liess diese vier durch, D2R nimmt sie nicht.
Check "'jdBarb2' abgelehnt"       ((Test-D2RName 'jdBarb2') -ne '')
Check "'Sorc99' abgelehnt"        ((Test-D2RName 'Sorc99') -ne '')
Check "'jdBarb-' abgelehnt"       ((Test-D2RName 'jdBarb-') -ne '')
Check "'-jdBarb' abgelehnt"       ((Test-D2RName '-jdBarb') -ne '')
Check "'Neuer Barb' abgelehnt"    ((Test-D2RName 'Neuer Barb') -ne '')

"--- Live-Namenspruefung im Dialog ---"
# Der Wiederherstellen-Dialog wird gebaut, aber nicht angezeigt. Dann wird ins
# Namensfeld "getippt" und geprueft, ob Feld und Knopf richtig reagieren - das
# ist der Teil, den man sonst nur von Hand durch Klicken pruefen koennte.
$dlgT = ConvertFrom-Xaml $RestoreXaml
$boxT = $dlgT.FindName('TxtName')
$errT = $dlgT.FindName('TxtNameError')
$okT  = $dlgT.FindName('BtnOk')
$normalBrushT = $boxT.BorderBrush

Register-NameCheck -Box $boxT -ErrBox $errT -Ok $okT

$boxT.Text = 'GuterName'
Check "gueltig: Knopf frei"       ($okT.IsEnabled)
Check "gueltig: kein Fehlertext"  ($errT.Visibility -eq 'Collapsed')

$boxT.Text = 'jdBarb2'
Check "Ziffer: Knopf gesperrt"    (-not $okT.IsEnabled)
Check "Ziffer: Fehler sichtbar"   ($errT.Visibility -eq 'Visible')
Check "Ziffer: Feld rot"          ($boxT.BorderBrush -eq [System.Windows.Media.Brushes]::Firebrick)

$boxT.Text = 'jdBarb-'
Check "Trenner am Ende gesperrt"  (-not $okT.IsEnabled)

$boxT.Text = 'WiederGut'
Check "Erholung: Knopf frei"      ($okT.IsEnabled)
Check "Erholung: Rahmen zurueck"  ($boxT.BorderBrush -eq $normalBrushT)
Check "Erholung: Fehler weg"      ($errT.Visibility -eq 'Collapsed')

# Zusatzpruefung des Aufrufers: warnt nur (orange), sperrt aber nicht - so
# verhaelt sich die Namenskollision im Wiederherstellen-Dialog.
$dlgW = ConvertFrom-Xaml $RestoreXaml
$boxW = $dlgW.FindName('TxtName'); $errW = $dlgW.FindName('TxtNameError'); $okW = $dlgW.FindName('BtnOk')
Register-NameCheck -Box $boxW -ErrBox $errW -Ok $okW -ExtraBlocks $false -Extra { param($n) if ($n -eq 'Belegt') { 'schon da' } else { '' } }
$boxW.Text = 'Belegt'
Check "Warnung: Knopf bleibt frei" ($okW.IsEnabled)
Check "Warnung: Text sichtbar"     ($errW.Text -eq 'schon da')
Check "Warnung: Feld orange"       ($boxW.BorderBrush -eq [System.Windows.Media.Brushes]::DarkOrange)

# Dieselbe Zusatzpruefung, aber sperrend - so wird sie das Umbenennen nutzen.
$dlgB = ConvertFrom-Xaml $RestoreXaml
$boxB = $dlgB.FindName('TxtName'); $errB = $dlgB.FindName('TxtNameError'); $okB = $dlgB.FindName('BtnOk')
Register-NameCheck -Box $boxB -ErrBox $errB -Ok $okB -ExtraBlocks $true -Extra { param($n) if ($n -eq 'Belegt') { 'schon da' } else { '' } }
$boxB.Text = 'Belegt'
Check "sperrende Zusatzpruefung"   (-not $okB.IsEnabled)
$boxB.Text = 'Anders'
Check "danach wieder frei"         ($okB.IsEnabled)

"--- Snapshot loeschen ---"
$zp = Join-Path $backup $full.pfad
Remove-Snapshot $full
Check "Ordner entfernt" (-not (Test-Path $zp))
Check "aus Index entfernt" (@($script:Index.snapshots | Where-Object { $_.id -eq $full.id }).Count -eq 0)

"--- Letzte Sicherung eines Charakters loeschen ---"
$einzel = New-Snapshot -Kind char -CharName 'TestHC'
$charOrdner = Split-Path -Parent (Join-Path $backup $einzel.pfad)
Check "Charakterordner angelegt" (Test-Path $charOrdner)
Remove-Snapshot $einzel
Check "leerer Charakterordner mit entfernt" (-not (Test-Path $charOrdner)) $charOrdner
Check "Charaktere-Ordner bleibt bestehen" (Test-Path (Join-Path $backup 'Charaktere'))

"--- Neuladen des Index ---"
Import-Index
Check "Snapshots ueberleben Neustart" ($script:Index.snapshots.Count -gt 0) $script:Index.snapshots.Count
$re = @($script:Index.snapshots | Where-Object { $_.id -eq $snap.id })[0]
Check "Tags nach Neuladen erhalten" ((@($re.tags) -contains 'hardcore') -and (@($re.tags) -contains 'test')) (@($re.tags) -join ',')

"--- Projektnamen ---"
Check "leerer Name abgelehnt"        ((Test-ProjectName '') -ne '')
Check "Schraegstrich abgelehnt"      ((Test-ProjectName 'Alte/Helden') -ne '')
Check "fuehrendes Leerzeichen abgelehnt" ((Test-ProjectName ' Lager') -ne '')
Check "41 Zeichen abgelehnt"         ((Test-ProjectName ('x' * 41)) -ne '')
Check "'Alte Helden' gueltig"        ((Test-ProjectName 'Alte Helden') -eq '')

"--- Parken ---"
$projWurzel  = Join-Path $saves '_Projekte'
$projOrdner  = Join-Path $projWurzel 'Alte Helden'
$stashVor    = [System.IO.File]::ReadAllText($stashPath)
$snapsVor    = @($script:Index.snapshots).Count
$aktivVor    = @(Get-Characters).Count

$p = Move-CharacterToProject -CharName 'TestBarb' -Project 'Alte Helden'
Check "5 Dateien verschoben"            ($p.Files.Count -eq 5) $p.Files.Count
Check "aus dem Spielstand-Ordner weg"   (-not (Test-Path (Join-Path $saves 'TestBarb.d2s')))
Check "im Projektordner angekommen"     (Test-Path (Join-Path $projOrdner 'TestBarb.d2s'))
Check "verschoben statt kopiert"        (@(Get-ChildItem $saves -File | Where-Object { $_.BaseName -eq 'TestBarb' -and $script:ExcludedExtensions -notcontains $_.Extension.ToLowerInvariant() }).Count -eq 0)
Check "gleichnamige .ctlo bleibt liegen" (Test-Path (Join-Path $saves 'TestBarb.ctlo'))
Check "Online-Datei nicht mitgeparkt"   (-not (Test-Path (Join-Path $projOrdner 'TestBarb.ctlo')))
Check "Shared Stash bleibt liegen"      ([System.IO.File]::ReadAllText($stashPath) -eq $stashVor)
Check "Stash nicht mitgewandert"        (-not (Test-Path (Join-Path $projOrdner 'ModernSharedStashSoftCoreV2.d2i')))
Check "Pflicht-Snapshot angelegt"       (@($script:Index.snapshots).Count -eq $snapsVor + 1) @($script:Index.snapshots).Count
Check "Snapshot traegt Tag 'geparkt'"   (@(@($script:Index.snapshots)[-1].tags) -contains 'geparkt')
Check "_INFO.txt im Projektordner"      (Test-Path (Join-Path $projOrdner '_INFO.txt'))
$pinfo = Get-Content (Join-Path $projOrdner '_INFO.txt') -Raw
Check "_INFO warnt vor dem Loeschen"    ($pinfo -match 'keine Sicherungen')
Check "_INFO nennt den Charakter"       ($pinfo -match 'TestBarb')
Check "nicht mehr aktiv gelistet"       (@(Get-Characters | Where-Object { $_.Name -eq 'TestBarb' }).Count -eq 0)
Check "ein aktiver Charakter weniger"   (@(Get-Characters).Count -eq $aktivVor - 1)

$geparkt = @(Get-ParkedCharacters)
$g1 = @($geparkt | Where-Object { $_.Name -eq 'TestBarb' })
Check "als geparkt gelistet"            ($g1.Count -eq 1)
Check "Projekt im Datensatz"            ($g1[0].Project -eq 'Alte Helden') $g1[0].Project
Check "Parked-Kennzeichen gesetzt"      ($g1[0].Parked)
Check "Level bleibt lesbar (42)"        ($g1[0].Level -eq 42) $g1[0].Level
Check "Get-AllCharacters zeigt beide"   (@(Get-AllCharacters).Count -eq (@(Get-Characters).Count + $geparkt.Count))

"--- D2R laeuft: die Sperren greifen ---"
# Dieser Fall liess sich vorher gar nicht pruefen. Jetzt wird das laufende Spiel
# vorgetaeuscht, statt darauf zu warten, dass zufaellig gerade jemand spielt.
$script:FakeD2RRunning = $true
$snapsD = @($script:Index.snapshots).Count

$kamP = $false
try { $null = Move-CharacterToProject -CharName 'TestHC' -Project 'Verboten' } catch { $kamP = $true }
Check "Parken abgelehnt"                $kamP
Check "TestHC blieb im Spielstand"      (Test-Path (Join-Path $saves 'TestHC.d2s'))
Check "Projektordner nicht angelegt"    (-not (Test-Path (Join-Path $projWurzel 'Verboten')))
Check "kein Snapshot entstanden"        (@($script:Index.snapshots).Count -eq $snapsD)

$kamR = $false
try { $null = Restore-CharacterFromProject -Project 'Alte Helden' -CharName 'TestBarb' } catch { $kamR = $true }
Check "Zurueckholen abgelehnt"          $kamR
Check "geparkte Datei unangetastet"     (Test-Path (Join-Path $projOrdner 'TestBarb.d2s'))

# Sichern muss trotzdem gehen: es liest nur. Verboten ist das Verschieben, nicht
# das Kopieren - sonst koennte man vor dem Spielen nicht schnell sichern.
$snapLauf = New-Snapshot -Kind char -CharName 'TestHC' -Label 'Waehrend D2R laeuft'
Check "Sichern bleibt erlaubt"          ($null -ne $snapLauf)

$script:FakeD2RRunning = $false

"--- Parken: Namenskollision im Projekt ---"
New-FakeD2S (Join-Path $saves 'TestBarb.d2s') 105 4 42 0x20
$snapsVor2 = @($script:Index.snapshots).Count
$kam = $false
try { $null = Move-CharacterToProject -CharName 'TestBarb' -Project 'Alte Helden' } catch { $kam = $true }
Check "zweiter gleicher Name abgelehnt" $kam
Check "Datei blieb im Spielstand-Ordner" (Test-Path (Join-Path $saves 'TestBarb.d2s'))
Check "kein Snapshot bei Abbruch"       (@($script:Index.snapshots).Count -eq $snapsVor2) @($script:Index.snapshots).Count

"--- Namenskollision finden ---"
# Hier liegt 'TestBarb' zweimal: aktiv im Spielstand-Ordner und geparkt in
# 'Alte Helden'. Der aktive Fund hat Vorrang, er ist der naeherliegende.
$kolA = Get-NameKollision 'TestBarb'
Check "aktiver Fund gewinnt"            ($kolA.Kind -eq 'active') $kolA.Kind
Remove-Item (Join-Path $saves 'TestBarb.d2s') -Force
# Jetzt nur noch geparkt - genau der Fall, den eine Pruefung ohne Blick in
# _Projekte uebersehen wuerde.
$kolP = Get-NameKollision 'TestBarb'
Check "geparkter Fund erkannt"          ($kolP.Kind -eq 'parked') $kolP.Kind
Check "Projekt wird mitgeliefert"       ($kolP.Project -eq 'Alte Helden') $kolP.Project
$kolF = Get-NameKollision 'GibtEsNicht'
Check "freier Name ist frei"            ($kolF.Kind -eq '') $kolF.Kind

"--- Zurueckholen ---"
$r = Restore-CharacterFromProject -Project 'Alte Helden' -CharName 'TestBarb'
Check "5 Dateien zurueckgeholt"         ($r.Files.Count -eq 5) $r.Files.Count
Check "wieder im Spielstand-Ordner"     (Test-Path (Join-Path $saves 'TestBarb.d2s'))
Check "aus dem Projektordner weg"       (-not (Test-Path (Join-Path $projOrdner 'TestBarb.d2s')))
Check "leerer Projektordner entfernt"   (-not (Test-Path $projOrdner))
Check "_Projekte-Wurzel mit entfernt"   (-not (Test-Path $projWurzel))
Check "wieder aktiv gelistet"           (@(Get-Characters | Where-Object { $_.Name -eq 'TestBarb' }).Count -eq 1)
$rb = Get-D2SInfo (Join-Path $saves 'TestBarb.d2s')
Check "Datei intakt (Barbar Lvl 42)"    ($rb.Valid -and $rb.ClassName -eq 'Barbar' -and $rb.Level -eq 42)

"--- Zurueckholen unter anderem Namen ---"
$null = Move-CharacterToProject -CharName 'TestHC' -Project 'Testlager'
$r2 = Restore-CharacterFromProject -Project 'Testlager' -CharName 'TestHC' -TargetName 'Umbenannt'
Check "unter neuem Namen zurueck"       (Test-Path (Join-Path $saves 'Umbenannt.d2s'))
Check "alter Name nicht wieder da"      (-not (Test-Path (Join-Path $saves 'TestHC.d2s')))
$ui = Get-D2SInfo (Join-Path $saves 'Umbenannt.d2s')
Check "Kopie intakt (Assassine 88 HC)"  ($ui.Valid -and $ui.Level -eq 88 -and $ui.Hardcore)

"--- Zurueckholen: Name schon vergeben ---"
$null = Move-CharacterToProject -CharName 'TestBarb' -Project 'Lager2'
New-FakeD2S (Join-Path $saves 'TestBarb.d2s') 105 4 1 0x20
$kam2 = $false
try { $null = Restore-CharacterFromProject -Project 'Lager2' -CharName 'TestBarb' } catch { $kam2 = $true }
Check "Kollision abgelehnt"             $kam2
Check "geparkte Datei unangetastet"     (Test-Path (Join-Path $saves '_Projekte\Lager2\TestBarb.d2s'))
Check "vorhandener Charakter unangetastet" ((Get-D2SInfo (Join-Path $saves 'TestBarb.d2s')).Level -eq 1)

"--- Kompletter Ordner sieht geparkte Charaktere nicht ---"
# Festgehalten, damit es nicht unbemerkt kippt: "Alles sichern" nimmt nur
# Dateien aus dem Wurzelverzeichnis, geparkte Charaktere liegen im Unterordner
# und sind deshalb NICHT dabei. Abgesichert sind sie durch den Pflicht-Snapshot,
# den das Parken anlegt.
$full2 = New-Snapshot -Kind full -Label 'Mit geparkten Charakteren'
$fullOrdner = Join-Path $backup $full2.pfad
Check "Projektordner nicht im Vollbackup" (-not (Test-Path (Join-Path $fullOrdner '_Projekte')))
Check "geparkte Datei nicht im Vollbackup" (@(Get-ChildItem $fullOrdner -Recurse -File | Where-Object { $_.Name -eq 'TestBarb.map' }).Count -eq 0)

"--- Einzelinstanz ---"
# Der Mutex verhindert, dass zwei Fenster dieselbe index.json beschreiben.
Check "erste Instanz bekommt die Sperre" (Enter-EinzelInstanz)
$script:InstanzErste = $script:Instanz

# Zweiter Versuch im selben Prozess: WaitOne(0) liefert sofort $true, weil ein
# Mutex reentrant ist. Deshalb aus einem eigenen Prozess pruefen - nur so ist der
# Test aussagekraeftig.
$zweiter = powershell.exe -NoProfile -Command @'
$m = New-Object System.Threading.Mutex($false, 'D2RCharBackupManager.Einzelinstanz')
try { if ($m.WaitOne(0)) { 'frei' } else { 'belegt' } } catch { 'belegt' }
'@
Check "zweite Instanz wird abgewiesen" ("$zweiter".Trim() -eq 'belegt') $zweiter

Exit-EinzelInstanz
Check "nach dem Freigeben ist die Sperre weg" ($null -eq $script:Instanz)

$dritter = powershell.exe -NoProfile -Command @'
$m = New-Object System.Threading.Mutex($false, 'D2RCharBackupManager.Einzelinstanz')
try { if ($m.WaitOne(0)) { 'frei' } else { 'belegt' } } catch { 'belegt' }
'@
Check "danach kann wieder gestartet werden" ("$dritter".Trim() -eq 'frei') $dritter

# Genau das braucht der Neustart bei Sprachwechsel und "Ansicht zuruecksetzen":
# ohne Freigabe vorher sperrte sich das Programm selbst aus.
Check "Freigeben ist mehrfach gefahrlos" ($null -eq (Exit-EinzelInstanz))

"--- Uebersetzungen ---"
# Jeder Text, der im Programm sichtbar wird, braucht einen Eintrag in
# $script:TextsEn. Fehlt einer, faellt die Oberflaeche an dieser Stelle still auf
# Deutsch zurueck - das faellt beim Entwickeln nicht auf, einem englischen Nutzer
# aber sofort. Deshalb hier pruefen statt hoffen.
$quelle = [System.IO.File]::ReadAllText($src)

# Nur literale Aufrufe: (T $variable) laesst sich von aussen nicht aufloesen.
$sichtbar = @{}
foreach ($m in ([regex]"\(T\s+'((?:[^']|'')*)'").Matches($quelle)) {
    $sichtbar[$m.Groups[1].Value.Replace("''","'")] = 'Code'
}
# Beschriftungen aus dem XAML - dieselben Attribute, die Convert-XamlText anfasst.
foreach ($m in ([regex]'(?:Header|Content|Text|ToolTip|Title)="([^"]{2,})"').Matches($quelle)) {
    $t = $m.Groups[1].Value
    if ($t -match '^\{' -or $t -match '^&#x') { continue }   # Bindung bzw. Symbolzeichen
    if (-not $sichtbar.ContainsKey($t)) { $sichtbar[$t] = 'XAML' }
}
foreach ($m in ([regex]'>([A-Za-zÄÖÜäöüß][^<>{]{2,60})</Button>').Matches($quelle)) {
    $t = $m.Groups[1].Value.Trim()
    if (-not $sichtbar.ContainsKey($t)) { $sichtbar[$t] = 'XAML' }
}

# Eigennamen werden bewusst nicht uebersetzt.
$keineUebersetzung = @($script:AppName)

$ohne = @()
foreach ($k in $sichtbar.Keys) {
    if ($keineUebersetzung -contains $k) { continue }
    if (-not $script:TextsEn.ContainsKey($k)) { $ohne += "$($sichtbar[$k]): $k" }
}

Check "sichtbare Texte gefunden (>150)" ($sichtbar.Count -gt 150) $sichtbar.Count
Check "TextsEn gefuellt (>200)"         ($script:TextsEn.Count -gt 200) $script:TextsEn.Count
Check "jeder sichtbare Text hat eine englische Fassung" ($ohne.Count -eq 0) ("`n         " + (($ohne | Sort-Object) -join "`n         "))

""
"ERGEBNIS: $pass bestanden, $fail fehlgeschlagen"
"Sandbox bleibt stehen: $root"


