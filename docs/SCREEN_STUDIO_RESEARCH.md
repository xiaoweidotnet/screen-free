# Screen Studio hands-on feature inventory

Observed directly in the installed Screen Studio app on 2026-07-29. This file
records only controls and behavior exposed by the running app; it is not based
on marketing copy or assumptions.

## Recording launcher

The compact `Start Recording` bar exposes:

- sources: Display, Window, Area, and Device;
- camera menu:
  - select a camera;
  - hide camera preview;
  - do not record camera;
- microphone menu:
  - select a microphone;
  - reduce noise and normalize volume;
  - disable automatic gain control;
  - do not record microphone;
- system audio:
  - record all applications;
  - record selected applications;
  - do not record system audio;
- recording options:
  - hide desktop icons;
  - hide the Screen Studio Dock icon while recording;
  - highlight the recorded area;
  - open the quick-share widget afterward;
  - show speaker notes;
  - countdown: none, 3, 5, or 10 seconds;
  - modern, forced-modern, or legacy recording engine.

The main `Record` menu also offers:

- record display, window, or area;
- after recording: create project, export to clipboard, create a shareable link,
  or save to file;
- automatically create zooms;
- new recording.

## Projects and media

The `File` menu exposes:

- recent projects, open project, and open last project;
- previous projects;
- create a project from an existing video;
- import preset;
- save, save as, show in Finder, and remove project.

The export menu can extract the original camera, microphone, system-audio, and
screen-recording files. It can also export the current frame as an image.

## Canvas and screen styling

Observed canvas controls:

- named aspect-ratio presets and crop;
- background types: wallpaper, gradient, solid color, and image;
- wallpaper categories and randomized wallpaper;
- background blur;
- padding;
- rounded corners;
- inset;
- shadow and advanced shadow settings.

## Cursor

Observed cursor controls:

- cursor size;
- always use the pointer cursor;
- hide when not moving;
- loop the cursor position back toward its initial position near the end;
- hide cursor;
- click effect: none, circle, ripple, or rotation;
- stop cursor movement before the final seconds of a recording;
- remove accessibility-induced cursor shakes and tune its threshold;
- optimize rapid cursor changes.

## Captions, audio, and shortcuts

- on-device transcript generation with Base, Small, or Medium model;
- automatic or chosen language;
- custom vocabulary/prompt for transcription;
- mute microphone;
- improve microphone audio by reducing noise and normalizing volume;
- optionally show pressed keyboard-shortcut labels in the video.

## Motion

- global motion blur;
- separate blur amounts for cursor movement, screen zooming, and screen panning;
- smooth cursor movement;
- cursor and zoom animation presets: Slow, Mellow, Quick, Rapid, or Customize.

## Timeline editing

Observed timeline capabilities:

- one or more visible timelines;
- video clips and a separate Zooms track;
- previous frame, play/pause, and next frame;
- split tool;
- timeline zoom in/out;
- clip speed: 0.5×, 0.75×, 1×, 1.2×, 1.4×, 1.6×, 1.8×, 2×,
  3×, 4×, 8×, 16×, or 24×;
- per-clip volume from 0% to 100%;
- remove, split at current time, reset trim, merge with next, and merge with
  previous.

ScreenFree parity: the shared timeline scale drives clips, ruler ticks,
playhead, waveform widths, and both edges of each Zooms bar. Native zoom-out,
zoom-in, percentage, one-click fit, and horizontal scrolling are implemented
with bilingual labels; point/time and resize-delta mapping are covered by a
model test.

## Export dialog

- MP4 or GIF;
- selectable frame rate;
- 720p, 1080p, 4K, and explicit pixel dimensions;
- Studio, Social Media, Web, and Web (Low) compression profiles;
- destinations: file, clipboard, or shareable link;
- estimated export time and output size.

The project menu also offers quick export to file, clipboard, and shareable
link, plus a history of clipboard exports.

## ScreenFree parity status

The authoritative implementation/verification matrix now lives in
`PRODUCT_REQUIREMENTS.md`. Since the first end-to-end proof above, ScreenFree
has added and exercised:

- live multi-display cards, freeform area picking, a recording-only mini
  controller, and self-window exclusion;
- optional click-through capture-boundary highlighting that remains outside the
  captured application stream;
- optional Dock-icon hiding via a restorable activation-policy state machine,
  including cancellation and failure cleanup;
- optional Finder desktop-icon hiding with exact prior-value restoration,
  normal-termination cleanup, and next-launch crash recovery;
- persistent recording-only speaker notes in a movable panel positioned on the
  selected display and excluded with the rest of ScreenFree's windows;
- persisted post-recording actions for editor, original-recording clipboard
  delivery, or original MP4 file save, with hosted sharing left explicit;
- microphone/camera discovery, a real microphone meter, independent camera
  recording, editable PIP with media-tested alpha-rounded MP4 output, and a
  preflight `Studio Check`;
- persisted microphone noise-reduction and volume-normalization switches wired
  into the independent ScreenCaptureKit microphone PCM path, with rumble
  filtering, low-level gating, bounded AGC, peak limiting, bit-identical bypass,
  and real interleaved CMSampleBuffer signal tests while system audio remains
  untouched;
- a persisted camera-preview visibility option that leaves the camera session
  and independent recording active while hiding launcher/controller previews;
- all-app, selected-app, or disabled system audio; selected-app audio uses an
  independently filtered stream so the visible screen is never filtered with it;
- deterministic system/microphone source-track roles with independent preview
  and export volume, microphone mute, and backward-compatible project recovery;
- decoded audio waveforms and safe normalization;
- imported background music with independent volume, synchronized looping
  preview, project recovery, and media-tested MP4 mixing;
- a ScreenFree-specific timed privacy-redaction track with preview dragging,
  two-edge time resizing, backward-compatible persistence, and current-frame
  plus MP4 pixel proof;
- timed spotlight highlights on the same movable/two-edge-resizable region
  track, with size, dim intensity, hue and duration controls plus even-odd
  focus-hole rendering proven in current-frame and reopened MP4 pixels;
- Clean, Vibrant, and Minimal built-in styles plus versioned portable style
  preset import/export with future-version rejection;
- movable and independently resizable zoom ranges (both edges verified in the
  running app), 0.1-second minimum zooms, cursor hide-idle, and click ripples;
- a persisted post-recording automatic-zoom switch that always retains raw
  click metadata for later manual regeneration;
- None, Circle, Ripple, and Rotation click effects shared by preview, video
  export, and current-frame export;
- privacy-filtered keyboard-shortcut labels shared by preview, current-frame
  rendering, and MP4/GIF export;
- adjustable end-of-video cursor freeze shared by preview, current-frame, and
  MP4/GIF export, with 0 seconds preserving full-length movement;
- an optional eased cursor return to the opening position during the final 20%
  (capped at one second), shared by preview/current-frame/MP4/GIF and rendered
  with bundled artwork even when the macOS system cursor image is unavailable;
- bundled arrow and link-pointer replacement with style-specific hotspots,
  project/preset persistence, legacy migration, and current-frame plus
  reopened-MP4 pixel proof;
- non-destructive short-spike removal with an adjustable threshold and
  rapid-change optimization, plus optional frame-rate-independent interpolation
  between recorded samples, shared by preview/current-frame/MP4/GIF while raw
  30 fps samples remain stored in the project; current-frame and reopened-MP4
  pixel comparisons prove smooth and stepped output differ;
- gradient/solid/image backgrounds and adjustable shadow;
- Aurora, Sunset, Ocean, Forest, Candy, and Graphite wallpaper presets with
  non-repeating randomization and shared preview/export rendering;
- on-device editable Apple Speech captions with project-private custom
  vocabulary/context, bounded deduplication, backward-compatible persistence,
  and direct request-configuration tests;
- MP4/GIF, Source/720p/1080p/4K resolution, quality, and
  24/25/30/50/60-fps export choices, plus exact even 320–7680 px custom
  dimensions that center-crop instead of stretching and are proven by a
  reopened 642×358 MP4;
- original screen/camera movie delivery without transcoding plus deterministic
  system-audio and microphone M4A extraction from persisted source-track roles;
- real MP4/GIF export progress plus cancellable rendering with incomplete-file
  cleanup;
- full MP4/GIF output to a chosen file or directly to the macOS clipboard;
- full-composition current-frame rendering to PNG or the macOS clipboard;
- source, 16:9, 9:16, 1:1, 4:3, and 3:4 canvases with centered aspect-fill
  crop plus image-background blur;
- source-frame-rate previous/next stepping rather than one-second jumps;
- shared Slow/Mellow/Quick/Rapid zoom easing across preview and export;
- a true Customize mode with transition duration and four cubic-Bézier control
  coordinates shared by preview, cursor alignment, current-frame output, and
  MP4/GIF export, including backward-compatible project/preset persistence;
- velocity-driven motion blur with global strength plus independent cursor,
  screen-zoom, and screen-pan controls shared by preview/current-frame/MP4/GIF,
  including real pixel proof and backward-compatible project/preset persistence;
- real pause/resume backed by media segments, with paused time removed from
  screen/camera output and cursor/click timestamps;
- safe merge-with-previous/next editing for compatible contiguous clips;
- neighbor-safe reset-trim editing backed by original source duration;
- versioned project files plus verified crash/relaunch recovery;
- English/Simplified Chinese/system-language switching.

Current deliberate gaps, rather than guessed parity claims, are third-party
cursor packs and hosted sharing.
