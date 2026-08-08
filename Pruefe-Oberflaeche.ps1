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

"--- Papierkorb-Anzeige ---"
Pruef "Anzeige gefuellt"            (-not [string]::IsNullOrWhiteSpace($TxtTrashInfo.Text)) $TxtTrashInfo.Text
Pruef "Knopf frei wenn etwas drin"  ($BtnEmptyTrash.IsEnabled -eq ($trash.Count -gt 0))
"  Text: '$($TxtTrashInfo.Text)'"

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
