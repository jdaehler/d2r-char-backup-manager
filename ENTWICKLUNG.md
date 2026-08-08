# Entwicklungsnotizen

Diese Datei richtet sich an den, der den Code pflegt — bewusst auf Deutsch, weil
das die Arbeitssprache dieses Projekts ist. Sie beschreibt nicht, *was* das
Programm kann, sondern *wie* es gebaut ist und welche Fallstricke es hat.

- Was das Programm kann und wie man es benutzt: [README.md](README.md) (englisch)
- Bedienungsanleitungen für Endanwender: [ANLEITUNG.md](ANLEITUNG.md) (deutsch),
  [INSTRUCTIONS.md](INSTRUCTIONS.md) (englisch)
- Was sich je Version geändert hat: [CHANGELOG.md](CHANGELOG.md)

## Starten

Doppelklick auf **`Start D2R Char Backup Manager.cmd`**.

## Sprache

Die Oberfläche gibt es auf Deutsch und Englisch, umschaltbar über den Knopf oben
rechts (`EN` / `DE`). Der deutsche Text ist zugleich der Übersetzungsschlüssel:
`$script:TextsEn` bildet ihn auf Englisch ab, `T` schlägt nach, und
`Convert-XamlText` übersetzt beim Laden **nur** `Header`/`Content`/`Text`/`ToolTip`/`Title`
sowie Knopfbeschriftungen — niemals Bindungspfade oder `x:Name`. Fehlt eine
Übersetzung, erscheint der deutsche Text statt einer Lücke. Der Sprachwechsel
startet das Fenster neu, weil die Übersetzung beim Aufbau greift.

Neue Texte also **immer auf Deutsch schreiben** und den Eintrag in `$script:TextsEn`
ergänzen. Englische Texte ohne `&`, das müsste im XAML maskiert werden.

## Kodierung

Die Datei enthält echte Umlaute und **muss als UTF-8 mit BOM** gespeichert bleiben —
sonst liest Windows PowerShell 5.1 sie als ANSI und zerlegt jeden Umlaut. Nach
jeder Bearbeitung mit einem Werkzeug, das den BOM verwirft, wieder setzen:

Im Projektordner ausführen:

```bash
powershell -c "$f='.\D2RCharBackupManager.ps1'; [IO.File]::WriteAllText((Resolve-Path $f),[IO.File]::ReadAllText((Resolve-Path $f)),(New-Object Text.UTF8Encoding($true)))"
```

## Erste Einrichtung

Es gibt keine. Der Spielstand-Ordner wird über die Registry ermittelt
(`Get-SavedGamesRoot`, berücksichtigt Ordnerumleitung), der Backup-Ordner liegt
standardmäßig als Unterordner `Backups` neben dem Programm. Abweichungen landen in
`config.json` daneben.

## Versionen

Die Versionsnummer steht in `$script:AppVersion` und erscheint im Fenstertitel
sowie rechts in der Statuszeile. Bei Änderungen mitpflegen.

Was sich je Version geändert hat, steht in [CHANGELOG.md](CHANGELOG.md) — bewusst
nur dort, damit die Liste nicht an zwei Stellen auseinanderläuft.

Frühere Stände liegen im Git, nicht als Ordnerkopie. Bis 1.1 gab es dafür lokal
`_versionen\<Version>\`; seit das Projekt am 04.08.2026 ein Repository ist, leistet
die Historie dasselbe besser, deshalb ist der Ordner am 06.08.2026 gelöscht worden.
**Vor einer Erweiterung wird also nichts mehr weggesichert** — es reicht, mit sauberem
Arbeitsbaum anzufangen und die fertige Version zu taggen. Die alten Stände 1.0 und 1.1
sind nicht verloren: sie stecken vollständig im ersten Commit `0a8d98e` und lassen sich
mit `git show 0a8d98e:_versionen/1.1/D2RCharBackupManager.ps1` oder
`git checkout 0a8d98e -- _versionen` wiederholen. Fertige Pakete gehören weiterhin als
Anhang an ein Release, nicht in den Verlauf.

## Stand

**Sichern** läuft gegen die echten Spielstände. Stand 04.08.2026: 28 Charaktere, davon
15 aktiv im Spielstand-Ordner und 13 geparkt im Projekt `FremdChars`; 86 Sicherungen.

**Wiederherstellen** ist am 04.08.2026 zum ersten Mal gegen den echten Spielstand-Ordner
gelaufen: `jdBarb` (Lvl 4 Barbar) unter dem freien Namen `TestKopie` wiederhergestellt,
ohne Stash, bei beendetem D2R. Vorher wurde der komplette Ordner gesichert
(`Kompletter Ordner\2026-08-04_101134`, 340 Dateien, 3 MB) — die Rückfahrkarte.

Geprüft wurde über SHA-256 des gesamten Spielstand-Ordners (518 Dateien) vor und nach
dem Vorgang, 13 Prüfungen, alle grün:

- keine vorhandene Datei geändert, keine verschwunden
- genau fünf neue Dateien, alle `TestKopie.*` (`.d2s .ctl .key .ma0 .map`)
- `TestKopie.d2s` byte-identisch mit `jdBarb.d2s`, Header gültig, Klasse Barbar, Level 4
- Shared Stash unangetastet
- keine Sicherheitskopie angelegt — der Zielname war frei, es gab nichts zu überschreiben
  (so gedacht, siehe *Auto-Sicherungen*)

**Im Spiel bestätigt:** D2R zeigte `TestKopie` neben `jdBarb` in der Charakterauswahl,
und der Charakter ließ sich spielen. Damit ist der Wiederherstellen-Pfad Ende-zu-Ende
belegt — auch die These, dass Umbenennen reines Umbenennen von Dateien ist (siehe
*Warum Umbenennen gefahrlos ist*). Der Testcharakter ist danach wieder aus dem
Spielstand-Ordner entfernt worden — vorher gesichert nach
`Charaktere\TestKopie\2026-08-04_102411 Lvl4 Barbar`, falls er je wieder gebraucht wird.

**Parken** ist am 04.08.2026 gegen den echten Spielstand-Ordner gelaufen: sieben
Charaktere in ein Projekt `FremdChars`. Nachgeprüft — alle sieben vollständig
verschoben, im Wurzelverzeichnis blieb von ihnen keine Datei, der Shared Stash
unangetastet, zu jedem der Pflicht-Snapshot im Backup, `_INFO.txt` geschrieben.
Bei einem Charakter wanderten damals auch `.ctlo`/`.keyo` mit, weil
`Get-CharacterFiles` über den Basisnamen greift. Das wurde seinerzeit als richtig
notiert — **ist es nicht**, und seit 1.21 passiert es nicht mehr: siehe
*Online-Charaktere bleiben draußen*.

**Im Spiel bestätigt**, ebenfalls am 04.08.2026: Die geparkten Charaktere sind aus
der Charakterauswahl von D2R verschwunden, und **Zurückholen wurde echt ausgeführt** —
`Frenzy` kam aus `FremdChars` zurück in den Spielstand-Ordner und stand danach wieder
in der Auswahl. Damit ist auch der Rückweg belegt, nicht nur der Hinweg. Das war die
letzte offene Stelle vor der Veröffentlichung: ein Fehler beim Zurückholen sähe für
den Nutzer nicht nach einem Fehler aus, sondern nach verlorenen Charakteren.

**Umbenennen** ist am 08.08.2026 gegen die echten Spielstände gelaufen, vom Captain
selbst ausgeführt und für gut befunden: `Amazone_Poison` (Level 47 Amazone) heißt
seitdem `jdAmazonePoison`. Nachgeprüft im Spielstand-Ordner — alle sechs Dateien sind
mitgewandert (`.d2s`, `.ctl`, `.key`, `.ma0`, `.ma1`, `.map`), unter dem alten Namen
blieb nichts liegen, und der Pflicht-Snapshot steht als *Automatisch vor dem
Umbenennen* im Index. Damit ist auch der Grenzfall belegt, der zur Umstellung der
Namensprüfung geführt hat: der alte Name enthielt einen Unterstrich, der neue keinen.

**Duplizieren und Löschen samt Zurückholen** sind am 08.08.2026 ebenfalls echt gelaufen,
vom Captain ausgeführt und für gut befunden:

- 16:08 **dupliziert**: `HM-TWO` (Level 13) → `TESTONE`, das Original blieb stehen.
- 16:10 **gelöscht**: `HM-TWO` wanderte nach
  `_Papierkorb\2026-08-08_161016_HM-TWO\` — fünf Dateien plus `_INFO.txt`, dazu der
  Pflicht-Snapshot *Automatisch vor dem Löschen* im Index.
- Danach **zurückgeholt**: `HM-TWO` steht wieder im Spielstand-Ordner, mit
  unverändertem Zeitstempel der Datei.

Damit sind alle drei Aktionen von 1.3 gegen echte Spielstände belegt, nicht nur gegen
die Sandbox.

**Dabei aufgefallen:** Nach dem Zurückholen bleibt der Papierkorb-Eintrag stehen, der
Charakter liegt also aktiv *und* im Papierkorb. Das folgt daraus, dass `Restore-Snapshot`
kopiert statt verschiebt, und ist für Snapshots richtig — beim Windows-Papierkorb
verschwindet der Eintrag beim Wiederherstellen dagegen. Offen, ob das hier auch so sein
soll; siehe *Offene Punkte*.

### Online-Charaktere bleiben draußen

Geprüft am 06.08.2026, Anlass: eine Komplettsicherung des Zweitkontos ergab
**114 Dateien für einen einzigen lokalen Charakter**. Aufgeschlüsselt waren das
66 `.ctlo`, 31 `.keyo`, 8 `.fltr`, 2 `.json`, 2 `.key` und je eine `.ctl`, `.d2i`,
`.d2s`, `.ma0`, `.map`. Also 97 von 114 Dateien Online-Reste, viele mit 0 Byte und
aus 2024 — D2R räumt sie nie auf, auch nicht für längst gelöschte Charaktere.

Welche Endungen zu Online-Charakteren gehören, wurde nachgeschlagen statt geraten
(Blizzard-Forum, „Savegames Offline vs. Online", und zweite Quelle bestätigend):

| gehört zu | Endungen |
|---|---|
| Online (Battle.net) | `.ctlo`, `.keyo` — **und nur diese** |
| Lokal (Einzelspieler) | `.d2s`, `.ctl`, `.key`, `.map`, `.ma0`–`.ma3` |

Ein `.mapo` oder `.ma0o` gibt es nicht: die Automap-Daten von Online-Charakteren
liegen wie der Charakter selbst auf Blizzards Servern. Die Endungsliste ist damit
vollständig, nicht bloß eine Näherung. Das Suffix `o` ist durchgehend die
Online-Variante der jeweiligen lokalen Endung.

Verworfen wurde die Idee, den Ausschluss abschaltbar zu machen. Die Dateien haben
keinen Sicherungswert — der Charakter, zu dem sie gehören, lässt sich von hier aus
ohnehin nicht sichern —, und ein Schalter hätte nur eine Frage aufgeworfen, auf die
es keine sinnvolle zweite Antwort gibt.

Der Ausschluss sitzt in `$script:ExcludedExtensions` und wirkt dadurch an allen drei
Stellen gleichzeitig: `Get-CharacterFiles` (Dateisatz eines Charakters, damit auch
Parken), `New-Snapshot -Kind full` (Komplettsicherung) und die Vorschau-Zählung im
Knopf *Alles sichern*.

Ältere Sicherungen behalten, was in ihnen liegt. Wiederherstellen kopiert nur und
löscht nichts, deshalb bleiben die Online-Dateien im Spielstand-Ordner künftig
unberührt — vorher hätte das Zurückspielen eines kompletten Ordners die Belegung
sämtlicher Online-Charaktere auf den Stand von damals zurückgedreht.

`Test-Sandbox.ps1` deckt 227 Prüfungen ab (Header-Parsing, Sichern, Wiederherstellen,
Umbenennen, Ordner-Ablage, `_INFO.txt`, Stash-Verhalten, Sicherheitskopie, Löschen,
Index-Neuladen, Parken, Zurückholen, Projektnamen, Namenskollisionen, Ausschluss der
Online-Dateien, Live-Namensprüfung im Dialog, D2R-Sperren) und läuft grün unter
Windows PowerShell 5.1 **und** PowerShell 7.4 — beides am 08.08.2026 nachgemessen.

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -Sta -File "Test-Sandbox.ps1"
```

Der Testlauf baut inzwischen echte WPF-Fenster und braucht dafür **STA**. Beide
PowerShell-Versionen starten auf Windows von sich aus mit STA — am 08.08.2026
nachgemessen, auch PowerShell 7 — der Schalter `-Sta` oben schadet also nicht,
nötig ist er nicht. Wer mit `-Mta` startet, bekommt eine klare Ansage statt eines
kryptischen Fehlers aus der Tiefe von WPF; das prüft das Skript in der ersten Zeile.

### Sandbox: fester Ordner, kein Wegwerf unter %TEMP%

Seit 08.08.2026 liegt die Spielwiese fest unter `_sandbox\` **neben dem Skript**, nicht
mehr unter `%TEMP%\d2rtest-<zufall>\`. Sie wird zu Beginn jedes Laufs geleert und neu
aufgebaut — die Tests brauchen einen bekannten Ausgangszustand — und bleibt danach
**stehen**. Genau das ist der Zweck: Nach einem Fehlschlag lässt sich hineinsehen, was
die Tests tatsächlich angelegt haben, ohne den Ordner in `%TEMP%` zu suchen, während
der nächste Lauf schon einen neuen anlegt. `_sandbox/` steht in `.gitignore`.

Weil hier rekursiv gelöscht wird, prüft das Skript vorher, dass der Pfad wirklich der
Ordner `_sandbox` neben dem Skript ist, und bricht sonst ab, ohne etwas anzufassen.

Der echte Spielstand-Ordner wird nicht angefasst. Auch die D2R-Erkennung ist
abgekoppelt: `Test-D2RRunning` wird im Testlauf durch eine umschaltbare Fassung
ersetzt. Vorher brach der Lauf ab, sobald jemand gerade spielte — und der Fall
„D2R läuft" ließ sich überhaupt nicht prüfen, weil er sich nicht auf Kommando
herstellen lässt. Jetzt ist er geprüft: Parken und Zurückholen werden abgelehnt,
Sichern bleibt erlaubt. Im Programm selbst bleibt der Schutz unverändert; dort führt
der einzige `Get-Process`-Aufruf durch genau diese eine Funktion.

### Verdrahtung des Fensters prüfen

`Pruefe-Oberflaeche.ps1` baut das Fenster auf, zeigt es aber nie, und prüft, was
`Test-Sandbox.ps1` nicht erreicht, weil es das ganze Fenster braucht: hängt das
Kontextmenü am Gitter, sind seine Einträge ohne Markierung gesperrt, heißt „Löschen"
bei einem Papierkorb-Eintrag „Endgültig löschen", zieht der Knopf mit, filtert die
Papierkorb-Auswahl in allen drei Stellungen richtig, stimmt die Mengenangabe neben
*Leeren*. Läuft gegen `_sandbox\` und legt sich dort bei Bedarf
selbst einen Papierkorb-Eintrag an — **nie gegen echte Spielstände**, denn dieser Lauf
löscht Dateien. Setzt voraus, dass `Test-Sandbox.ps1` vorher lief.

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -Sta -File "Pruefe-Oberflaeche.ps1"
```

Beim Schreiben dieses Skripts prompt in den eigenen Fallstrick getreten: ohne BOM
gespeichert, worauf Windows PowerShell 5.1 die Umlaute als ANSI las und vier Vergleiche
gegen `'Löschen'` fehlschlugen — obwohl der Istwert danebenstand und richtig aussah.
Siehe *Kodierung*: gilt auch für Hilfsskripte, nicht nur für die Anwendung.

### Oberfläche prüfen, ohne sie zu starten

`Render-Ansicht.ps1` baut das Fenster im Speicher auf, markiert drei Charaktere,
setzt den Fokus bewusst auf einen Knopf und schreibt das Ergebnis als PNG nach
`%TEMP%\...\ansicht.png`. Damit lassen sich Farben, Abstände und Umbrüche
beurteilen, ohne die App zu öffnen — so wurde der fehlende Auswahl-Kontrast gefunden.

### Demo-Umgebung zum Screenshots machen

`Demo-Umgebung.ps1` baut unter `%TEMP%\D2R-Demo` eine vollständige, startbare
Fassung: Programmkopie, 16 erfundene Charaktere, 4 geparkte in zwei Projekten,
17 fertige Sicherungen mit Labels und Notizen, eigene `config.json`. Ein
Doppelklick auf `Start Demo.cmd` öffnet das echte Fenster — nur eben mit
ausgedachten Daten.

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -Sta -File "Demo-Umgebung.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "Demo-Umgebung.ps1" -DryRun
powershell.exe -NoProfile -ExecutionPolicy Bypass -Sta -File "Demo-Umgebung.ps1" -Deutsch
```

Damit entstehen Bilder vom laufenden Programm — schärfer und mit echten
Fensterrahmen, anders als beim Rendern in den Speicher.

Drei Dinge sind dabei bewusst so gebaut:

- Die Programmkopie bekommt einen **eigenen Mutex-Namen** (`…Demo`). Sonst
  ließe sich die Demo nicht starten, solange das echte Programm offen ist.
- Der **Haftungshinweis ist vorab bestätigt**, sonst stünde er im Bild. Die
  Fassungsnummer wird aus der Programmdatei gelesen, damit sie nicht veraltet.
- Das Skript weigert sich, in den Projektordner oder unter `Saved Games` zu
  schreiben, und legt vorher den Zielordner an — es löscht ihn, also nie auf
  etwas zeigen lassen, das bleiben soll. `-DryRun` zeigt alles vorher an.

### Screenshots fürs README

Die Bilder in `screenshots\` sind **aus erfundenen Charakteren** erzeugt, nicht aus
einem echten Spielstand — sonst stünden im öffentlichen Repo echte Charakternamen,
Projektnamen und Sicherungszeiten. Beim Neuerzeugen daran denken: gerendert wird
gegen einen Wegwerf-Ordner unter `%TEMP%` mit ausgedachten Namen und englischer
Oberfläche (`Language = 'en'` in der Wegwerf-`config.json`).

Beim Rendern müssen **drei** Stellen unterdrückt werden, nicht nur das Hauptfenster:
zusätzlich die Startsperre mit dem Haftungshinweis und die Einzelinstanz-Prüfung.
Beide laufen davor und machen sonst je ein Fenster auf, das auf einen Klick wartet —
und die Einzelinstanz-Prüfung würde das Rendern abbrechen, sobald die App gerade
offen ist. Genau dann will man aber oft rendern.

### Dateien im Ordner

| Datei | Zweck |
|---|---|
| `D2RCharBackupManager.ps1` | die Anwendung |
| `Start D2R Char Backup Manager.cmd` | Doppelklick-Starter |
| `ANLEITUNG.md` / `INSTRUCTIONS.md` | für Endanwender, liegen im Deploy-Paket |
| `README.md` | Schaufenster des Repos, englisch, mit Screenshots |
| `ENTWICKLUNG.md` | diese Datei, nur für die Pflege |
| `CHANGELOG.md` | Änderungen je Version, englisch |
| `screenshots\` | Bilder fürs README, aus **erfundenen** Charakteren erzeugt |
| `Test-Sandbox.ps1` | 227 Prüfungen gegen die Sandbox in `_sandbox\` |
| `Pruefe-Oberflaeche.ps1` | 21 Prüfungen der Fenster-Verdrahtung (Kontextmenü, Knopfbeschriftungen, Filter) |
| `_sandbox\` | Spielwiese der Tests, wird bei jedem Lauf neu gebaut, nicht im Repo |
| `Build-Deploy.ps1` | baut `_deploy\D2R-Char-Backup-Manager-<Version>.zip` |
| `Render-Ansicht.ps1` | Fenster als PNG rendern |
| `Demo-Umgebung.ps1` | startbare Demo mit erfundenen Daten, zum Screenshots machen |
| `config.json` | persönliche Pfade und Sprache, **nicht** im Deploy-Paket |
| `LICENSE` | MIT, liegt im Deploy-Paket und wird im Über-Dialog angezeigt |
| `.gitignore` / `.gitattributes` | für den späteren Git-Umzug: hält `config.json` und Backups draußen, verbietet Git jede Umwandlung an der `.ps1` (BOM) |

## Funktionsumfang

| Bereich | Verhalten |
|---|---|
| Snapshot Charakter | kompletter Dateisatz (`.d2s`, `.ctl`, `.key`, `.ma0`–`.ma3`, `.map`) + Shared Stash |
| Mehrfachauswahl | Ein Knopf „Markierte sichern (n)" für einen, mehrere oder alle Charaktere (Strg-Klick, Umschalt-Klick, Strg+A oder der Knopf „Alles markieren"). Übersprungen wird nichts — wer gezielt markiert, meint es so |
| Trennung Auswahl/Aktion | In der linken Gruppe löst **genau ein** Knopf etwas aus: „Markierte sichern". „Alles markieren" markiert nur, „Spielstand-Ordner" öffnet nur, „Aktualisieren" liest nur neu. Die Sicherung des ganzen Ordners steht in einer eigenen Gruppe daneben |
| Snapshot kompletter Ordner | alle Dateien im Spielstand-Ordner außer `*.bak`, Knopf „Alles sichern" in eigener Gruppe |
| Wiederherstellen | optional unter anderem Namen; Stash nur auf ausdrücklichen Wunsch |
| Sicherheitskopie | wird vor jeder Wiederherstellung automatisch angelegt (abschaltbar) |
| Metadaten | Label, Tags (kommagetrennt), Notiz je Snapshot |
| Filtern | Volltextsuche, Tag-Filter, „nur gewählter Charakter", Auto-Sicherungen ausblenden |
| Schutz | blockierende D2R-Warnung nur beim **Wiederherstellen**; fragt vor Überschreiben eines bestehenden Namens nach |
| Rückfragen | vor „Alles sichern", „Snapshot löschen", bei Namenskollision beim Wiederherstellen und wenn D2R beim Wiederherstellen läuft. Das Sichern markierter Charaktere fragt bewusst **nicht** — es ist die Alltagsaktion und ändert nichts am Spiel |
| Sichern bei laufendem Spiel | erlaubt und nicht durch Rückfragen unterbrochen — der Snapshot bekommt automatisch den Tag `spiel-lief` und das Feld `d2rRunning`, weil der Stand dann älter sein kann als das Spielgeschehen |
| Vorauswahl | der erste Charakter ist immer markiert, damit der Sichern-Knopf nie ins Leere läuft |
| Sortierung | Klick auf eine Spaltenüberschrift sortiert; die Sortierung überlebt Aktualisieren *und* Programmneustart (liegt als `SortChars` / `SortSnaps` in `config.json`) |
| Parken | Verschiebt den Dateisatz nach `_Projekte\<Projekt>\` im Spielstand-Ordner. D2R listet nur `.d2s` aus dem Wurzelverzeichnis, damit ist der Charakter aus der Spielauswahl verschwunden. Shared Stash bleibt liegen. Pflicht-Snapshot vorher, nicht abschaltbar |
| Haftungshinweis | Beim ersten Start blockierend; ohne Haken und Bestätigung startet das Hauptfenster nicht (`Confirm-Disclaimer`). Die Bestätigung steht als `Disclaimer` in `config.json` und gilt für die Fassung `$script:DisclaimerVersion` — Nummer erhöhen zwingt alle zur erneuten Bestätigung. Bewusst **nicht** Teil von `View`, sonst löschte „Ansicht zurücksetzen" sie mit |
| Über-Dialog | Knopf oben rechts. Zeigt Version, den Haftungshinweis samt Bestätigungsdatum, die Lizenz aus der Datei `LICENSE` und öffnet auf Knopfdruck die Anleitung. **Dasselbe Fenster** wie die Startsperre, nur mit `-ReadOnly` — der Hinweistext steht deshalb nur einmal im Code |
| Gemerkte Ansicht | Fenstergröße, Breite der linken Hälfte, Spaltenbreiten beider Listen und beide Ausblenden-Haken liegen als `View` in `config.json`. Gespeichert beim Schließen (`Save-View`), angewandt vor dem Anzeigen (`Restore-View`). Die Fenster**position** bewusst nicht — nach dem Abziehen eines Monitors startete das Fenster sonst außerhalb des Bildschirms |
| Ansicht zurücksetzen | Knopf in den Einstellungen. Löscht `View` und beide Sortierungen, lässt Pfade, Sprache, Klassennamen und die Haftungsbestätigung stehen, startet das Fenster neu. `$script:SkipViewSave` verhindert, dass das Schließen die eben gelöschten Werte zurückschreibt |
| Geparkte in der Liste | Stehen weiter in der Charakterliste, blass und kursiv, mit Projekt in der letzten Spalte. `Get-AllCharacters` fügt aktive und geparkte zusammen. Checkbox „Geparkte ausblenden" filtert sie in `Update-All` heraus — bewusst **nicht** gemerkt, siehe offene Punkte |

Datums- und Größenspalten sortieren über `SortMemberPath` nach dem zugrundeliegenden Wert,
nicht nach dem angezeigten Text — sonst landet „03.01.2019" zwischen 2026er Daten und
„69,2 KB" hinter „206,9 KB".

Bewusst **nicht** enthalten: automatische Hintergrund-Sicherung (war so gewünscht —
ausschließlich manuell).

### Auto-Sicherungen

Vor jeder Wiederherstellung sichert die App **den Zustand, der gleich überschrieben wird** —
als Rückfahrkarte, falls der falsche Snapshot erwischt wurde. Solche Einträge tragen das
Label „Automatisch vor Wiederherstellung", den Tag `auto` und stehen in der Typ-Spalte als
`Charakter (Auto)` bzw. `Kompletter Ordner (Auto)`. Über die Checkbox „Auto-Sicherungen ausblenden"
verschwinden sie aus der Liste.

Sie sind ganz normale Snapshots und lassen sich genauso wiederherstellen. Angelegt werden
sie nur, wenn es tatsächlich etwas zu überschreiben gibt — beim Wiederherstellen unter einem
noch freien Namen entsteht keine. Im Wiederherstellen-Dialog abschaltbar (Standard: an).

### Denselben Charakter mehrfach sichern

Jeder Klick erzeugt einen eigenständigen Snapshot; überschrieben wird nie etwas. Die ID
ist `yyyyMMdd-HHmmss` plus 4 Zufallszeichen, mehrere Sicherungen in derselben Sekunde
kollidieren also nicht. In der Liste stehen sie sekundengenau untereinander.

Jeder Charakter-Snapshot kostet Platz, auch wenn sich nichts geändert hat: über die
72 vorhandenen gemessen im Schnitt **rund 100 KB**, Spanne 12 KB bis 430 KB. Den
Ausschlag geben die Kartendateien (`.ma0`–`.ma3`), nicht der Shared Stash — der ist
mit gut 8 KB kleiner als gedacht. Deshalb vergleicht die App den Inhalt per SHA-256 und
schreibt in die Statuszeile, wenn eine Sicherung inhaltlich mit einer früheren identisch
ist. Angelegt wird sie trotzdem; automatisch aufgeräumt wird **nichts**.

## Ablage

```
<Backup-Ordner>\
  _LIESMICH.txt
  index.json                                    Labels, Tags, Notizen
  Charaktere\<Name>\<Datum_Zeit> Lvl<n> <Klasse>\
      _INFO.txt, <Spielstanddateien>, SharedStash\<*.d2i>
  Kompletter Ordner\<Datum_Zeit>\
      _INFO.txt, <alle Dateien>
```

**Ordner statt ZIP, unkomprimiert** — das ist der Kern des Entwurfs: Man muss im Explorer
sehen können, was wann von wem gesichert wurde, und im Notfall ohne dieses Programm
zurückkopieren können. Jede Sicherung trägt eine `_INFO.txt` mit allen Angaben und einer
Schritt-für-Schritt-Anleitung fürs Zurückkopieren von Hand; im Wurzelverzeichnis erklärt
`_LIESMICH.txt` den Aufbau. Geht `index.json` verloren, bleiben die Sicherungen benutzbar —
nur die Beschriftungen fehlen dann.

Kostenpunkt gegenüber ZIP: rund viermal so viel Platz (bei 65 Sicherungen 24,6 statt 6,6 MB).

Die Ordnernamen `Charaktere`, `Kompletter Ordner`, `SharedStash` und `_Projekte` sind **fest
und werden nicht übersetzt** — sonst entstünden beim Sprachwechsel zwei Bäume.

Geparkte Charaktere liegen **nicht** im Backup-Ordner, sondern im Spielstand-Ordner:

```
<Spielstand-Ordner>\_Projekte\<Projektname>\
    _INFO.txt, <Spielstanddateien der geparkten Charaktere>
```

Das ist Absicht: ein geparkter Charakter ist kein Backup, sondern das Original an
einem Ort, an dem D2R es nicht sieht. Läge er im Backup-Ordner, verwischte genau
dieser Unterschied. Deshalb auch der Pflicht-Snapshot vor jedem Parken.

**Bekannte Lücke:** `New-Snapshot -Kind full` liest nur das Wurzelverzeichnis des
Spielstand-Ordners, „Alles sichern" enthält geparkte Charaktere also **nicht**.
Abgesichert sind sie durch den Pflicht-Snapshot beim Parken. Zwei Prüfungen in
`Test-Sandbox.ps1` halten dieses Verhalten fest, damit es nicht unbemerkt kippt.

Intern zeigt `pfad` im Datensatz relativ auf den Snapshot-Ordner. `Restore-Snapshot` liest
zusätzlich noch alte Datensätze mit `zip`; geschrieben wird dieses Format nicht mehr.
Ein Skript `Migrate-Backups.ps1` hat den Altbestand einmalig umgestellt — 65 von 65 am
03.08.2026, mit Sicherheitskopie. Es liegt **nicht mehr im Projekt**: einmalige
Migrationen gehören nicht ins Repo, wo sie jemand versehentlich starten kann. Falls es
je wieder gebraucht wird: `git show 0a8d98e:_versionen/1.1/Migrate-Backups.ps1`.

## Warum Umbenennen gefahrlos ist

In D2R steht der Charaktername **nicht** in der `.d2s`-Datei. Das klassische 16-Byte-Namensfeld
an Offset `0x14` ist genullt (ab Save-Version 100 sogar ganz entfernt); der Name ergibt sich
ausschließlich aus dem *Dateinamen*. Wiederherstellen unter neuem Namen ist deshalb reines
Umbenennen der Dateien — keine Binärmanipulation, keine Prüfsummen-Neuberechnung.

## .d2s-Header (empirisch gegen 28 echte Saves verifiziert)

```
0x00 Magic 0xAA55AA55 | 0x04 Version | 0x08 Dateigröße | 0x0C Prüfsumme | 0x10 aktive Waffe

base = 0x14 ab Version 100, sonst 0x24   (bis v99 liegt dazwischen das leere Namensfeld)
  base+0   Status-Bits: Bit2 = Hardcore, Bit3 = gestorben, Bit5 = Erweiterung
  base+1   Fortschritt
  base+4   Klassen-ID   (danach folgen immer die Marker-Bytes 0x10 0x1E)
  base+7   Level
  base+12  zuletzt gespielt (Unix-Zeit)
```

Vorgefundene Versionen: 96 (Original-D2), 97, 99, 105.

## Klassen

| ID | Klasse | | ID | Klasse |
|---|---|---|---|---|
| 0 | Amazone | | 4 | Barbar |
| 1 | Zauberin | | 5 | Druide |
| 2 | Totenbeschwoerer | | 6 | Assassine |
| 3 | Paladin | | 7 | Hexenbeschwoerer (Warlock) |

Klasse 7 ist die neue Klasse aus einem Patch nach Mitte 2026. Kommen weitere dazu, erscheinen
sie als „Klasse *n* (?)" und lassen sich in `config.json` unter `ClassNames` nachtragen.

## Offene Punkte

1. **Altbestände nicht importiert.** Die vorhandenen Ordner `Backup`, `BAK20250510`, `Temp`
   und die 178 `.bak`-Dateien im Spielstand-Ordner ignoriert die App bisher. Dazu die
   170 verwaisten `.keyo`/`.ctlo` gelöschter Charaktere (`Abracadabra213848843` und
   ähnlich) — von 178 gehören nur 4 zu einem heutigen Charakter.
2. **„Alles sichern" erfasst geparkte Charaktere nicht.** Siehe *Ablage*. Bewusst so
   gelassen, weil das Ändern auch `Restore-Snapshot` betrifft — aber es ist eine Falle,
   falls „komplett" wörtlich genommen wird.
3. **Datumsformat bleibt deutsch, auch auf Englisch.** `LastPlayedStr` und
   `Format-Timestamp` schreiben fest `dd.MM.yyyy HH:mm`. In der englischen
   Oberfläche steht damit `04.08.2026` statt `2026-08-04` oder `08/04/2026` — auf
   dem README-Screenshot gut zu sehen. Beim Ändern aufpassen: die *Sortierung* darf
   nicht auf den formatierten Text zurückfallen, dafür gibt es `LastPlayedSort`
   und `SortKey`.
4. **Kosmetik.** Die Griffpunkte und der Überlaufpfeil der Werkzeugleiste sind
   WPF-Standardbeiwerk und ließen sich ausblenden.
5. **Papierkorb-Eintrag bleibt nach dem Zurückholen stehen** (aufgefallen beim echten
   Test am 08.08.2026). Der Charakter liegt danach aktiv im Spielstand-Ordner *und*
   weiterhin im Papierkorb, weil `Restore-Snapshot` kopiert statt verschiebt. Beim
   Windows-Papierkorb verschwindet der Eintrag beim Wiederherstellen — hier bleibt er,
   wie jeder andere Sicherungseintrag auch. Beides vertretbar: Bleiben heißt, man kann
   mehrfach und unter verschiedenen Namen zurückholen; Verschwinden wäre aufgeräumter
   und näher an der Erwartung, die das Wort „Papierkorb" weckt. **Nicht ohne Ansage des
   Captains ändern** — automatisches Wegräumen ist genau das, was dieses Programm sonst
   überall vermeidet.

Erledigt: der Wiederherstellen-Pfad ist am 04.08.2026 echt gelaufen und im Spiel bestätigt
(siehe *Stand*) — bis dahin der größte blinde Fleck des Programms.

## Verworfen: D2R aus dem Programm heraus starten

Am 08.08.2026 überlegt und **bewusst gelassen**. Der Wunsch war naheliegend: Nach dem
Parken oder Zurückholen ist das Fenster ohnehin offen, ein Knopf würde den Umweg über
Battle.net sparen. Technisch wäre es klein.

Dagegen sprach das Transparenzversprechen im README, das dort wörtlich steht:

> „…never injects anything, **never starts or stops it**."

Ein Startknopf macht diesen Satz unwahr. Er ließe sich ehrlich umschreiben — aber der
Abschnitt ist der Grund, warum jemand dieses Programm überhaupt an seine Spielstände
lässt, und die Bequemlichkeit von einem gesparten Klick wiegt das nicht auf. Dazu käme,
dass ein PowerShell-Skript, das eine `.exe` startet, genau das Muster ist, auf das
Virenscanner-Heuristik anspringt — und das Programm hat dieses Problem ohnehin schon.

Falls es später doch kommt: Der Weg führt über das Battle.net-Protokoll bzw. den
Launcher-Pfad aus der Registry (**nachschlagen, nicht raten**), nur auf Klick, niemals
automatisch, und ohne jede Möglichkeit, das Spiel zu *beenden*. Beide README-Abschnitte
— Transparenz und Virenscanner — müssten mit geändert werden, im selben Commit.

## Geplant: Charakter-Aktionen (aufgenommen 06.08.2026)

Drei Aktionen direkt auf der Charakterliste, vom Captain am 06.08.2026 gewünscht:

1. **Umbenennen — erledigt am 08.08.2026.** Alle Dateien des Charakters gleich
   umbenennen. Kein Eingriff in die Datei, siehe *Warum Umbenennen gefahrlos ist*.
   `Rename-Character` plus `Show-RenameDialog`, Symbolknopf in der neuen Gruppe
   „Charakter". Einzelheiten unter *Umbenennen: was dabei zu beachten war*.
2. **Duplizieren — erledigt am 08.08.2026.** Dateisatz unter neuem Namen kopieren.
   Genau wie vorgesehen gebaut: `Copy-Character` legt einen Snapshot an und schreibt
   ihn sofort mit `Restore-Snapshot -TargetName` zurück. Damit ist die Sicherung nicht
   Beiwerk, sondern der Mechanismus selbst, und es gibt keinen zweiten Kopierpfad neben
   dem längst erprobten. Der Shared Stash wird **nicht** mitkopiert — er gehört allen
   Charakteren gemeinsam.
3. **Löschen — erledigt am 08.08.2026.** Nur für „soll wirklich weg" — wer den
   Charakter bloß aus der Charakterauswahl haben will, parkt ihn. Zwingender Snapshot
   davor und Verschieben in einen **eigenen Papierkorb-Ordner** statt hartem Löschen.
   `Remove-CharacterToTrash`, `Get-TrashStats`, `Clear-Trash`. Einzelheiten unten.

### Papierkorb als eigener Ordner

Vom Captain am 06.08.2026 festgelegt: **eigener Ordner, nicht der Windows-Papierkorb.**
Aus dem Windows-Papierkorb legt ein „Wiederherstellen" im Explorer die Dateien direkt
an den Ursprungsort zurück — der Charakter stünde wieder in der D2R-Auswahl, ohne dass
das Programm davon weiß. Ein eigener Ordner passt außerdem zum Rest: Ordner statt ZIP,
im Explorer sichtbar, auch ohne das Programm zurückzukopieren.

- **Ort:** `<Backup-Ordner>\_Papierkorb\`, also neben den Sicherungen und **nicht** im
  Spielstand-Ordner. So bleibt der Save-Ordner sauber und der Papierkorb wandert beim
  Cowork-Backup von selbst mit.
- **Ein Unterordner je Löschung:** `2026-08-06_1432_jdBarb\` mit `_INFO.txt` wie bei den
  Sicherungen — der Zeitstempel muss rein, derselbe Name kann mehrfach gelöscht werden.
- **Kein automatisches Leeren, keine Altersgrenze.** Nur anzeigen, wie viel drin liegt,
  und „Papierkorb leeren" von Hand. Etwas, das ungefragt Charaktere endgültig entsorgt,
  gehört nicht in dieses Programm.
- **Zurückholen über den vorhandenen Pfad:** Ein Papierkorb-Eintrag hat dasselbe Format
  wie ein Snapshot. Als eigene Art (`kind = 'trash'`) im Index geführt, funktioniert
  `Restore-Snapshot` sofort — samt Zurückholen unter anderem Namen. Preis: der Eintrag
  erscheint in der Sicherungsliste und braucht dort Kennzeichnung und Filter.
- Liegt der Backup-Ordner auf einem anderen Laufwerk als die Spielstände, ist das
  Verschieben ein Kopieren mit anschließendem Löschen. Erst nach erfolgreichem Kopieren
  löschen, und bei nicht erreichbarem Backup-Ziel das Löschen gar nicht erst anbieten.

**So gebaut, plus was beim Bauen dazukam:**

- **Kopiert wird immer, auch auf demselben Laufwerk.** Erst kopieren, Dateigröße
  vergleichen, dann löschen — nie umgekehrt. Damit ist die Reihenfolge in beiden Fällen
  dieselbe, und ein Abbruch mittendrin kostet keine Datei, sondern hinterlässt
  schlimmstenfalls eine Kopie zu viel.
- **Zwei Netze übereinander, mit Absicht.** Der Pflicht-Snapshot ist eine *Kopie* und
  bleibt liegen, auch wenn der Papierkorb geleert wird; der Papierkorb-Eintrag enthält
  die *Originale* und ist der schnelle Rückweg. Endgültig ist damit nur der Rückweg,
  nie der Charakter. Der Trash-Eintrag merkt sich in `snapshotId`, zu welcher Sicherung
  er gehört.
- **`Restore-Snapshot` brauchte genau eine Änderung:** `$istChar = ($Snapshot.kind -ne
  'full')` statt `-eq 'char'`. Danach holt der gewöhnliche Rückweg auch Gelöschtes
  zurück, samt anderem Namen. Dasselbe Muster in `Write-SnapshotInfo`.
- **`Remove-Item` statt `[IO.Directory]::Delete` beim Leeren.** Das README verspricht,
  dass eine Suche nach `Remove-Item` *jede* Stelle findet, an der dieses Programm etwas
  löscht. Eine Löschung, die durchs Raster fiele, wäre genau die eine, die niemand
  prüfen kann. Beim Ändern dieser Stelle also nicht auf .NET-Methoden ausweichen — und
  die Zahl im README mitzählen (Stand 1.3: acht Stellen).
- **Kein eigener Knopf zum Leeren — die Markierung entscheidet.** Das hat zwei Anläufe
  gebraucht. Zuerst stand „Leeren" als roter Symbolknopf neben „Löschen": zwei rote
  Knöpfe, sinngemäß derselbe Name, aber verschieden weite Wirkung. Der Captain fragte
  prompt, warum von zwei Charakteren die Rede sei, wenn nur einer markiert ist — die
  Zahl stimmte, die Gruppierung log. Der zweite Anlauf, eine eigene GroupBox
  „Papierkorb" mit Mengenangabe, war immer noch daneben: die Liste enthält *beides*,
  und wer einen Papierkorb-Eintrag markiert hatte, suchte die Löschung folgerichtig
  beim Papierkorb-Knopf.

  **Endstand, vom Captain vorgegeben:** eine Gruppe „Markierte Einträge" mit genau zwei
  Aktionen — *Wiederherstellen…* und *Löschen*. Was passiert, entscheidet die
  Markierung; die Filter darunter sind das Werkzeug, sie herzustellen. Der Papierkorb
  wird geleert, indem man auf „nur Papierkorb" filtert, alles markiert und löscht.
  `Clear-Trash` und `Get-TrashStats` sind damit ersatzlos entfallen — `Remove-Snapshot`
  räumt die leere `_Papierkorb`-Wurzel ohnehin mit weg.

  Dafür kann die Snapshot-Liste jetzt **Mehrfachauswahl** (`SelectionMode="Extended"`).
  Der Löschen-Knopf nennt die Anzahl in Klammern und heißt *Endgültig löschen*, sobald
  ausschließlich Papierkorb-Einträge markiert sind. Beim Rechtsklick bleibt eine
  bestehende Mehrfachauswahl erhalten, wenn die angeklickte Zeile dazugehört — sonst
  hätte das Menü die Auswahl zerstört, die man gerade aufgebaut hat.

  Lehre fürs nächste Mal: Wenn zwei Knöpfe dasselbe Wort tragen und sich nur in der
  Reichweite unterscheiden, ist nicht die Beschriftung das Problem, sondern dass es
  zwei Knöpfe sind.
- **Der Löschen-Dialog unterscheidet Papierkorb-Einträge.** Bei einem Snapshot stimmt
  „Die Spielstände selbst bleiben unberührt"; bei einem Papierkorb-Eintrag liegen dort
  die Originale, und der Satz klänge harmloser als die Lage ist. Dort steht deshalb,
  dass der schnelle Rückweg verschwindet und die Sicherung bleibt.
- **Die Filterzeile ist jetzt ein `WrapPanel`.** Mit dem dritten Häkchen passte sie nicht
  mehr in jede Fensterbreite und wurde rechts abgeschnitten. Im gerenderten Fenster
  aufgefallen, nicht im Test — Tests prüfen Verhalten, nicht Layout.

**Gemeinsame Basis, einmal bauen:** Dateisatz eines Charakters ermitteln, `Test-D2RRunning`,
Pflicht-Snapshot, Namensprüfung mit Kollisionstest — und der muss **geparkte** Charaktere
in `_Projekte\` mit einschließen, sonst kollidiert ein neuer Name unbemerkt mit einem
geparkten Dateisatz. Reihenfolge: Umbenennen zuerst (validiert die Basis), dann
Duplizieren (fast geschenkt), dann Löschen.

### Namensregeln — nachgeschlagen am 08.08.2026, nicht geraten

Quelle: Arreat Summit, die offizielle Blizzard-Spielhilfe
(`classic.battle.net/diablo2exp/basics/characters.shtml`). Gilt unverändert für D2R,
mehrfach in den Blizzard-D2R-Foren bestätigt.

- **Länge 2 bis 15 Zeichen.**
- **Nur Buchstaben A–Z**, groß und klein. **Keine Ziffern, keine Leerzeichen.**
- Dazu **entweder ein Bindestrich oder ein Unterstrich** — genau einer, und **nicht als
  erstes oder letztes Zeichen**.

Als Regex: `^(?=.{2,15}$)[A-Za-z]+([-_][A-Za-z]+)?$`

**Gegen den echten Bestand geprüft:** alle 33 Charaktere des Captains (14 im
Wurzelverzeichnis, der Rest geparkt in `_Projekte\`) erfüllen diese Regel — auch die
Grenzfälle `Amazone_Poison`, `HM-ONE` und `jdASSA-One`. Deshalb darf die Prüfung im
Programm **hart sperren** statt nur zu warnen: es gibt keinen vorhandenen Namen, den sie
verbieten würde.

Nicht verwechseln: die verwaisten `.ctlo`/`.keyo` mit Ziffern im Namen
(`Abracadabra213848843`) gehören **Online**-Charakteren. Für die gelten die
Battle.net-Regeln, und angefasst werden sie ohnehin nicht (siehe *Online-Charaktere
bleiben draußen*).

Grund für die Sorgfalt: Ein Name, den das Tool zulässt und das Spiel nicht, erzeugt einen
Charakter, der in der Auswahl fehlt.

### Umbenennen: was dabei zu beachten war

- **Nur die Schreibweise ändern ist der Sonderfall.** Windows unterscheidet in
  Dateinamen keine Groß-/Kleinschreibung, `jdbarb` → `jdBarb` ist für das Dateisystem
  also dieselbe Datei und wird als „Ziel existiert bereits" abgelehnt. `Rename-Character`
  erkennt das (`-eq` gleich, `-ceq` verschieden), nimmt diesen Fall von der
  Kollisionsprüfung aus und benennt über einen Zwischennamen um. Getestet wird, dass
  hinterher kein `~tmp`-Rest liegen bleibt.
- **Alles, was den Knopf sperrt, läuft durch die Live-Prüfung** — auch das laufende
  Spiel. Stünde die D2R-Sperre als eigene Zeile daneben, hübe der nächste Tastendruck
  sie wieder auf, weil `Register-NameCheck` den Knopf bei gültigem Namen freigibt. Als
  Nebeneffekt bekommt man den Knopf von selbst zurück, wenn man D2R bei offenem Dialog
  beendet und weitertippt.
- **Farbe folgt der Wirkung:** Die Zusatzprüfung färbt rot, wenn sie sperrt
  (`ExtraBlocks`), sonst orange. Eine orange Meldung an einem gesperrten Knopf wäre ein
  Widerspruch.
- **Immer nur ein Charakter.** Jeder braucht einen eigenen neuen Namen, eine
  Sammelaktion gäbe es dafür nicht.
- **Geparkte Charaktere sind ausgenommen** und werden mit Hinweis abgelehnt. Grund ist
  der Pflicht-Snapshot: `New-Snapshot` sieht nur in den Spielstand-Ordner, nicht in die
  Projektordner (*Offene Punkte*, Nr. 2). Ohne Sicherung wird nicht umbenannt, also muss
  ein geparkter Charakter erst zurückgeholt werden. Wenn das stören sollte, ist der
  richtige Weg, `New-Snapshot` um Projektordner zu erweitern — nicht, die Pflicht
  aufzuweichen.
- **Online-Reste bleiben liegen.** `.ctlo`/`.keyo` gehören Battle.net-Charakteren, auch
  wenn sie zufällig denselben Basisnamen tragen. Sie werden nicht mit umbenannt, und ein
  Test hält das fest.

### Duplizieren: der eine Unterschied zum Umbenennen

Beide teilen sich Dialog (`Show-NameDialog` mit `-Mode rename|copy`), Live-Prüfung und
Kollisionstest. Der Unterschied steckt in einem einzigen Fall, und der ist gefährlich:

**Eine andere Schreibweise reicht beim Duplizieren nicht.** Für Windows ist `NEUERHELD`
dieselbe Datei wie `neuerHeld` — beim Umbenennen ist das erwünscht (der Sonderfall mit
dem Zwischennamen oben), beim Duplizieren würde die „Kopie" das Original überschreiben
und der Charakter wäre weg. `Copy-Character` lehnt deshalb mit `-eq` ab, also ohne
Rücksicht auf Groß-/Kleinschreibung, und der Dialog sagt es beim Tippen. Ein Test hält
den Fall fest, samt Prüfung, dass das Original danach unverändert dasteht.

Zwei kleinere Entscheidungen: Das Namensfeld startet beim Duplizieren **leer** statt mit
dem alten Namen — vorbelegt würde es sofort rot, was nach Fehler aussieht, obwohl man
noch nichts getan hat. Und `Restore-Snapshot` läuft mit `-SkipSafetyBackup`, weil der
Zielname unmittelbar davor als frei geprüft wurde: es gibt nichts zu überschreiben und
damit nichts zu sichern.

**Bewusst abgewogen:** Mit diesen drei Aktionen wird der Backup-Manager wieder ein Stück
Char-Manager — wovon der Programmname am 03.08.2026 gerade weg wollte. Vertretbar, solange
jede dieser Aktionen einen Snapshot erzwingt, das Sichern also der Grund bleibt, warum sie
überhaupt im Programm sind.

## Fallstricke, die schon Blut gekostet haben

- `0xAA55AA55` **nicht** als Hex-Literal vergleichen: Windows PowerShell 5.1 liest das als
  negativen Int32, der Vergleich schlägt dann immer fehl. Deshalb dezimal `2857740885`.
- Keine `System.Collections.Generic.List[object]` verwenden: In PS 5.1 wirft schon `@(...)`
  um so eine Liste eine `ArgumentException`. Überall gewöhnliche Arrays benutzen.
- Zeitstempel niemals mit `[datetime]::Parse($x)` lesen: PowerShell 7 macht beim
  `ConvertFrom-Json` aus ISO-Strings bereits ein `DateTime`, Windows PowerShell 5.1 nicht.
  Bei einem `DateTime` wandelt PowerShell erst in die invariante Schreibweise `08/03/2026`
  um, und `Parse` liest die deutsch als 8. März — Tag und Monat vertauscht. Dafür gibt es
  `ConvertTo-DateTimeSafe` / `Format-Timestamp`.
- Nie eine DataGrid-Spalte nach einem Feld sortieren lassen, das aus `index.json`
  stammt: `ConvertFrom-Json` liefert Zahlen als `Int32`, frisch erzeugte Datensätze
  tragen `Int64`, und WPF wirft beim Vergleich „Fehler beim Vergleichen von zwei
  Elementen im Array". Dafür gibt es die typfesten Felder `SizeSort`, `LevelSort`,
  `LastPlayedSort` und `SortKey` — `SortMemberPath` zeigt immer auf eines davon.
- WPF braucht zwingend einen STA-Thread — daher `-Sta` im Starter.
- Das Skript war früher reines ASCII (Umlaute als `ae`/`oe`/`ue`). Das gilt **nicht mehr** —
  es enthält echte Umlaute und braucht deshalb zwingend das BOM, siehe *Kodierung*.
  Wer es „aufräumt" und das BOM entfernt, zerlegt unter PS 5.1 jeden Umlaut.
