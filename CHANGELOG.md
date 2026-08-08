# Changelog

Newest entry first. The version number lives in `$script:AppVersion` and is shown
in the window title and on the right of the status bar.

## 1.3 — 2026-08-08

Three actions straight on the character list: **rename**, **duplicate** and
**delete**. Each of them takes a backup first, and that cannot be switched off —
that mandatory backup is the reason these actions belong in a backup program at
all. They sit in their own "Character" group as icon buttons; delete is red and
stands behind a separator, because it is the only one that takes something away.

- **Rename.** All files of the character are renamed together. Nothing inside the
  save file is touched: in D2R the name lives in the file name alone, so this is
  pure file renaming — no binary editing, no checksum. Previously this was only
  possible as a detour through restoring under a different name, which left the
  old character behind to be cleaned up by hand.
  - Changing only the capitalisation works as well (`jdbarb` → `jdBarb`). Windows
    treats those as the same file name, so it is done via an intermediate name.
- **Duplicate.** Copies the file set under a new name; the original stays exactly
  as it is. The shared stash is *not* copied along — it belongs to all characters
  at once. Internally this is a backup that is immediately written back under the
  new name, so it uses the same well-tested path as restoring.
  - Here a different capitalisation is **refused**: to Windows the "copy" would be
    the same file and would overwrite the original.
- **Delete, with the program's own recycle bin.** Safer than deleting inside D2R,
  which is final and takes no backup. Two nets, on purpose: the mandatory backup
  is a copy and remains even when the bin is emptied, while the bin holds the
  originals and is the quick way back. Emptying ends the quick way back, not the
  character.
  - Deliberately **not** the Windows recycle bin: restoring from that one in
    Explorer would put the files straight back where they came from, so the
    character would reappear in the D2R selection without this program knowing.
  - Location `_Papierkorb\` next to the backups, one folder per deletion with a
    timestamp in its name and an `_INFO.txt`. Entries show up in the snapshot list
    marked as "Recycle bin" and can be brought back the ordinary way — including
    under a different name.
  - **No separate "empty" button.** Emptying is the same move as any other
    deletion: set the filter to *recycle bin only*, select everything, press
    Delete. For that the snapshot list now allows **multiple selection**; the
    Delete button shows the count and reads *Delete for good* when only recycle
    bin entries are selected.
  - **No automatic cleanup, no age limit.** Deleting happens only when you ask
    for it, and the confirmation states how many entries and how much data it
    concerns.
  - Files are copied and verified first and only then removed, never the other way
    round. If the backup folder cannot be reached, deleting does not start at all.

**Name checking is now correct, and it happens while you type.** The rules were
looked up in Blizzard's official game guide rather than guessed: 2 to 15
characters, letters A–Z only, plus at most one `_` or `-` that may not be the
first or last character. The previous check allowed digits and a trailing
separator — names D2R does not accept, which would have produced a character
missing from the selection. The field now turns red and the button greys out as
soon as a name will not work; orange marks the cases that are allowed but worth a
second thought, such as an existing name that would be overwritten when restoring.
Collision checking includes parked characters, which used to be a blind spot.

**Snapshot list:** multiple selection, a right-click menu with *Restore…* and
*Delete*, and a filter for the recycle bin (*all entries* / *without recycle bin* /
*recycle bin only*). The button group above it is named after what it acts on —
the selected entries — instead of after the kind of thing in the list.

Not covered: parked characters cannot be renamed, duplicated or deleted directly.
Bring them back first. The mandatory backup does not reach into project folders,
and rather than weaken that rule the action is refused with a note.

## 1.21 — 2026-08-06

A note on the numbering: the second digit after the dot is a bug-fix counter on the
release it hangs off. So 1.21 is the first fix to 1.2, 1.22 would be the second, and
the next proper release is 1.3.

- **Online characters are no longer backed up.** The files `*.ctlo` and `*.keyo`
  are now excluded everywhere: from the whole-folder backup, from the file count
  shown before it, and from a character's file set. They only ever held the key
  bindings of Battle.net characters — the characters themselves live on Blizzard's
  servers and this program can neither back them up nor restore them.
- Why it matters beyond tidiness: D2R never deletes these files, not even for
  characters deleted long ago, so they pile up (in a real folder, 97 files out of
  114 after two years). Restoring a whole folder used to copy all of them back,
  rolling the bindings of *every* online character to their state at backup time
  when the point was to bring back one local character. That cannot happen now —
  the files are neither saved nor written back.
- Which extensions belong to online characters was verified against the Blizzard
  D2R forums, not guessed: online characters use `.ctlo` and `.keyo` and nothing
  else; `.d2s`, `.ctl`, `.key`, `.map` and `.ma0`–`.ma3` are local. See
  `ENTWICKLUNG.md`.
- Test suite extended: the sandbox now seeds online leftovers, including one that
  shares its base name with a local character, and checks that they stay out of
  both backup kinds and out of parking.
- Older backups keep the files they were made with. Nothing about them changes,
  and restoring one still works.

## 1.2 — 2026-08-04

- **Liability notice on first start.** Has to be accepted once, otherwise the
  program does not start. The acceptance is stored in `config.json` and applies to
  that wording of the text; if the text changes materially, everyone is asked again.
- **About dialog** in the top right: version, the notice together with the date it
  was accepted, the licence read from the `LICENSE` file, and a button that opens
  the instructions. It is the same window as the start gate in a second mode, so
  the text exists only once in the code.
- **The view is remembered:** window size, width of the left half, column widths of
  both lists and all three hide checkboxes. The window *position* deliberately is
  not — unplug a second monitor and the window would come back off-screen.
- **"Reset view" button** in the settings. Resets the view only; paths, language
  and the accepted notice stay.
- `LICENSE` (MIT) is now part of the distributed package.
- Column widths of the snapshot list trimmed — the *Size* column used to sit
  outside the visible area.
- **Dates now follow the interface language.** German keeps `04.08.2026`, English
  gets `2026-08-04` — ISO rather than `08/04/2026`, because the American and
  British orders swap day and month and you cannot tell them apart by looking.
  Sorting is unaffected: it never used the formatted text.
- The test suite checks that every visible string has an English counterpart, so a
  forgotten translation fails a test run instead of surfacing in the program.
- **Only one window at a time.** Two running instances would both write the same
  `index.json`, and whichever saved last would silently drop the other one's
  labels, tags and notes. A second start now says so and stops. The lock is
  released before the restart that a language switch or "reset view" performs,
  otherwise the program would lock itself out.

## 1.1 — 2026-08-04

- **Parking characters.** The file set moves to `_Projekte\<project>\` inside the
  save folder. D2R only lists `.d2s` files from the root, so the character
  disappears from the character selection without being deleted. Bringing it back
  works at any time, optionally under a different name.
- A backup of every character is taken before parking, and it cannot be switched
  off. A parked character is the original, not a copy.
- Blocking check for a running D2R before **and** after the move.
- Parked characters stay visible in the list: greyed out, italic, with their
  project in the last column. A "hide parked" checkbox takes them out of the view.
- Window widened to 1520 px so the new column fits.

## 1.0 — 2026-08-03

- Backing up single characters with multi-selection, plus the entire save folder
  in one piece.
- Restoring, optionally under a different name. An automatic safety copy is taken
  before every restore.
- Labels, tags and notes per backup; search and filters; remembered sort order.
- Duplicate detection via SHA-256.
- Storage as **folders instead of ZIP archives**, uncompressed, with an `_INFO.txt`
  in every backup and a `_LIESMICH.txt` at the root — so the files are reachable
  without this program.
- Interface in German and English, picked from the Windows display language on
  first start.
- Distributable package built by `Build-Deploy.ps1`.

### Verified against real save games

On 2026-08-04 the restore path ran against the real save folder for the first time
(`jdBarb` → `TestKopie`, without the stash, D2R closed) and was confirmed in the
game: both characters appeared in the selection and the copy could be played.
Checked with SHA-256 over the entire save folder before and after — no existing
file changed, none disappeared, and only the five expected new files appeared.

Parking was run against the real save folder the same day and confirmed in the
game in both directions: parked characters were gone from the character selection,
and one of them was brought back and appeared there again. The round trip matters
more than the one-way journey — a fault while bringing a character back would not
look like a fault to the user, it would look like a lost character.
