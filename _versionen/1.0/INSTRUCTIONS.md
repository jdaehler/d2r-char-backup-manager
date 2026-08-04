# D2R Char Backup Manager — Instructions

Backs up and manages local *Diablo II: Resurrected* characters. You can label
backups, tag them, attach notes, and restore a character under a **different
name**.

Works for **local (offline) characters** only. Online characters live on
Blizzard's servers and cannot be backed up from outside the game.

---

## What you need

* **Windows 10 or 11** — that is all.
* Windows PowerShell ships with Windows. **Nothing to install** — no .NET, no
  Python, no administrator rights.
* *Diablo II: Resurrected* with at least one local character.

## Starting it

1. Extract the ZIP file wherever you like — desktop, documents, USB stick.
2. Double-click **`Start D2R Char Backup Manager.cmd`**.

There is **nothing to set up**. The program finds your save games by itself and
stores its backups in a **`Backups`** subfolder right next to it. Move the whole
folder somewhere else and your backups simply come along.

> **Did the ZIP come from the internet?** Windows blocks downloaded files. The
> easiest fix is **before** extracting: right-click the ZIP → *Properties* →
> tick **Unblock** at the bottom → *OK*. Everything extracted from it is then
> free too. If you already extracted it, do the same with the `.cmd`.

### If no characters show up

Then your save folder is not where Windows usually keeps it. The program tells
you at startup where it looked; enter the correct folder under **Settings**. The
usual location is:

```
C:\Users\<YourName>\Saved Games\Diablo II Resurrected
```

### Storing backups elsewhere

Under **Settings** you can pick any backup folder. A different drive than the one
holding your save games is a good choice — then your backups survive a disk
failure too.

## Language

The **`EN`** button in the top right switches the interface to English (and `DE`
switches back). The window briefly restarts; the setting is remembered.

---

## Using it

### Backing up

| Button | What it does |
|---|---|
| **Back up selected (n)** | **The only button on the left that creates anything.** Backs up every selected character including the shared stash; the number tells you up front how many that is |
| ☑ (icon) | Select all characters — same as Ctrl+A |
| ☐ (icon) | Clear the selection |
| 📂 (icon) | Show the save folder in Explorer |
| 🔄 (icon) | Reload the lists |
| **Back up everything** | Sits in its own *Whole folder* group. Backs up the entire save folder in one piece |

The icon buttons deliberately carry no text — hover over one and it tells you what it
does. Only the two buttons that actually create something are labelled.

**Selecting several:** Ctrl-click for individual ones, Shift-click for a range,
**Ctrl+A** or the *Select all* button for all. A plain click selects exactly one —
the normal case.

### What is the difference between "selected" and "everything"?

Selecting all 28 characters and backing them up gives you **28 separate character
backups**. *Back up everything* creates **one** backup of the whole folder — and that
one also contains things no character backup holds:

```
Settings.json    graphics, sound, key bindings
*.fltr           your item filters
*.ctlo / *.keyo  key bindings of your online characters
```

On top of that, everything in it comes from the same second. That is why I recommend
it for the shared stash case (see below).

Nothing is skipped: whatever you select gets backed up, even if nothing changed
since the last backup. The status bar tells you afterwards if a backup is identical
in content to an earlier one.

Backing up is safe and never changes anything in the game. It also works while
D2R is running — the backup then automatically gets the tag `spiel-lief`, because
the saved state may be older than what is happening in the game right now.

**Suggestion:** press **All** once after every play session.

### Labelling

At the bottom right you can give each backup a **label**, **tags** (comma
separated) and a **note** — then press *Apply*. Without a label you will only be
able to tell your backups apart by their timestamp.

### Restoring

> **Quit D2R first.** The game writes its state back when it exits and would
> otherwise overwrite your restore. While D2R runs, the program shows a red
> warning in the bottom right.

Select a backup → **Restore…**. In the dialog:

* **Target character name** — keep the original name to replace the character. A
  *different* name creates a **copy as a new character**; the original is left
  untouched.
* **Also restore the shared stash** — **off** by default, and that is usually
  right. See below.
* **Create a safety backup beforehand** — on by default, please leave it on. The
  state that is about to be overwritten is saved first and appears in the list
  marked *Auto*. That is your way back.

### The shared stash — the one tricky decision

The stash belongs to **all characters together**. So there is no option that is
always correct:

| Your choice | Consequence |
|---|---|
| Do **not** restore the stash (default) | The stash stays as it is now. If you moved items from the character into the stash since the backup, you will end up with **duplicates**. |
| **Do** restore the stash | Character and stash match each other again. But everything you stored since the backup is **gone**. |

The program does the judging for you: under the checkbox it tells you whether the
stash has changed at all since that backup. If it says *unchanged*, the choice does
not matter. If it says in red that it changed, read the sentence — the checkbox will
cost you real items.

**Rule of thumb:**

* **Only the character went wrong** (died, misspent skills, bad trade)
  → leave the box unticked. This is the normal case.
* **You want a whole moment in time back**, character *and* stash
  → use a **Back up everything** backup instead of a character backup. That one is
  consistent by design because everything comes from the same second.
* **In doubt** → restore without the box first and check in the game. The automatic
  safety backup always lets you go back.

### Deleting

**Delete** only removes the *backup*, never a save game.

---

## Where things are

Backups go into the backup folder you chose:

```
index.json           all labels, tags and notes
snapshots\*.zip      one ZIP file per backup
```

The ZIPs are ordinary archives — in an emergency you can get at the contents
without this program: open the ZIP and copy the files from `char\` back into the
save folder.

Next to the program sits `config.json` holding the paths and the language.

## Passing it on

Copy the whole folder. **Delete `config.json` first** — it contains personal
paths. Not strictly required (the program detects foreign paths and asks again),
but cleaner. The backups themselves (`index.json`, `snapshots`) belong to each
user and are not shared.

## If something goes wrong

| Problem | Cause |
|---|---|
| Nothing happens on click | The status bar at the bottom says what the program did |
| No characters listed | Wrong save folder — correct it under *Settings* |
| Window does not open | Right-click the `.cmd` → *Properties* → **Unblock** |
| Restored state is gone again | D2R was still running and overwrote it on exit |
