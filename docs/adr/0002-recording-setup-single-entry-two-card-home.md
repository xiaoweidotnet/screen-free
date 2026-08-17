# Recording setup gets a single entry: two-card home + setup page, inspector exits the recording business

The app opens on a home with two cards — 开始录制 (Record) and 剪辑 (Edit, hosting
the existing history/open/drag-drop). Starting a recording always goes through
one full-window Recording Setup page (capture source, audio & camera, script,
recording options) that defaults every control to its last-used value except the
script, which starts blank with a recent-scripts picker. The Recording section
of the editor's right inspector is removed; the toolbar record button routes
through the same setup page. The old global Speaker Notes feature becomes the
per-project Script, shown while recording in an auto-scrolling Teleprompter
panel (bottom-center, movable, ⌥Space pause, ⌥↑/⌥↓ speed).

## Why

Recording settings in two places (inspector and, implicitly, wherever a new
recording starts) inevitably drift apart — same reasoning as ADR 0001's removal
of the duplicate annotation entry point. The two-card home makes the product's
actual mental model (record vs edit) explicit without violating the "launch
into a blank home" constraint: history only appears after the user clicks Edit.
The script defaults blank because scripts have the opposite reuse pattern from
capture/audio settings — carrying the last script would force clearing it every
session; a recent-scripts picker gives reuse without the tax. Three structural
variants were prototyped (`swift run ScreenFree --prototype-home`, kept on the
prototype branch): A two-card home + sectioned setup page, B minimal home +
three-step wizard, C home-is-setup single page. A was chosen 2026-08-17.

## Consequences

- The inspector returns to editing-only concerns; there is exactly one code
  path into a recording.
- `ScreenFreeProjectSnapshot` gains an optional `script` field (nil default, so
  existing `.screenfree` files decode unchanged). The legacy UserDefaults
  speaker-notes keys retire after a one-time migration into the recent-scripts
  list (recent entries are full-text copies in UserDefaults, used only as a
  picker source; the project keeps its own copy).
- The Teleprompter is recording-only and excluded from capture like all
  ScreenFree panels; it is never rendered into preview or exports, so no
  renderer changes.
