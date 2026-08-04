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

### Sicherungen woanders ablegen

Unter **Einstellungen** lässt sich der Backup-Ordner frei wählen. Sinnvoll ist
eine andere Festplatte als die mit den Spielständen — dann sind die Sicherungen
auch bei einem Plattendefekt noch da.

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

## Wo liegt was

Die Sicherungen landen im gewählten Backup-Ordner:

```
index.json           alle Labels, Tags und Notizen
snapshots\*.zip      je Sicherung eine ZIP-Datei
```

Die ZIPs sind normale Archive — im Notfall kommst du auch ohne das Programm an
den Inhalt: einfach öffnen und die Dateien aus `char\` zurück in den
Spielstand-Ordner kopieren.

Neben dem Programm liegt `config.json` mit den Pfaden und der Sprache.

## Weitergeben

Den ganzen Ordner kopieren. **`config.json` vorher löschen** — sie enthält deine
persönlichen Pfade. Nötig ist das nicht (das Programm erkennt fremde Pfade und
fragt neu), aber sauberer. Die Sicherungen selbst (`index.json`, `snapshots`)
gehören dem jeweiligen Benutzer und werden nicht mitgegeben.

## Wenn etwas klemmt

| Problem | Ursache |
|---|---|
| Es passiert nichts beim Klick | Unten in der Statuszeile steht, was das Programm gemacht hat |
| Keine Charaktere in der Liste | Falscher Spielstand-Ordner — unter *Einstellungen* korrigieren |
| Fenster geht nicht auf | Rechtsklick auf die `.cmd` → *Eigenschaften* → **Zulassen** |
| Wiederhergestellter Stand ist wieder weg | D2R lief noch und hat beim Beenden überschrieben |
