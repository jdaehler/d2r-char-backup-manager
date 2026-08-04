# D2R Char Backup Manager — Anleitung

Sichert und verwaltet lokale Charaktere von *Diablo II: Resurrected*. Du kannst
Sicherungen beschriften, mit Schlagwörtern versehen, Notizen anhängen und einen
Charakter unter einem **anderen Namen** zurückholen.

Funktioniert nur für **lokale Charaktere** (Offline). Online-Charaktere liegen auf
Blizzards Servern und lassen sich von außen nicht sichern.

---

## Was man braucht

* **Windows 10 oder 11** — mehr nicht.
* Windows PowerShell ist in Windows bereits enthalten. **Nichts zu installieren**,
  kein .NET, kein Python, keine Administratorrechte.
* *Diablo II: Resurrected* mit mindestens einem lokalen Charakter.

## Starten

1. ZIP-Datei auspacken, wohin du magst — Desktop, Dokumente, USB-Stick.
2. Doppelklick auf **`Start D2R Char Backup Manager.cmd`**.

Es gibt **nichts einzurichten**. Das Programm sucht deine Spielstände selbst und
legt seine Sicherungen in einen Unterordner **`Backups`** direkt neben sich. Wer
den ganzen Ordner woanders hinkopiert, nimmt seine Sicherungen also einfach mit.

> **Kam die ZIP-Datei aus dem Internet?** Windows blockiert heruntergeladene
> Dateien. Am einfachsten **vor** dem Auspacken: Rechtsklick auf die ZIP-Datei →
> *Eigenschaften* → unten **„Zulassen"** ankreuzen → *OK*. Dann sind auch alle
> ausgepackten Dateien frei. Wurde schon ausgepackt, dasselbe mit der `.cmd`.

### Falls keine Charaktere erscheinen

Dann liegt dein Spielstand-Ordner nicht dort, wo Windows ihn normalerweise
führt. Das Programm sagt dir beim Start, wo es gesucht hat; den richtigen Ordner
trägst du unter **Einstellungen** ein. Üblich ist:

```
C:\Users\<DeinName>\Saved Games\Diablo II Resurrected
```

### Was sich das Programm merkt

Fenstergröße, die Breite der linken Hälfte, die Spaltenbreiten beider Listen, die
Sortierung und die beiden Ausblenden-Haken werden beim Schließen gespeichert und
beim nächsten Start wiederhergestellt. Du richtest dir die Ansicht also einmal ein.

Die Fenster*position* wird bewusst **nicht** gemerkt: Wer mit zwei Bildschirmen
arbeitet und einen abzieht, fände das Fenster sonst außerhalb des sichtbaren
Bereichs wieder.

Passt gar nichts mehr, hilft **Einstellungen → Ansicht zurücksetzen**. Das setzt
nur die Ansicht zurück — Pfade, Sprache und deine Sicherungen bleiben unberührt.
Das Fenster startet dabei kurz neu.

### Sicherungen woanders ablegen

Unter **Einstellungen** lässt sich der Backup-Ordner frei wählen. Sinnvoll ist
eine andere Festplatte als die mit den Spielständen — dann sind die Sicherungen
auch bei einem Plattendefekt noch da.

## Beim ersten Start: der Hinweis

Vor dem ersten Start erscheint ein **Hinweis zur Haftung und zur Eigenverantwortung**.
Er lässt sich nicht überspringen: erst mit gesetztem Haken und einem Klick auf
*Einverstanden, Programm starten* öffnet sich das Hauptfenster. Danach kommt er
nicht wieder — es sei denn, der Text ändert sich inhaltlich.

Der Kern in einem Satz: Das Programm gibt es umsonst und ohne jede Gewährleistung,
die Benutzung geschieht auf eigene Verantwortung, und **du solltest dir vorher
selbst eine Kopie deines Spielstand-Ordners anlegen** — mit dem Windows-Explorer,
unabhängig von diesem Programm. Das dauert eine Minute und ist die zuverlässigste
Rückfahrkarte, die es gibt.

Nachlesen kannst du das jederzeit über den Knopf **Über** oben rechts. Dort stehen
auch die Version, das Datum deiner Bestätigung und die Lizenz — und von dort öffnet
ein Knopf diese Anleitung.

## Sprache

Rechts oben schaltet der Knopf **`EN`** auf Englisch um (und `DE` wieder zurück).
Das Fenster startet dabei kurz neu, die Einstellung bleibt gespeichert.

---

## Bedienung

### Sichern

| Knopf | Wirkung |
|---|---|
| **Markierte sichern (n)** | **Der einzige Knopf links, der etwas anlegt.** Sichert alle markierten Charaktere samt Shared Stash; die Zahl sagt dir vorher, um wie viele es geht |
| ☑ (Symbol) | Alle Charaktere markieren — entspricht Strg+A |
| ☐ (Symbol) | Markierung aufheben |
| 📂 (Symbol) | Spielstand-Ordner im Explorer anzeigen |
| 🔄 (Symbol) | Listen neu einlesen |
| **Alles sichern** | Steht in der eigenen Gruppe *Kompletter Ordner*. Sichert den ganzen Spielstand-Ordner in einem Stück |
| **Parken… / Zurückholen** | Stehen in der eigenen Gruppe *Spielanzeige*. Nehmen Charaktere aus der D2R-Charakterauswahl heraus und wieder hinein — siehe eigenen Abschnitt weiter unten |

Die Symbolknöpfe sind absichtlich ohne Text — fahre mit der Maus darüber, dann steht
da, was sie tun. Nur die beiden Knöpfe, die tatsächlich etwas anlegen, tragen Text.

**Mehrere markieren:** Strg-Klick für einzelne, Umschalt-Klick für einen Bereich,
**Strg+A** oder der Knopf *Alles markieren* für alle. Ein einzelner Klick markiert
genau einen — das ist der Normalfall.

### Was ist der Unterschied zwischen „Markierte" und „Alles sichern"?

Alle 28 Charaktere markieren und sichern ergibt **28 einzelne Charakter-Sicherungen**.
*Alles sichern* legt dagegen **eine** Sicherung des ganzen Ordners an — und die enthält
zusätzlich Dinge, die in keiner Charakter-Sicherung stecken:

```
Settings.json    Grafik, Ton, Tastenbelegung
*.fltr           deine Item-Filter
*.ctlo / *.keyo  Tastenbelegungen der Online-Charaktere
```

Außerdem stammt bei *Alles sichern* garantiert alles aus derselben Sekunde. Das ist
der Grund, warum ich sie beim Shared Stash empfehle (siehe unten).

Übersprungen wird dabei nichts: Was du markierst, wird gesichert, auch wenn sich
seit der letzten Sicherung nichts geändert hat. Die Statuszeile sagt dir hinterher,
wenn eine Sicherung inhaltlich einer früheren gleicht.

Sichern ist ungefährlich und verändert nie etwas am Spiel. Es geht auch bei
laufendem D2R — die Sicherung bekommt dann automatisch das Schlagwort
`spiel-lief`, weil der Stand älter sein kann als das aktuelle Spielgeschehen.

**Empfehlung:** nach jeder Spielsitzung einmal auf **Alle** drücken.

### Beschriften

Unten rechts lassen sich zu jeder Sicherung **Label**, **Tags** (durch Komma
getrennt) und eine **Notiz** eintragen — dann *Übernehmen*. Ohne Label
unterscheidest du deine Sicherungen später nur am Zeitstempel.

### Wiederherstellen

> **Vorher unbedingt D2R beenden.** Das Spiel schreibt seinen Stand beim Beenden
> zurück und würde die Wiederherstellung sonst wieder überschreiben. Läuft D2R,
> warnt das Programm unten rechts in Rot.

Sicherung auswählen → **Wiederherstellen…**. Im Dialog:

* **Ziel-Charaktername** — Originalname stehen lassen, um den Charakter zu
  ersetzen. Ein *anderer* Name legt eine **Kopie als neuen Charakter** an; das
  Original bleibt unangetastet.
* **Shared Stash mit wiederherstellen** — standardmäßig **aus**, und das ist
  meistens richtig. Siehe unten.
* **Sicherheitskopie vorher anlegen** — standardmäßig an, bitte anlassen. Damit
  landet der Zustand, der gleich überschrieben wird, vorher als Sicherung in der
  Liste (erkennbar am Zusatz *Auto*). Das ist deine Rückfahrkarte.

### Der Shared Stash — die einzige heikle Entscheidung

Die Truhe gehört **allen Charakteren gemeinsam**. Deshalb gibt es keine Variante,
die immer richtig ist:

| Du wählst | Folge |
|---|---|
| Stash **nicht** zurückspielen (Standard) | Die Truhe bleibt, wie sie jetzt ist. Hattest du seit der Sicherung Gegenstände vom Charakter in die Truhe gelegt, gibt es sie danach **doppelt**. |
| Stash **mit** zurückspielen | Der Charakter und die Truhe passen wieder zueinander. Alles, was du seit der Sicherung eingelagert hast, ist dann aber **weg**. |

Das Programm nimmt dir die Einschätzung ab: Im Wiederherstellen-Dialog steht unter
der Checkbox, ob sich die Truhe seit dieser Sicherung überhaupt verändert hat. Steht
dort *unverändert*, ist die Entscheidung egal. Steht dort in Rot, dass sie sich
geändert hat, lies den Satz — dann kostet das Häkchen dich echte Gegenstände.

**Faustregel:**

* **Nur der Charakter ist schiefgegangen** (gestorben, verskillt, falsch getauscht)
  → Häkchen weglassen. Das ist der Normalfall.
* **Du willst einen kompletten Zeitpunkt zurück**, Charakter *und* Truhe
  → nimm eine Sicherung per **Alles sichern** statt einer Charakter-Sicherung. Die ist
  von sich aus stimmig, weil alles aus derselben Sekunde stammt.
* **Im Zweifel** → erst ohne Häkchen wiederherstellen, im Spiel nachsehen. Die
  automatische Sicherheitskopie erlaubt dir jederzeit den Rückweg.

### Löschen

**Löschen** entfernt nur die *Sicherung*, niemals einen Spielstand.

---

## Charaktere aus der Spielanzeige nehmen (Parken)

Wer viele Charaktere hat, scrollt sich in D2R durch eine endlose Liste. **Parken**
räumt Charaktere aus der Charakterauswahl, ohne sie zu löschen.

Der Trick dahinter: D2R zeigt nur die Charaktere an, deren Dateien **unmittelbar**
im Spielstand-Ordner liegen. Was in einem Unterordner liegt, sieht das Spiel nicht.
Das Programm verschiebt geparkte Charaktere deshalb nach `_Projekte\<Projektname>\`
im Spielstand-Ordner. Nichts wird gelöscht, nichts umgeschrieben — nur verschoben.

### So geht's

1. Links die Charaktere markieren (Strg-Klick für mehrere).
2. In der Gruppe **Spielanzeige** auf **Parken…**.
3. Ein vorhandenes Projekt auswählen oder einen neuen Namen eintippen —
   zum Beispiel *Alte Helden*, *Hardcore-Versuch*, *Ladder-Saison*.
4. Fertig. Beim nächsten Start von D2R sind sie aus der Auswahl verschwunden.

**Zurückholen** macht es rückgängig: geparkte Charaktere markieren, Knopf drücken,
sie stehen wieder in der Spielauswahl.

### Was du in der Liste siehst

Geparkte Charaktere verschwinden **nicht** aus dem Programm — sie stehen weiter in
der Liste, nur **blass und kursiv**, mit ihrem Projekt in der Spalte *Projekt*. So
verlierst du nie den Überblick, was du weggeräumt hast.

Wird dir das zu voll, blendet der Haken **Geparkte ausblenden** in der Gruppe
*Spielanzeige* sie aus der Liste aus. Am Parken ändert das nichts — nur an der
Anzeige. Der Haken wird nicht gemerkt: nach einem Neustart des Programms stehen
die geparkten wieder mit in der Liste.

### D2R muss dabei geschlossen sein

> **Das Programm prüft vor jedem Parken und Zurückholen, ob D2R läuft — und
> **blockiert**, wenn ja.** Kein „trotzdem fortfahren". Das Spiel hält die
> Spielstanddateien offen und schreibt sie beim Beenden zurück; würde man
> währenddessen verschieben, käme dabei ein halber Dateisatz heraus.

Zwei Dinge, die diese Prüfung ehrlicherweise **nicht** kann:

* Sie sieht nur, *ob* das Spiel läuft, nicht ob es gerade schreibt. Für diesen
  Zweck genügt das.
* Startest du D2R in genau der Sekunde, in der verschoben wird, kommt die Prüfung
  zu spät. Deshalb wird direkt vorher **und** direkt danach geprüft — hat sich
  dazwischen etwas geändert, sagt das Programm es dir, statt es zu verschweigen.

### Wichtig: geparkt ist nicht gesichert

Eine Sicherung ist eine **Kopie** — geht sie verloren, hast du noch das Original.
Ein geparkter Charakter **ist** das Original, nur an einem anderen Ort. Löschst du
den Projektordner, ist der Charakter weg.

Deshalb legt das Programm **vor jedem Parken automatisch eine Sicherung** von jedem
betroffenen Charakter an. Das lässt sich nicht abschalten. In jedem Projektordner
liegt außerdem eine `_INFO.txt`, die erklärt, was da liegt und wie du es notfalls
von Hand zurückschiebst.

### Zwei Kleinigkeiten

* **Geparkte lassen sich nicht sichern.** Sie liegen nicht im Spielstand-Ordner.
  Markierst du nur geparkte und drückst *Markierte sichern*, sagt das Programm das.
  Die Zahl im Knopf zählt ohnehin nur die aktiven.
* **Der Shared Stash wandert nie mit.** Die Truhe gehört allen Charakteren
  gemeinsam und bleibt immer im Spielstand-Ordner liegen.
* **„Alles sichern" erfasst geparkte Charaktere nicht** — es sichert den
  Spielstand-Ordner, und geparkte liegen im Unterordner darunter. Abgesichert
  sind sie durch die Pflicht-Sicherung beim Parken.

---

## Wo liegt was

Die Sicherungen landen im gewählten Backup-Ordner:

```
_LIESMICH.txt                                erklärt den Aufbau
index.json                                   alle Labels, Tags und Notizen
Charaktere\<Name>\<Datum_Zeit> Lvl<n> <Klasse>\
    _INFO.txt, die Spielstanddateien, SharedStash\
Kompletter Ordner\<Datum_Zeit>\
    _INFO.txt, alle Dateien
```

**Ordner statt ZIP, unkomprimiert** — das ist Absicht. Du sollst im Explorer sehen
können, was wann gesichert wurde, und im Notfall **ohne dieses Programm**
zurückkopieren können. In jeder Sicherung liegt eine `_INFO.txt` mit allen Angaben
und einer Schritt-für-Schritt-Anleitung zum Zurückkopieren von Hand.

Geparkte Charaktere liegen **nicht** hier, sondern im Spielstand-Ordner unter
`_Projekte\<Projektname>\`.

Neben dem Programm liegt `config.json` mit den Pfaden und der Sprache.

## Weitergeben

Den ganzen Ordner kopieren. **`config.json` vorher löschen** — sie enthält deine
persönlichen Pfade. Nötig ist das nicht (das Programm erkennt fremde Pfade und
fragt neu), aber sauberer. Die Sicherungen selbst (`index.json`, `snapshots`)
gehören dem jeweiligen Benutzer und werden nicht mitgegeben.

## Transparenz: Datenschutz, Virenscanner und dein Konto

### Das Programm geht nirgendwo ins Netz

Es enthält überhaupt keinen Netzwerkcode: keine Abrufe, keine Downloads, keine
Telemetrie, keine Update-Prüfung. Über dich und deine Charaktere verlässt nichts
diesen Rechner. `config.json` mit deinen Pfaden bleibt neben dem Programm liegen.

Eines solltest du wissen: Wenn du den Backup-Ordner in eine Cloud legst — OneDrive,
Dropbox — landen deine Spielstände dort. Das ist deine Entscheidung, nicht etwas,
das das Programm von sich aus tut.

### Es fasst das Spiel nicht an

Das Einzige, was es über *Diablo II: Resurrected* wissen will, ist: läuft es
gerade? Nur damit es sich weigern kann, Dateien unter einem laufenden Spiel
wegzuziehen. Es liest oder schreibt keinen Speicher, klinkt sich nirgends ein,
startet und beendet nichts. Es arbeitet ausschließlich an Dateien.

### Kann ich dafür gebannt werden?

Ehrliche Antwort in zwei Teilen.

**An Online-Charaktere kommt es gar nicht heran.** Ladder- und andere
Online-Charaktere liegen auf Blizzards Servern; auf deiner Platte steht nichts von
ihnen. Das Programm arbeitet ausschließlich an den Dateien lokaler Charaktere.

**Einen alten Stand zurückspielen ist trotzdem eine Änderung am Spielstand.** Was
Blizzard davon hält, kann dir niemand versprechen. Wer online spielt und an seinem
Konto hängt, sollte im Kopf behalten: Dieses Werkzeug ist für die lokalen
Charaktere gedacht, und die Benutzung ist deine Entscheidung.

### Warum wird mein Virenscanner nervös?

Weil es ein PowerShell-Skript ist, das Dateien kopiert — dasselbe Muster benutzen
auch Schadprogramme. Harmlos aussehen *und* die Arbeit tun geht nicht beides.

Was besser hilft als ein Versprechen: **lies es.** Es ist eine einzige Textdatei.
Suche nach `Remove-Item`, dann findest du alle fünf Stellen, an denen überhaupt
etwas gelöscht wird, oder nach `Copy-Item` und `Move-Item` für jede Stelle, an der
Dateien wandern.

Eine digitale Signatur hat das Programm nicht, deshalb kann Windows vor einem
unbekannten Herausgeber warnen. Ein Zertifikat kostet jedes Jahr Geld — schwer zu
rechtfertigen für etwas, das verschenkt wird.

### Warum steht im Starter `-ExecutionPolicy Bypass`?

Windows führt unsignierte PowerShell-Skripte standardmäßig nicht aus. Die Angabe
hebt das **nur für diesen einen Start** auf. Sie ändert keine Einstellung,
schreibt nichts in die Registry und lässt die Richtlinie auf deinem System
unverändert. Nach dem Beenden bleibt nichts davon aktiv.

### Was es auf der Festplatte anrichtet

Aufgeräumt wird **nie** automatisch — absichtlich, damit nichts hinter deinem
Rücken verschwindet. Eine Charakter-Sicherung kostet im Schnitt rund **100 KB**;
über 72 echte Sicherungen gemessen lag sie zwischen 12 KB und 430 KB, je nachdem
wie viele Kartendateien ein Charakter hat. Das wird bei jedem Klick geschrieben,
auch wenn sich nichts geändert hat. Wer nach jeder Sitzung sichert, sollte über ein
Jahr mit ein paar hundert Megabyte rechnen und alte Sicherungen selbst löschen,
wenn er den Platz braucht.

In jeder Sicherung steht außerdem in der `_INFO.txt`, aus welchem Ordner sie kam.
Gibst du einen Backup-Ordner weiter, geht dein Windows-Benutzername in diesem Pfad
mit.

## Wenn etwas klemmt

| Problem | Ursache |
|---|---|
| Es passiert nichts beim Klick | Unten in der Statuszeile steht, was das Programm gemacht hat |
| Keine Charaktere in der Liste | Falscher Spielstand-Ordner — unter *Einstellungen* korrigieren |
| Fenster geht nicht auf | Rechtsklick auf die `.cmd` → *Eigenschaften* → **Zulassen** |
| Wiederhergestellter Stand ist wieder weg | D2R lief noch und hat beim Beenden überschrieben |
| Parken geht nicht | D2R läuft — das Programm blockiert dann bewusst. Spiel beenden, dann klappt es |
| Geparkter Charakter fehlt im Spiel | So soll es sein. Über *Zurückholen* kommt er wieder in die Auswahl |
