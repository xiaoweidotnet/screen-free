# ScreenFree

A native macOS screen recorder and non-destructive video editor. Every visual
effect — cursor, clicks, zooms, redactions, spotlight, captions, camera PIP, and
annotations — is stored as metadata and composited by one shared renderer for
preview, current-frame export, MP4, and GIF.

## Language

**Annotation**:
A timed, non-destructive freehand or shape marking drawn over a recording while
it is being captured; rendered by the shared compositor only inside its fade
window.
_Avoid_: EmphasisAnnotation, drawing, doodle, markup, scribble

**Brush**:
The freehand annotation kind (`kind = .brush`), a stroke built from a sequence
of normalized points.
_Avoid_: pen, pencil

**Fade**:
The visibility window of an annotation — visible from `start` until
`start + duration` (default 3s), then gone. ScreenFree uses Fade only; it has no
freeze/persist counterpart like ScreenDraw's Freeze mode.
_Avoid_: dissolve, expire

**Source time / Edit time**:
Metadata (cursor, clicks, shortcuts, annotations) is stored in source time; the
timeline maps it to edit time through clip playback rate and trimming for
rendering.

**Normalized coordinates**:
Geometry (cursor, regions, annotation points) stored in 0…1 relative to the
recorded source frame, so it survives resolution and canvas changes.
_Avoid_: pixels, points, screen coordinates

**Script**:
The spoken text attached to one recording project. Pasted or imported before
recording, persisted with the project, blank by default for a new recording.
_Avoid_: speaker notes, narration copy, script text

**Teleprompter**:
The recording-only floating panel that auto-scrolls the project's Script at an
adjustable speed. Excluded from capture like all ScreenFree panels; never
rendered into preview or exports.
_Avoid_: speaker notes panel, script overlay

**Recording Setup**:
The single pre-recording configuration page (capture source, audio, camera,
script, teleprompter defaults) reached from the Record entry. Every control
defaults to its last-used value except the Script, which starts blank with a
recent-scripts picker.
_Avoid_: recording inspector, record settings dialog
