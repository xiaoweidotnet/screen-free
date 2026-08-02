# ScreenFree

ScreenFree is a native macOS screen recorder and non-destructive video editor,
implemented in SwiftUI, AppKit, ScreenCaptureKit, and AVFoundation.

## Product features

- Choose a display, window, or freely dragged recording area. Every connected
  display gets a live thumbnail and an explicit selection card.
- Record all system audio, only selected applications, or no system audio,
  plus an optional microphone. Device discovery, a live RMS/peak meter,
  silence/clipping detection, and safe post-record normalization are included.
  Optional real-time microphone cleanup applies an 80 Hz rumble filter,
  low-level noise gate, bounded automatic gain, and peak limiter before the
  independent microphone source track is encoded; system audio is untouched.
- Preview and record a selected camera as an independent editable picture-in-
  picture track.
- Hide the editor while recording and keep only a small floating timer/controller
  on the chosen display. A large centered countdown remains obvious before
  capture begins. ScreenFree excludes its own windows and audio from the
  captured source.
- Optionally switch to accessory mode during recording so the Dock icon
  disappears. Stop, countdown cancellation, and failure paths restore the
  previous activation policy before the editor returns.
- Optionally outline the exact display, window, or freeform area being captured.
  The click-through overlay turns orange while paused and is excluded from the
  recording with the rest of ScreenFree's UI.
- Keep persistent speaker notes in a movable 560×170 recording-only panel on
  the selected display. Empty notes stay hidden, and the panel is excluded from
  the capture with all ScreenFree windows.
- Pause and resume from the floating controller. Paused time is removed from
  the final screen/camera media, timer, cursor path, and click timeline.
- Choose what happens after stop: open the non-destructive editor, copy the
  original screen recording as a persistent file URL, or save an MP4 directly
  to a chosen location. The preference persists across launches.
- Record a separate 30 fps cursor path and click timeline. Create automatic
  click-focused zooms or manual zooms, move their focus point, move a zoom range,
  resize either edge down to 0.1 seconds, and choose Slow, Mellow, Quick, or
  Rapid motion—or tune a real four-control-point cubic Bézier and transition
  duration—shared by preview and export.
- Choose no click effect, a filled circle, an expanding ripple, or a rotating
  dashed ring; the selected effect is shared by preview, video export, and
  current-frame export.
- Optionally show recorded keyboard shortcuts as polished key labels. The
  privacy filter stores only combinations containing Command, Control, or
  Option—ordinary typing is never captured.
- Split, trim, remove, safely merge contiguous clips, speed up, slow down,
  mute, or amplify clips without modifying the original recording. Merge is
  rejected when it would discard different speed or volume settings. Clip
  blocks carry a scissors badge, and Delete acts on the block currently under
  the pointer before falling back to the selected block.
- Fit the whole timeline or zoom it to 64× with track-local controls, keyboard
  shortcuts, or a trackpad pinch. A native full-screen preview hides the editor
  chrome and returns to the workstation with Escape.
- Reset a clip's trim to the available source boundaries without overlapping
  neighboring clips or changing its speed and volume.
- Render a real decoded-audio waveform; source, 16:9, 9:16, 1:1, 4:3, or 3:4
  centered canvas crop; six built-in wallpapers with non-repeating randomize,
  plus gradient/solid/image backgrounds with image blur;
  padding, rounded corners, shadow, cursor effects, click ripples, captions,
  and camera layout in both preview and export.
- Optionally return the cursor to its opening position during the final 20% of
  the edit (capped at one second). Preview, current-frame output, MP4, and GIF
  share the same eased path and bundled cursor artwork.
- Replace the cursor consistently with a bundled arrow or link-pointer shape.
  Each style uses its own hotspot in preview, current-frame output, MP4, and
  GIF, and the choice travels with projects and portable style presets.
- Non-destructively remove short out-and-back cursor spikes with an adjustable
  threshold, smooth unusually rapid changes, and optionally interpolate the
  recorded 30 fps cursor samples into fluid frame-rate-independent movement.
  The original samples remain intact in the project, and preview, current-frame,
  MP4, and GIF rendering share the same interpolation rule.
- Generate editable captions with Apple's on-device speech recognizer. Add up
  to 100 deduplicated product names or specialist phrases as private
  project-level recognition context; the terms never leave the Mac.
- Export H.264/AAC MP4 or looping animated GIF at selectable frame rates,
  Source/720p/1080p/4K resolutions or an exact even 320–7680 px custom canvas,
  24/25/30/50/60 fps, and quality profiles, with live progress and cancellation
  that removes incomplete output. Custom dimensions center-crop without
  stretching. Send the full export directly to a file or the macOS clipboard.
- Copy the fully composed current frame to the clipboard or save it as PNG.
- Add timed spotlight highlights on the same editable region track used for
  privacy work: move the focus in the preview, resize either timeline edge,
  tune size/dimming/color, and bake the effect into current-frame, MP4, or GIF
  output while keeping the focus area undimmed.
- Save/open versioned `.screenfree` project files and autosave crash-recovery
  state without reopening stale media on a normal launch. A recording-history
  browser scans ScreenFree's Movies folder and reopens earlier captures for
  another editing pass.
- Switch between English, Simplified Chinese, and the system language without
  restarting.
- Run `Studio Check` before recording to verify screen access, automatic-click
  detection, storage, camera discovery, and microphone signal.

## Run

```bash
./script/build_and_run.sh
```

The development bundle is assembled at `dist/ScreenFree.app`.

## macOS permissions

- **Screen & System Audio Recording** is required for display/window capture.
- **Microphone** is required only when microphone recording or the input meter
  is enabled. Native microphone capture in recordings requires macOS 15 or
  later; the editor and system-audio recorder still run on macOS 14.
- **Camera** is required only when a camera is selected.
- **Input Monitoring** is required for automatic click-triggered zooms. Manual
  zooms and the editable cursor path still work without it.
- **Speech Recognition** is requested only when generating captions.

ScreenFree exposes the missing permission in `Studio Check` and opens the exact
System Settings page instead of silently degrading.

## Verification

Run all model and media-pipeline tests:

```bash
swift test
```

The 67-check suite creates real H.264 input media, exports MP4 and GIF through
the same renderer used by the app, and reopens the results to verify duration,
video tracks, center-cropped dimensions, file size, and GIF frame count. It also
joins two screen-recording segments carrying 48 kHz stereo audio and verifies
that duration and audio survive pause/resume finalization. A separate media test
also proves that selected-application audio remains aligned as an additional
editable source track, verifies exact independent system/microphone gains and
microphone mute before producing a consumer-ready MP4 mix; another cancels a
live GIF render and verifies
that no partial file remains, while a pasteboard test verifies full-video file
handoff. Localization tests also cover dynamic filenames, counts, errors, and
timeline summaries after an in-app language change. The real frame renderer
also verifies that the playhead cursor, active caption, and selected click
effect change the composed output pixels. Shortcut tests reject ordinary typing,
verify old-project migration, and compare real exported MP4 pixels with the
shortcut layer enabled and disabled.
Multi-display geometry tests also verify Quartz-to-AppKit placement for primary,
taller adjacent, and vertically arranged displays.
Recording-presentation tests verify Dock hiding is entered only once and always
restores the previous application policy, including opt-out and pre-existing
accessory-mode paths.
Desktop-icon presentation tests preserve whether Finder's prior value was
explicit, avoid touching an already-hidden desktop, and cover opt-out,
duplicate begin, exact restoration, and idempotent finish; the app also stores
a next-launch recovery record before changing Finder.
Camera-preview policy tests prove hiding the launcher/controller preview does
not depend on disabling camera selection, while automatic-zoom policy tests
cover enabled, disabled, and no-click outcomes without deleting raw clicks.
Speaker-note tests verify whitespace-aware visibility and exact placement on a
negative-coordinate secondary display.
Original-recording delivery tests replace an existing destination safely,
preserve the source on a same-file request, and verify localized dynamic
filenames. The same suite builds a real two-track audio asset, extracts the
second role to a one-track M4A with exact duration, atomically replaces an
existing file, and rejects an unavailable role instead of exporting the wrong
audio.
Timeline scaling tests verify one-click fit, enlarged scrollable content, exact
time/point round trips, and zoom-range drag deltas at non-default magnification.
A two-color camera composition test verifies both the current-frame renderer
and an actual MP4 preserve the picture-in-picture center while all four rounded
corners reveal the screen beneath it.
The shared cursor resolver also verifies an optional end-of-video freeze uses
the exact cutoff position while 0 seconds preserves movement through the final
frame. It additionally verifies the cursor-return duration and exact midpoint
and final positions; current-frame and actual MP4 tests compare enabled and
disabled output without relying on the system cursor image. The same tests
prove spike removal and rapid-path optimization reach current-frame and MP4
rendering rather than modifying the source samples. Pixel comparisons also
prove smooth interpolation differs from stepped 30 fps cursor sampling in both
current-frame output and a reopened MP4. Separate pixel comparisons prove the
arrow and pointer replacements reach both current-frame output and a reopened
MP4 rather than changing only the inspector preview.
Custom-motion tests solve the Bézier x-axis numerically, verify a linear and a
deliberate curve at exact timeline positions, and prove custom parameters
materially change frames produced by the real video composition.
Motion-blur tests resolve real zoom/pan and cursor velocity, compare enabled
and disabled current-frame pixels, and reopen actual MP4 exports to prove both
screen-transition and cursor blur are baked into delivery media.
Custom-resolution tests clamp invalid/odd values, verify center-crop geometry,
and reopen an actual MP4 to prove its encoded track is exactly 642×358.
Wallpaper tests verify catalog selection, non-repeating randomization,
project/preset migration, and materially different pixels from the same real
frame composition when switching back to a regular gradient.
Background-music tests loop a short audio file across the full edited timeline,
verify its independent mix volume, and reopen the actual MP4 to confirm audio
and duration survive export.
Privacy-redaction tests cover range clamping and legacy migration, then verify
an active timed mask produces black pixels in both the current-frame renderer
and a real MP4 while the same location remains visible outside its time range.
The same media suite verifies a timed spotlight preserves pixels inside its
focus hole, dims the exterior in current-frame output, and survives reopening
the actual exported MP4.
Caption-context tests sanitize comma/newline-separated phrases, deduplicate
case-insensitively, enforce phrase/count limits, and inspect the real
on-device speech request to prove the terms are supplied to recognition.
Microphone-enhancement tests pass real interleaved Float32 PCM through the same
sample-buffer entry point used by ScreenCaptureKit, prove disabled processing
is bit-for-bit unchanged, attenuate low-level noise, lift quiet speech, and
limit peaks to 0.98.
Style-preset tests round-trip the versioned `.screenfreepreset` format, reject
future versions, apply every captured visual setting, and safely fall back when
a referenced background image is unavailable.

The detailed Screen Studio inventory and evidence-backed parity checklist are in
[`docs/SCREEN_STUDIO_RESEARCH.md`](docs/SCREEN_STUDIO_RESEARCH.md) and
[`docs/PRODUCT_REQUIREMENTS.md`](docs/PRODUCT_REQUIREMENTS.md).
