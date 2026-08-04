$ErrorActionPreference = 'Stop'
$enc = New-Object System.Text.UTF8Encoding($true)
$src = [System.IO.File]::ReadAllText('P:\Cowork\D2R-Char-Backup-Manager\D2RCharBackupManager.ps1')

$probe = @'

Import-Index
Update-All

# Drei Zeilen markieren, Fokus bewusst NICHT im Gitter lassen - genau die Lage,
# in der WPF die Auswahl sonst ausgraut.
$GridChars.SelectedItems.Clear()
foreach ($e in (@($GridChars.Items) | Select-Object -First 3)) { [void]$GridChars.SelectedItems.Add($e) }
Update-SnapButtonLabel
$win.FindName('BtnSnapChar').Focus() | Out-Null

$breite = 1380; $hoehe = 800
$inhalt = $win.Content
$win.Content = $null                       # aus dem Fenster loesen, um es einzeln zu rendern
$inhalt.Measure([System.Windows.Size]::new($breite, $hoehe))
$inhalt.Arrange([System.Windows.Rect]::new(0, 0, $breite, $hoehe))
$inhalt.UpdateLayout()

$bmp = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($breite, $hoehe, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
$bmp.Render($inhalt)
$enc2 = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
$enc2.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bmp))
$ziel = 'C:\Users\JD6B13~1.JD-\AppData\Local\Temp\claude\P--Cowork\6ac4e251-d356-48f0-9c18-efb201cd4639\scratchpad\ansicht.png'
$fs = [System.IO.File]::Open($ziel, [System.IO.FileMode]::Create)
try { $enc2.Save($fs) } finally { $fs.Dispose() }
'Bild geschrieben: ' + $ziel + '  (' + [math]::Round((Get-Item $ziel).Length/1KB) + ' KB)'
'Markiert: ' + (@(Get-SelectedChars) -join ', ')
'@

$d = Join-Path $env:TEMP 'render-app'
if (Test-Path $d) { [System.IO.Directory]::Delete($d, $true) }
New-Item -ItemType Directory -Path $d -Force | Out-Null
[System.IO.File]::WriteAllText((Join-Path $d 'D2RCharBackupManager.ps1'),
    $src.Replace('[void]$win.ShowDialog()', '# aus') + $probe, $enc)
@{ SavePath   = (Join-Path $env:USERPROFILE 'Saved Games\Diablo II Resurrected')
   BackupPath = 'P:\Cowork\D2R-Backups'
   Language   = 'de' } | ConvertTo-Json | Set-Content (Join-Path $d 'config.json') -Encoding UTF8

& powershell.exe -NoProfile -ExecutionPolicy Bypass -Sta -File (Join-Path $d 'D2RCharBackupManager.ps1') 2>&1
[System.IO.Directory]::Delete($d, $true)
