# Remove the editor annotation tool in favor of recording-time drawing

The editor's "Annotations" panel (post-hoc rectangle/line drawing on the
timeline) is removed, and `EmphasisAnnotation` is repurposed into a recording-time
`Annotation` that the user draws live while capturing — the "circle the important
thing" workflow — and that fades after 3 seconds.

## Why

The goal is live, transient annotation during recording, not post-hoc editing.
Keeping a second drawing surface in the editor would mean two UI entry points
and two mental models for the same visual. The existing `EmphasisAnnotation`
model and its shared renderer are kept and extended (new kinds `brush`,
`ellipse`, `arrow`, plus color and fade), so no rendering code is thrown away —
only the editor-facing entry points (pencil inspector, timeline track) are
deleted.

## Consequences

- Old `.screenfree` projects still render their rectangle/line annotations
  (backward-compatible decode); they just can no longer be created or edited in
  the editor.
- Annotations are recording-only, fade after 3s, and are excluded from the
  "original media" export because they are metadata, not baked pixels.
