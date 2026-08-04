$ErrorActionPreference = 'Stop'
$enc = New-Object System.Text.UTF8Encoding($true)
# Eigenen Ordner ableiten statt hart codieren: der Projektordner wird
# gelegentlich umbenannt oder verschoben, und ein fester Pfad braeche dann
# kommentarlos.
$src = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'D2RCharBackupManager.ps1'))

$probe = @'

Import-Index
Update-All

# Drei Zeilen markieren, Fokus bewusst NICHT im Gitter lassen - genau die Lage,
# in der WPF die Auswahl sonst ausgraut.
$GridChars.SelectedItems.Clear()
foreach ($e in (@($GridChars.Items) | Select-Object -First 3)) { [void]$GridChars.SelectedItems.Add($e) }
Update-SnapButtonLabel
$win.FindName('BtnSnapChar').Focus() | Out-Null

# Masse aus dem Fenster selbst holen, nicht hier wiederholen - sonst prueft man
# bei jeder Aenderung der Fensterbreite am Ziel vorbei.
$breite = [int]$win.Width; $hoehe = [int]$win.Height
$inhalt = $win.Content
$win.Content = $null                       # aus dem Fenster loesen, um es einzeln zu rendern
$inhalt.Measure([System.Windows.Size]::new($breite, $hoehe))
$inhalt.Arrange([System.Windows.Rect]::new(0, 0, $breite, $hoehe))
$inhalt.UpdateLayout()

$bmp = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($breite, $hoehe, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
$bmp.Render($inhalt)
$enc2 = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
$enc2.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bmp))
$ziel = Join-Path $env:TEMP 'ansicht.png'
$fs = [System.IO.File]::Open($ziel, [System.IO.FileMode]::Create)
try { $enc2.Save($fs) } finally { $fs.Dispose() }
'Bild geschrieben: ' + $ziel + '  (' + [math]::Round((Get-Item $ziel).Length/1KB) + ' KB)'
'Markiert: ' + (@(Get-SelectedChars) -join ', ')
'@

$d = Join-Path $env:TEMP 'render-app'
if (Test-Path $d) { [System.IO.Directory]::Delete($d, $true) }
New-Item -ItemType Directory -Path $d -Force | Out-Null
# DREI Stellen muessen weg, nicht nur das Hauptfenster: die Startsperre mit dem
# Haftungshinweis und die Einzelinstanz-Pruefung laufen davor und machen sonst je
# ein Fenster auf, das auf einen Klick wartet. Die Einzelinstanz-Pruefung wuerde
# das Rendern ausserdem abbrechen, sobald die App gerade offen ist - und genau
# dann will man oft rendern.
$ohneFenster = $src.Replace('[void]$win.ShowDialog()', '# aus').
                    Replace('if (Confirm-Disclaimer) {', 'if ($true) {').
                    Replace('if (-not (Enter-EinzelInstanz)) {', 'if ($false) {')
[System.IO.File]::WriteAllText((Join-Path $d 'D2RCharBackupManager.ps1'),
    $ohneFenster + $probe, $enc)
# Backup-Ordner bewusst im Temp: das Rendern soll niemandes echte Sicherungen
# anfassen, auch nicht lesend. Wer die eigenen Snapshots im Bild sehen will,
# traegt hier seinen Backup-Ordner ein.
@{ SavePath   = (Join-Path $env:USERPROFILE 'Saved Games\Diablo II Resurrected')
   BackupPath = (Join-Path $d 'backup')
   Language   = 'de' } | ConvertTo-Json | Set-Content (Join-Path $d 'config.json') -Encoding UTF8

& powershell.exe -NoProfile -ExecutionPolicy Bypass -Sta -File (Join-Path $d 'D2RCharBackupManager.ps1') 2>&1
[System.IO.Directory]::Delete($d, $true)
