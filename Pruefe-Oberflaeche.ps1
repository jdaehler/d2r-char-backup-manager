$ErrorActionPreference = 'Stop'
# Prueft die Verdrahtung der Oberflaeche, die sich in Test-Sandbox.ps1 nicht
# pruefen laesst, weil sie das ganze Fenster braucht: Kontextmenue, mitlaufende
# Knopfbeschriftungen, Papierkorb-Anzeige. Das Fenster wird aufgebaut, aber nie
# gezeigt - nach demselben Muster wie Render-Ansicht.ps1.
#
# Voraussetzung: Test-Sandbox.ps1 lief vorher, damit unter _sandbox\ etwas liegt.
$enc = New-Object System.Text.UTF8Encoding($true)
$src = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'D2RCharBackupManager.ps1'))

$sandbox = Join-Path $PSScriptRoot '_sandbox'
if (-not (Test-Path (Join-Path $sandbox 'backup\index.json'))) {
    throw "Keine Sandbox gefunden. Bitte zuerst Test-Sandbox.ps1 laufen lassen."
}

$probe = @'

Import-Index
Update-All

# Fuer die Papierkorb-Pruefungen muss einer drin liegen. Der Testlauf leert ihn
# am Ende, deshalb hier bei Bedarf einen anlegen.
if (@($script:Index.snapshots | Where-Object { $_.kind -eq 'trash' }).Count -eq 0) {
    $frei = @(Get-Characters)
    if ($frei.Count -gt 0) { $null = Remove-CharacterToTrash -CharName $frei[0].Name; Update-All }
}

$ok = 0; $fail = 0
function Pruef($text, $bedingung, $zusatz = '') {
  if ($bedingung) { $script:ok++; "  [ok]   $text" }
  else { $script:fail++; "  [FAIL] $text $zusatz" }
}

"--- Kontextmenue der Snapshot-Liste ---"
$m = $GridSnaps.ContextMenu
Pruef "Menue haengt am Gitter"      ($null -ne $m)
Pruef "zwei Eintraege"              ($m.Items.Count -eq 2) $m.Items.Count
Pruef "erster ist Wiederherstellen" ($m.Items[0].Header -like 'Wiederherstellen*') $m.Items[0].Header

$auf = { $m.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.ContextMenu]::OpenedEvent))) }

$GridSnaps.SelectedItem = $null
& $auf
Pruef "ohne Markierung gesperrt"    (-not $m.Items[1].IsEnabled)

$normal = @($GridSnaps.Items | Where-Object { $_.kind -ne 'trash' })
if ($normal.Count -gt 0) {
  $GridSnaps.SelectedItem = $normal[0]
  & $auf
  Pruef "bei Snapshot: Loeschen"     ($m.Items[1].Header -eq 'Löschen') $m.Items[1].Header
  Pruef "und freigegeben"            ($m.Items[1].IsEnabled)
  Pruef "Knopf sagt dasselbe"        ($BtnDelete.Content -eq 'Löschen') $BtnDelete.Content
}

$trash = @($GridSnaps.Items | Where-Object { $_.kind -eq 'trash' })
if ($trash.Count -gt 0) {
  $GridSnaps.SelectedItem = $trash[0]
  & $auf
  # Beim Papierkorb liegen die Originaldateien - das muss der Knopf sagen.
  Pruef "bei Papierkorb: endgueltig" ($m.Items[1].Header -eq 'Endgültig löschen') $m.Items[1].Header
  Pruef "Knopf zieht mit"            ($BtnDelete.Content -eq 'Endgültig löschen') $BtnDelete.Content
} else {
  "  (kein Papierkorb-Eintrag herstellbar - Teil uebersprungen)"
}

"--- Papierkorb-Filter ---"
# Der Filter ist dreiwertig und wird ueber den Index ausgewertet, nicht ueber den
# angezeigten Text - sonst braeche er in der englischen Oberflaeche.
$CmbTrash.SelectedIndex = 0; Update-SnapshotGrid
$alle = @($GridSnaps.Items).Count
$mitTrash = @($GridSnaps.Items | Where-Object { $_.kind -eq 'trash' }).Count
Pruef "mit anzeigen: Papierkorb dabei" ($mitTrash -gt 0) $mitTrash

$CmbTrash.SelectedIndex = 1; Update-SnapshotGrid
Pruef "ausblenden: kein Papierkorb"  (@($GridSnaps.Items | Where-Object { $_.kind -eq 'trash' }).Count -eq 0)
Pruef "ausblenden: Rest bleibt"      (@($GridSnaps.Items).Count -eq ($alle - $mitTrash)) @($GridSnaps.Items).Count

$CmbTrash.SelectedIndex = 2; Update-SnapshotGrid
Pruef "nur Papierkorb: nichts sonst" (@($GridSnaps.Items | Where-Object { $_.kind -ne 'trash' }).Count -eq 0)
Pruef "nur Papierkorb: alle dabei"   (@($GridSnaps.Items).Count -eq $mitTrash) @($GridSnaps.Items).Count

$CmbTrash.SelectedIndex = 0; Update-SnapshotGrid
Pruef "zurueck auf alles"            (@($GridSnaps.Items).Count -eq $alle)

"--- Mehrfachauswahl ---"
# Den Papierkorb leert man jetzt ueber Filter plus Mehrfachauswahl, nicht ueber
# einen eigenen Knopf. Also muss die Liste mehrere Zeilen zulassen.
Pruef "Liste erlaubt mehrere Zeilen" ($GridSnaps.SelectionMode -eq 'Extended') $GridSnaps.SelectionMode

$CmbTrash.SelectedIndex = 2; Update-SnapshotGrid    # nur Papierkorb
$GridSnaps.SelectAll()
$markiert = @(Get-SelectedSnapshotRecords)
Pruef "SelectAll erfasst alle"       ($markiert.Count -eq @($GridSnaps.Items).Count) $markiert.Count
Pruef "nur Papierkorb markiert"      (@($markiert | Where-Object { $_.kind -ne 'trash' }).Count -eq 0)
Update-DeleteButtonLabel
Pruef "Knopf sagt endgueltig"        ($BtnDelete.Content -like 'Endgültig löschen*') $BtnDelete.Content

$CmbTrash.SelectedIndex = 0; Update-SnapshotGrid
$GridSnaps.SelectAll()
$alleM = @(Get-SelectedSnapshotRecords)
Update-DeleteButtonLabel
# Gemischte Auswahl: nicht "endgueltig", denn es sind auch gewoehnliche
# Sicherungen dabei - aber die Anzahl muss dranstehen.
Pruef "gemischt: nicht endgueltig"   ($BtnDelete.Content -notlike 'Endgültig*') $BtnDelete.Content
Pruef "Knopf nennt die Anzahl"       ($BtnDelete.Content -like "*($($alleM.Count))*") $BtnDelete.Content
$GridSnaps.UnselectAll()

""
"ERGEBNIS: $ok bestanden, $fail fehlgeschlagen"
if ($fail -gt 0) { exit 1 }
'@

# Dieselben drei Stellen wie beim Rendern: Startsperre, Einzelinstanz und das
# Anzeigen des Fensters muessen raus, sonst wartet der Lauf auf einen Klick.
$d = Join-Path $env:TEMP ('d2r-uipruef-' + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $d -Force | Out-Null
try {
    $ohneFenster = $src.Replace('[void]$win.ShowDialog()', '# aus').
                        Replace('if (Confirm-Disclaimer) {', 'if ($true) {').
                        Replace('if (-not (Enter-EinzelInstanz)) {', 'if ($false) {')
    [System.IO.File]::WriteAllText((Join-Path $d 'D2RCharBackupManager.ps1'), $ohneFenster + $probe, $enc)

    # Gegen die Sandbox, niemals gegen echte Spielstaende oder Sicherungen:
    # dieser Lauf legt einen Papierkorb-Eintrag an, loescht also Dateien.
    @{ SavePath   = (Join-Path $sandbox 'saves')
       BackupPath = (Join-Path $sandbox 'backup')
       Language   = 'de' } | ConvertTo-Json | Set-Content (Join-Path $d 'config.json') -Encoding UTF8

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -Sta -File (Join-Path $d 'D2RCharBackupManager.ps1') 2>&1
} finally {
    [System.IO.Directory]::Delete($d, $true)
}
