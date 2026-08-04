# Changelog

Newest entry first. The version number lives in `$script:AppVersion` and is shown
in the window title and on the right of the status bar.

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
