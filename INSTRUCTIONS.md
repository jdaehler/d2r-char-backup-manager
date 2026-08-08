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

### What the program remembers

Window size, the width of the left half, the column widths of both lists, the
sorting and both hide checkboxes are saved when you close the program and restored
on the next start. So you arrange your view once.

The window *position* is deliberately **not** remembered: if you work with two
screens and unplug one, you would otherwise find the window outside the visible
area.

If nothing fits any more, **Settings → Reset view** helps. It only resets the
view — paths, language and your backups are left untouched. The window restarts
briefly.

### Storing backups elsewhere

Under **Settings** you can pick any backup folder. A different drive than the one
holding your save games is a good choice — then your backups survive a disk
failure too.

## On first start: the notice

Before the first start a **notice about liability and your own responsibility**
appears. It cannot be skipped: only with the checkbox ticked and a click on
*I agree, start the program* does the main window open. After that it stays away —
unless the text changes materially.

The core in one sentence: the program is free and comes with no warranty
whatsoever, you use it on your own responsibility, and **you should make your own
copy of your save folder first** — with Windows Explorer, independently of this
program. It takes a minute and it is the most reliable way back there is.

You can read it again any time via the **About** button in the top right. It also
shows the version, the date you accepted the notice and the licence — and a button
there opens these instructions.

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
| **Park… / Bring back** | Sit in their own *Character selection* group. Take characters out of the D2R character selection and back in — see the separate section further down |

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
```

On top of that, everything in it comes from the same second. That is why I recommend
it for the shared stash case (see below).

**Online characters are left out.** The files `*.ctlo` and `*.keyo` are not backed
up. They only hold the key bindings of your Battle.net characters — the characters
themselves live on Blizzard's servers and can neither be backed up nor restored from
here. D2R never cleans these files up: they stay behind even for characters deleted
long ago, often at 0 bytes. In a real folder that came to 97 files out of 114 after
two years. Leaving them out does not just make a backup easier to read, it makes it
safer: otherwise restoring a whole folder would roll the bindings of *every* online
character back to how they were then, when all you wanted was one local character.

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

### Deleting a backup

The **Delete** button above the snapshot list on the right removes only the
*backup*, never a save game. To delete a character itself, use the left-hand side —
see the next section.

---

## Renaming, duplicating and deleting characters

The **Character** group at the top left holds three icon buttons. Each works on
**exactly one** selected character, and **a backup is taken automatically before
every one of them** — that cannot be switched off.

All three need **D2R to be closed**. While the game is running the buttons are
there, but the dialog will not let you go through with it.

### Rename

Renames all files of the character together. **Level, gear and progress stay
untouched** — in D2R the name lives in the file name only, not inside the save
file. The program writes nothing into the file itself.

The field checks along as you type:

* **Red field, greyed-out button** → that name will not work. The reason is right
  below it.
* Allowed are **2 to 15 letters**, plus at most **one** `_` or `-`, and not as the
  first or last character. **D2R accepts no digits and no spaces** — a name with a
  digit would produce a character you can no longer find in the game.
* Changing only the capitalisation (`jdbarb` → `jdBarb`) works.

### Duplicate

Creates a **copy under a new name**. The original stays exactly as it is, so
afterwards you have two characters. Handy before trying something that might go
wrong.

The **shared stash is not copied along** — it belongs to all characters at once
and exists only a single time.

Here a different capitalisation is **not** enough as a new name: to Windows that
would be the same file, and the copy would overwrite the original. The program
refuses it.

### Delete

The red button behind the separator. It is for "this really has to go". **To only
take a character out of the D2R character selection, park it instead** — see the
next section.

Deleting here is **safer than deleting inside D2R**, which is final and takes no
backup. There are two nets under you:

1. **The mandatory backup** is a copy and lands among the normal backups. It stays
   even when you empty the recycle bin.
2. **The recycle bin** holds the original files and is the quick way back.

This is the **program's own recycle bin**, not the Windows one. It sits next to
your backups as `_Papierkorb\`, with one subfolder per deletion.

Deleted characters appear in the snapshot list on the right with the type
**Recycle bin**. From there you bring them back the ordinary way via
**Restore…**, under a different name if you like.

There is a filter for it at the far right above the list:

* **all entries** — backups and recycle bin together (default)
* **without recycle bin** — only the ordinary backups
* **recycle bin only** — just the deleted characters, handy for tidying up

This affects the display only; it changes nothing about the recycle bin itself.

### Emptying the recycle bin

There is **no separate button** for it — it works like deleting any other entry:

1. Set the filter at the top right to **recycle bin only**.
2. Select everything in the list (**Ctrl+A**, or click the first row and
   shift-click the last).
3. Press **Delete**.

The button then reads *Delete for good* and shows the count in brackets. The
confirmation states how many entries and how much disk space are affected.

A **single** entry goes the same way: select it and delete — or, quicker,
**right-click the row**.

**Nothing is ever cleaned up on its own** — there is no age limit and no automatic
purge. And even afterwards the characters are not lost: the backups made before
each deletion remain. What is gone for good is only the quick way back.

**Nothing is ever cleaned up on its own** — there is no age limit and no automatic
purge. And even after emptying, the characters are not lost: the backups made
before each deletion remain. What is gone for good is only the quick way back.

### Parked characters are out of scope here

If a character is parked, all three buttons say: bring it back first. That is down
to the mandatory backup — it only reaches characters sitting in the save folder.
Better an honest refusal than working without a backup.

---

## Taking characters out of the game's list (parking)

With many characters you scroll through an endless list in D2R. **Parking** clears
characters out of the character selection without deleting them.

The trick behind it: D2R only shows characters whose files sit **directly** in the
save folder. Anything inside a subfolder is invisible to the game. So the program
moves parked characters into `_Projekte\<project name>\` inside the save folder.
Nothing is deleted, nothing is rewritten — only moved.

### How to do it

1. Select the characters on the left (Ctrl-click for several).
2. In the **Character selection** group press **Park…**.
3. Pick an existing project or type a new name — for example *Old heroes*,
   *Hardcore attempt*, *Ladder season*.
4. Done. Next time you start D2R they are gone from the selection.

**Bring back** undoes it: select the parked characters, press the button, and they
are back in the game's list.

### What you see in the list

Parked characters do **not** disappear from the program — they stay in the list,
just **greyed out and italic**, with their project in the *Project* column. That way
you never lose track of what you put away.

If that gets too crowded, the **hide parked** checkbox in the *Character selection*
group takes them out of the list. This changes nothing about the parking itself —
only the display. The checkbox is not remembered: after restarting the program the
parked ones are listed again.

### D2R must be closed

> **The program checks whether D2R is running before every park and bring-back —
> and **blocks** if it is.** There is no "continue anyway". The game keeps the save
> files open and writes them back when it exits; moving files underneath it would
> leave you with half a file set.

Two things this check honestly **cannot** do:

* It only sees *whether* the game is running, not whether it is writing right now.
  For this purpose that is enough.
* If you start D2R in the very second the files are being moved, the check comes
  too late. That is why it runs immediately before **and** immediately after — if
  something changed in between, the program tells you instead of hiding it.

### Important: parked is not backed up

A backup is a **copy** — if you lose it, you still have the original. A parked
character **is** the original, just somewhere else. Delete the project folder and
the character is gone.

That is why the program **automatically creates a backup of every character before
parking it**. This cannot be switched off. Each project folder also holds an
`_INFO.txt` explaining what is in there and how to move it back by hand if needed.

### Two small things

* **Parked characters cannot be backed up.** They are not in the save folder. If
  you select only parked ones and press *Back up selected*, the program says so.
  The number on the button counts only the active ones anyway.
* **The shared stash never travels along.** The stash belongs to all characters
  together and always stays in the save folder.
* **"Back up everything" does not cover parked characters** — it backs up the save
  folder, and parked ones live in a subfolder below it. They are covered by the
  mandatory backup taken when parking.

---

## Where things are

Backups go into the backup folder you chose:

```
_LIESMICH.txt                                explains the layout
index.json                                   all labels, tags and notes
Charaktere\<name>\<date_time> Lvl<n> <class>\
    _INFO.txt, the save files, SharedStash\
Kompletter Ordner\<date_time>\
    _INFO.txt, every file except the online leftovers (*.ctlo, *.keyo)
```

> **Why are those names German?** `Charaktere` ("characters"), `Kompletter Ordner`
> ("whole folder"), `SharedStash` and `_LIESMICH.txt` ("readme") keep their names
> even in the English interface. That is deliberate: if they were translated,
> switching the language would create a second set of folders, and backups made in
> one language would be invisible in the other. What you *read* inside
> `_LIESMICH.txt` and every `_INFO.txt` does follow the interface language.

**Folders instead of ZIPs, uncompressed** — on purpose. You should be able to see
in Explorer what was backed up when, and to copy it back **without this program**
in an emergency. Every backup holds an `_INFO.txt` with all the details and
step-by-step instructions for copying it back by hand.

Parked characters are **not** here; they live in the save folder under
`_Projekte\<project name>\`.

Next to the program sits `config.json` holding the paths and the language.

## Passing it on

Copy the whole folder. **Delete `config.json` first** — it contains personal
paths. Not strictly required (the program detects foreign paths and asks again),
but cleaner. The backups themselves (`index.json`, `snapshots`) belong to each
user and are not shared.

## Transparency: privacy, antivirus and your account

### It never goes online

There is no network code in it at all: no requests, no downloads, no telemetry, no
update check. Nothing about you or your characters leaves this machine.
`config.json` with your paths stays next to the program.

One thing to know: if you put the backup folder in a cloud — OneDrive, Dropbox —
your save games end up there. That is your choice, not something the program does
by itself.

### It does not touch the game

The only question it ever asks about *Diablo II: Resurrected* is whether it is
running right now, so it can refuse to pull files out from under a running game. It
never reads or writes memory, never hooks into anything, never starts or stops the
game. It works on files and nothing else.

### Can this get my account banned?

Honest answer, in two halves.

**It cannot reach online characters at all.** Ladder and other online characters
live on Blizzard's servers; nothing on your disk represents them. This program
works exclusively on the files of local, offline characters.

**But restoring an old save is still a change to your save game.** Nobody can
promise you what Blizzard makes of that. If you play online and care about your
account, keep in mind that this tool is meant for your local characters, and that
using it is your decision.

### Why does my antivirus get nervous?

Because it is a PowerShell script that copies files — malicious scripts use the
same pattern. You cannot look harmless to a heuristic and still do the work.

Better than any promise: **read it.** It is a single plain text file. Search for
`Remove-Item` and you will find all five places where anything is deleted, or
`Copy-Item` and `Move-Item` for every place files are moved.

The program carries no digital signature, so Windows may warn about an unknown
publisher. A certificate costs money every year — hard to justify for something
given away for free.

### Why does the launcher say `-ExecutionPolicy Bypass`?

Windows does not run unsigned PowerShell scripts by default. The flag lifts that
**for this one launch only**. It changes no setting, writes nothing to the registry
and leaves the policy on your system as it was. Once the program closes, nothing of
it stays active.

### What it does to your disk

Nothing is ever cleaned up automatically — on purpose, so nothing disappears behind
your back. A character backup costs about **100 KB** on average; measured across 72
real backups the range was 12 KB to 430 KB, depending on how many map files a
character has. That is written every time you press the button, even when nothing
changed. Backing up after every session, expect a few hundred megabytes over a
year, and delete old backups yourself when you want the space.

Every backup also records in its `_INFO.txt` which folder it came from. If you pass
a backup folder on to someone, your Windows user name travels with it in that path.

## If something goes wrong

| Problem | Cause |
|---|---|
| Nothing happens on click | The status bar at the bottom says what the program did |
| No characters listed | Wrong save folder — correct it under *Settings* |
| Window does not open | Right-click the `.cmd` → *Properties* → **Unblock** |
| Restored state is gone again | D2R was still running and overwrote it on exit |
| Parking does not work | D2R is running — the program blocks on purpose. Quit the game and it works |
| Parked character missing in the game | That is the point. Use *Bring back* to put it into the selection again |
