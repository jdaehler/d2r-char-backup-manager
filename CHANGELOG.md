# Änderungsverlauf

Neuester Eintrag oben. Die Versionsnummer steht in `$script:AppVersion` und
erscheint im Fenstertitel sowie rechts in der Statuszeile.

## 1.2 — 2026-08-04

- **Haftungshinweis beim ersten Start.** Muss bestätigt werden, sonst startet das
  Programm nicht. Die Bestätigung liegt in `config.json` und gilt für die jeweilige
  Fassung des Textes; ändert sich der Text inhaltlich, wird erneut gefragt.
- **Über-Dialog** oben rechts: Version, Haftungshinweis mit Bestätigungsdatum,
  Lizenz aus der Datei `LICENSE`, und ein Knopf, der die Anleitung öffnet.
  Dasselbe Fenster wie die Startsperre, nur in zweiter Betriebsart — der Text
  steht deshalb nur einmal im Code.
- **Ansicht wird gemerkt:** Fenstergröße, Breite der linken Hälfte, Spaltenbreiten
  beider Listen und alle drei Ausblenden-Haken. Die Fensterposition bewusst nicht.
- **Knopf „Ansicht zurücksetzen"** in den Einstellungen. Setzt nur die Ansicht
  zurück; Pfade, Sprache und die Haftungsbestätigung bleiben.
- `LICENSE` (MIT) liegt jetzt im Weitergabe-Paket.
- Spaltenbreiten der Snapshot-Liste gekürzt — die Spalte *Größe* lag vorher
  außerhalb des sichtbaren Bereichs.

## 1.1 — 2026-08-04

- **Charaktere parken.** Der Dateisatz wandert nach `_Projekte\<Projekt>\` im
  Spielstand-Ordner. D2R listet nur `.d2s`-Dateien aus dem Wurzelverzeichnis,
  damit verschwindet der Charakter aus der Charakterauswahl, ohne gelöscht zu
  werden. Zurückholen jederzeit, auf Wunsch unter anderem Namen.
- Vor jedem Parken wird zwingend ein Snapshot angelegt — nicht abschaltbar.
  Ein geparkter Charakter ist das Original, keine Kopie.
- Blockierende D2R-Prüfung vor **und** nach dem Verschieben.
- Geparkte Charaktere bleiben in der Liste sichtbar: blass, kursiv, mit Projekt
  in der letzten Spalte. Haken „Geparkte ausblenden" blendet sie aus.
- Fenster auf 1520 px verbreitert, damit die neue Spalte hineinpasst.

## 1.0 — 2026-08-03

- Sichern einzelner Charaktere mit Mehrfachauswahl, dazu der komplette
  Spielstand-Ordner in einem Stück.
- Wiederherstellen, auf Wunsch unter anderem Namen. Automatische Sicherheitskopie
  vor jeder Wiederherstellung.
- Labels, Tags und Notizen je Sicherung; Suche und Filter; gemerkte Sortierung.
- Duplikaterkennung über SHA-256.
- Ablage als **Ordner statt ZIP**, unkomprimiert, mit `_INFO.txt` je Sicherung und
  `_LIESMICH.txt` im Wurzelverzeichnis — damit man ohne dieses Programm an die
  Dateien kommt.
- Oberfläche deutsch und englisch, beim ersten Start aus der Windows-Anzeigesprache.
- Weitergabe-Paket über `Build-Deploy.ps1`.

### Nachgewiesen

Der Wiederherstellen-Pfad ist am 04.08.2026 zum ersten Mal gegen die echten
Spielstände gelaufen (`jdBarb` → `TestKopie`, ohne Stash, D2R beendet) und im
Spiel bestätigt worden: beide Charaktere standen in der Auswahl, die Kopie ließ
sich spielen. Geprüft über SHA-256 des gesamten Spielstand-Ordners vor und nach
dem Vorgang — keine vorhandene Datei geändert, keine verschwunden.
