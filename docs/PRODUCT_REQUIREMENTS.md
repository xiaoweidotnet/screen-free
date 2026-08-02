# ScreenFree product requirements and evidence

This is the completion checklist for the commercial macOS product. A row is
only marked verified after the native app has been exercised, not merely after
the code compiles.

## Recording

| Requirement | Screen Studio evidence | ScreenFree state |
| --- | --- | --- |
| Select one of multiple displays | Recorder has Display/Window/Area/Device modes; display selection occurs before recording | Implemented with one card and live thumbnail per `SCDisplay`; verified on the currently attached display, multi-display hardware verification still required |
| Record one window | Observed Window mode | Implemented with ScreenCaptureKit window enumeration |
| Record an area | Observed Area mode; official guide supports dragging or entering dimensions | Verified: full-display freeform picker dims the outside with a true transparent cutout; a real 80% area recording produced 1210×786 H.264/AAC media |
| Hide the editor while recording | User-supplied screenshot and observed compact recorder | Verified: regular editor is ordered out and a 470×72 floating controller is placed on the selected display |
| Hide the Dock icon while recording | Observed recording option | Optional accessory-mode transition is implemented and persisted as a recording preference. The previous activation policy is restored before the editor on stop, countdown cancellation, or start/stop failure; a state-machine test covers duplicate begin, opt-out, pre-existing accessory mode, and idempotent finish. Live visual verification remains pending unlock |
| Hide desktop icons while recording | Observed recording option | Optional Finder `CreateDesktop` transition is implemented as a persisted recording preference. ScreenFree stores whether the prior value was explicit as well as its Boolean value, restores it on stop/cancel/failure/normal termination, and leaves a crash-recovery record that is retried on the next launch. Finder is refreshed only when a real visibility transition occurs. State-machine tests cover inherited-visible, already-hidden, opt-out, duplicate begin, exact restoration, and idempotent finish; live Finder verification remains pending unlock |
| Do not bake product UI into the recording | Screen Studio keeps its camera/controller editable and outside the final result | Verified by extracted source frame; ScreenFree excludes its own `SCRunningApplication` from the content filter |
| Highlight recorded area | Observed recording option | Optional click-through red dashed border follows the exact ScreenCaptureKit source frame and turns orange while paused. The overlay belongs to ScreenFree's excluded application; Quartz-to-AppKit placement is tested for primary, adjacent-taller, and vertically arranged displays, with final live visual validation pending unlock |
| Speaker notes | Observed recording option | Persistent notes can be edited before or during recording and appear in a movable 560×170 recording-only panel at the bottom center of the selected display. Whitespace-only notes remain hidden; the panel is part of ScreenFree's excluded application and is removed on stop, cancellation, or failure. Visibility and negative-coordinate secondary-display placement are tested; live visual verification remains pending unlock |
| System audio | Observed All Apps / Selected Apps / Off | All applications, selected applications, and off are implemented. Selected-app mode uses a separate ScreenCaptureKit audio stream, aligns it by presentation timestamp, and appends it without filtering the visible display. ScreenFree writes the primary system and microphone tracks itself, so their order is deterministic rather than inferred from an undocumented native-recorder order. Live all-app + microphone recording produced one H.264 screen track and two independent 48 kHz stereo AAC tracks; the deterministic two-track mixer is also media-tested |
| Microphone detection and enhancement | Observed device menu, noise reduction, volume normalization/AGC, and white input meter | Device enumeration, stable device ID, permission state, real RMS/peak meter, silence/clipping detection, and selected-device ScreenCaptureKit recording are implemented. Persisted Reduce noise and Normalize volume switches process only the independent microphone PCM before AAC encoding: 80 Hz high-pass filtering, a low-level adaptive gate, bounded automatic gain, and a 0.98 peak limiter. A real interleaved Float32 CMSampleBuffer test proves disabled samples remain bit-identical, noise falls, quiet speech rises, and peaks remain bounded. System audio bypasses the processor. Microphone recording requires the macOS 15 stream API and is explicitly rejected rather than silently producing no microphone track on macOS 14 |
| Camera detection | Observed device menu, hide preview, and no-camera options | Device enumeration, permission state, live preview, separate camera movie recording, editable preview player, and export picture-in-picture are implemented. A persisted Hide Preview option removes both launcher and compact-controller previews without stopping the capture session or camera recording; a visibility-policy test covers no camera, hidden, and visible states. Live FaceTime camera permission, compact-controller preview, 1920×1080 recording, editor preview, and final MP4 composition are verified |
| Countdown | Observed None/3/5/10 seconds | Implemented in the compact controller plus a dedicated 320×280 centered overlay with a 132 pt numeral. The live three-second path was exercised before a real recording; geometry and visibility policy are covered by tests |
| After-recording action | Observed create project, clipboard, share link, or file | Open editor, copy original recording to the clipboard, and save original MP4 to a chosen file are implemented as persisted choices. Quick delivery is explicitly labeled as original screen media so camera/cursor/zoom composition is never silently promised. File replacement and same-source preservation are tested; hosted share remains a deliberate external-service gap |
| Cursor/click/shortcut metadata | Automatic zooms are click-driven; shortcut labels and an automatic-zoom recording option were observed | Independent 30 fps cursor samples only control focus and never trigger zooms. Left clicks and right-button holds of at least 0.5s generate zooms; short right clicks do not. Generated and legacy zooms follow the cursor by default, while an explicit fixed focus remains respected. A persisted Automatically Create Zooms switch controls post-recording generation without deleting raw metadata. Global clicks and privacy-filtered Command/Control/Option shortcuts use macOS Input Monitoring; ordinary typing is rejected. Policy tests cover movement-only, left-click, short-right-click, long-right-hold, disabled, and empty paths |
| Pause/resume | Official changelog and recording guide expose pause/resume | Verified in the running app: the controller timer remained at 00:21 throughout a 3.5s pause, resume continued the timer, and 21.873584s + 21.613333s H.264/AAC segments produced a 43.485000s merged file with 48kHz stereo audio—the paused wall-clock gap is absent |

## Editing

| Requirement | Screen Studio evidence | ScreenFree state |
| --- | --- | --- |
| Split, trim, reset trim, remove, merge | Observed in clip timeline menu | Implemented and covered by model tests. Reset trim restores only the source range available between neighbors without overlap or setting loss. Merge accepts either neighbor only when source time, speed, and volume are compatible, then proves original duration/settings are restored; incompatible merges are rejected without mutation |
| Direct timeline editing | Screen Studio uses a persistent split tool, scissors markers, hover-oriented selection, and Escape to leave the active tool | Verified in the packaged app: split mode remained active after a point split, clips display a top scissors badge, and Escape returned to selection without resizing the window. Delete prioritizes the hovered clip/zoom/region before the previous inspector selection, including stale hover-exit ordering covered by store tests |
| Timeline detail zoom | Observed zoom slider, fit, and scrollable detailed timeline | Track-local −/slider/percentage/+/Fit controls, ⌘−/⌘+/⌘0, horizontal scrolling, and trackpad pinch are implemented. Fit remains 100%; 64× keeps an hour-long edit below 0.1 seconds per point on an 820 pt viewport. The packaged app was exercised from 100% to 152% and exposed horizontal scrolling |
| Full-screen preview | Observed preview full-screen action | Verified in the packaged app: the editor chrome is replaced by the composed video plus minimal time/play/exit controls, the window enters native macOS full screen, and Escape restores the workstation |
| Recording history | Previous captures can be reopened for another editing pass | The toolbar history browser scans `~/Movies/ScreenFree` for MP4/MOV captures, sorts newest first, shows date and size, refreshes, opens by click or context menu, and reveals in Finder. A real new recording appeared first and reopened in the editor; a normal relaunch still starts blank |
| Clip speed and volume | Observed 0.5×–24× and 0%–100% | Implemented; audio supports up to 200% for quiet recordings |
| Real waveform | Screen Studio exposes microphone/system audio waveforms | Implemented from decoded PCM samples; replaces the original decorative waveform and was exercised on a real system-audio recording |
| Audio analysis | Product requirement from user | Real RMS and peak analysis, silence/clipping state, and safe normalization implemented |
| Independent recorded-track mix | Screen Studio exposes system-audio and microphone controls, including microphone mute | ScreenFree records deterministic system/microphone track roles, provides independent 0–200% volume plus microphone mute, applies the same mix to preview and MP4 export, and persists roles/gains/mute through autosave and `.screenfree` recovery. A real two-track composition test proves the exact per-track gains, mute isolation, legacy migration, and consumer-ready MP4 mix |
| Background music | Observed as an editing workflow | Native audio-file import, replacement/removal, independent volume, timeline-synchronized looping preview, project persistence, and MP4 mixing are implemented. A real media test loops a 0.24s track across a 1s edit, verifies at least four composition segments and the exact 0.35 mix gain, then reopens the exported MP4 to confirm audio and duration |
| Automatic zooms | Clicks generate purple zoom ranges | Implemented and verified |
| Manual zoom focus | Official guide exposes a movable purple focus point | Implemented in video preview |
| Resizable zoom range | Official guide: drag either zoom edge | Verified in the running app: right edge changed 2.20s → 11.14s without moving the start; left edge then changed the start 0.00s → 3.24s and duration → 7.91s |
| Zoom motion | Observed Slow, Mellow, Quick, Rapid, and Customize presets | Slow, Mellow, Quick, Rapid, and Customize are implemented with shared eased progress for preview, cursor alignment, current-frame rendering, and video export. Customize exposes transition duration plus four true cubic-Bézier control coordinates; its x-axis is numerically inverted rather than treating time as the curve parameter. Resolver tests cover entry/hold/exit and exact custom curves, while real composition tests prove Rapid, Mellow, and a custom curve produce materially different frames |
| Motion blur | Observed global motion blur with separate cursor movement, screen zooming, and screen panning amounts | Implemented as an opt-in effect, disabled for new projects by default, with an overall switch/strength and three independent 0–100% amounts. A shared velocity resolver keeps static frames sharp, drives the live preview, and animates public Core Image Gaussian filters through the offline Core Animation composition. Current-frame and actual MP4 pixel tests independently prove screen-transition blur and cursor-motion blur; explicit settings persist in projects and portable style presets with legacy migration |
| Camera editing | Official guide supports size, layout, position, and mirroring | Independent camera movie, synchronized preview/export PIP, four positions, size, corner radius, and mirroring are implemented. A Core Image compositor applies the same true-alpha rounded mask to current-frame and MP4 output. Mirrored and non-mirrored media tests verify the camera center and all four transparent corners; a real FaceTime-camera export verifies mirrored rounded PIP pixels in the final MP4 |
| Background/canvas | Observed wallpaper categories/randomize plus gradient/color/image, blur, padding, radius, inset, and shadow | Source, 16:9, 9:16, 1:1, 4:3, and 3:4 canvases use centered aspect-fill crop. Aurora, Sunset, Ocean, Forest, Candy, and Graphite wallpapers share exact three-color/direction data between preview and MP4/GIF; randomize always chooses a different entry. Gradient/solid/image, image blur, padding, radius, and shadow remain editable. Media tests prove square center crop, wallpaper-versus-gradient output pixels, project migration, and preset round-trip |
| Frame stepping | Observed previous-frame and next-frame controls | Verified in the running app: next frame advanced 00:00.00 → 00:00.02 → 00:00.04 on the 60fps source and two previous-frame actions returned exactly to 00:00.00 |
| Cursor editing | Observed size, hide-idle, return-to-opening-position, stop-before-end, accessibility-shake removal with threshold, rapid-change optimization, smooth movement, always-use-pointer replacement, and click effects | Size, show/hide, arrow/link-pointer replacement with style-specific hotspots, hide-idle timeout, adjustable 0–5s stop-before-end, optional eased return to the opening position, non-destructive short-spike removal with adjustable threshold, rapid-change smoothing, optional frame-rate-independent interpolation of the recorded 30 fps path, plus None/Circle/Ripple/Rotation click effects are implemented consistently in preview, video, GIF, and current-frame output. The return uses the final 20% capped at one second and composes correctly with an earlier freeze. Bundled vector artwork avoids WindowServer-dependent missing images; model tests and current-frame/actual-MP4 pixel comparisons cover replacement, enabled versus stepped movement, preset/project persistence, and legacy migration without altering raw samples |
| Shortcut labels | Observed optional pressed-shortcut labels | Toggle, recorded-count display, removal, project persistence, preview, current-frame rendering, and MP4/GIF export are implemented. A privacy formatter test proves plain typing and Shift-only input are rejected; real MP4 pixel comparison proves the layer is rendered |
| Timed privacy redaction | ScreenFree product differentiator for customer-data workflows | A dedicated red Privacy track supports selecting, moving, and resizing both time edges; the preview supports direct box dragging, while the inspector controls width, height, opacity, duration, and deletion. Redactions persist with backward-compatible migration, clamp after timeline edits, and render consistently in preview, current-frame, MP4, and GIF. Model and real MP4 pixel tests prove range constraints and active/inactive rendering |
| Timed spotlight highlight | Visual emphasis required for polished walkthroughs | A Spotlight region shares the production-tested timed-region track: preview dragging, two-edge move/resize, width, height, dim intensity, hue, duration, deletion, persistence, and timeline clamping. Preview/current-frame/MP4/GIF use an even-odd focus hole so the selected area stays undimmed while the exterior darkens. Current-frame and reopened-MP4 pixel tests prove both the preserved center and timed exterior dimming |
| Captions | Official guide uses local Whisper or Apple Speech plus custom vocabulary/prompt | On-device Apple Speech generation, language selection, cue editing/removal, preview, persistence, and export rendering are implemented. A project-private vocabulary/context field accepts comma/newline-separated specialist phrases, normalizes and deduplicates up to 100 entries, and supplies them through the actual on-device recognition request. Request configuration and backward-compatible project migration are tested; permission/device transcription validation remains open |
| Project recovery | Screen Studio automatically saves and attempts recovery | Versioned `.screenfree` snapshots remain available for crash recovery and explicit project opening. A normal launch deliberately starts with no loaded video, as required; prior source videos remain discoverable through Recording History instead of silently restoring stale editor state |
| Style presets | File menu exposes preset import | Clean, Vibrant, and Minimal built-ins plus versioned `.screenfreepreset` import/export are implemented. A preset captures canvas/aspect/background/wallpaper, padding, radius, shadow, cursor visibility/end behavior/effects, shortcut and caption styling, zoom defaults/preset/custom Bézier, and camera layout. Tests prove full round-trip/application, backward-compatible wallpaper/cursor/custom-motion migration, reject future versions, and safely replace a missing image background with a gradient |

## Export

| Requirement | Screen Studio evidence | ScreenFree state |
| --- | --- | --- |
| MP4 | Observed H.264 export settings | Verified through the UI: 46.73s, 1512×982 H.264 with 48kHz stereo AAC; extracted frames show canvas and mouse zoom |
| GIF | Observed GIF export and loop settings | Verified by a media-pipeline test using real generated H.264 input; looping GIF reopens with multiple frames |
| Frame rate | Observed selectable FPS | 24/25/30/50/60 fps implemented and option-tested |
| Resolution/quality | Observed source dimensions, 720p, 1080p, 4K, explicit pixel dimensions, and compression profiles | Source/720p/1080p/4K map to native AVFoundation presets; Custom accepts exact even 320–7680 px width/height, center-crops rather than stretching, and deliberately uses Studio quality so a lower preset cannot silently resize the encoded track. Studio/Social/Compact profiles remain available for standard resolutions. Range/even-value and crop tests run alongside an actual exported MP4 reopened at exactly 642×358 |
| Progress/cancellation | Observed estimated export time and active export state | MP4 polls the real AVFoundation session progress; GIF reports completed frames. Both can be cancelled from the inspector and remove incomplete output; cancellation cleanup is media-tested |
| File/clipboard destinations | Observed file and clipboard export destinations | Full MP4/GIF exports can be saved to a chosen file or copied as a persistent cache-backed macOS file URL; pasteboard handoff is tested and old clipboard exports are pruned after seven days |
| Original media extraction | Observed original screen, camera, microphone, and system-audio exports | The export inspector saves original screen and camera movies without transcoding, and uses persisted deterministic track roles to extract system audio or microphone as a single M4A without ever substituting another track. Delivery copies through a same-directory temporary file before atomic replacement. A real two-track media test selects the second track, verifies exact 0.5s duration/one-track output, rejects an unavailable index, and covers replacement plus same-source preservation |
| Camera/cursor/zooms in output | Editable layers must survive export | Screen, canvas, cursor, clicks, and zooms are verified in extracted output frames. Synthetic camera media is independently composed and verified in an actual MP4, including mirrored alpha-rounded corners. A real 19.83s hardware export from the recorded 1512×982 screen source and 1920×1080 FaceTime-camera source was reopened as H.264 + 48 kHz AAC, and an extracted frame verifies the rounded mirrored PIP in the encoded output |
| Current frame | Observed current-frame image export | Copy-to-clipboard and PNG save actions render the current timeline frame through the full video composition; square dimensions plus the playhead cursor, active caption, and click effect are pixel-tested, with final clipboard/UI validation pending unlock |

## Localization and product quality

- English, Simplified Chinese, and follow-system language modes are persisted.
- Language changes update the active editor without restarting, including
  dynamic status filenames, clip/zoom counts, device default labels, and known
  error messages.
- A native Settings scene exposes language and permission readiness.
- `Studio Check` is a ScreenFree-specific preflight feature that checks screen
  access, Input Monitoring, disk capacity, camera discovery/authorization, and
  microphone authorization/live signal before a recording.
- `swift test` currently runs 67 checks, including timeline/recovery model tests plus
  media/device tests that create H.264 + 48 kHz stereo AAC input, join two
  pause/resume segments without dropping audio, prove square center-crop
  rendering, export MP4 and GIF, validate legacy project compatibility, and
  reject camera recording when its preview is not ready, keep cropped-out
  cursor/click metadata outside the rendered canvas, and preserve aligned
  selected-application audio as a second editable source track, validate its
  independent system/microphone gain and mute mapping plus final MP4 mix,
  validate export progress
  completion, cancellation cleanup, full-video pasteboard handoff, and dynamic
  localization plus original-recording file delivery, deterministic second-role
  M4A extraction, invalid-role rejection, and atomic replacement, validate click-effect
  and privacy-safe shortcut migration,
  current-frame pixels, real shortcut-layer MP4 pixels, and multi-display
  recording-border geometry, Dock-policy restoration, and speaker-note
  visibility/multi-display placement plus desktop-icon exact-state restoration,
  validate lossless adjacent-clip merge and
  eased
  zoom entry/hold/exit, compare Rapid versus Mellow frames through the real
  renderer, verify neighbor-safe trim reset, and verify every advertised
  resolution/frame-rate option, custom dimension constraints and an exact
  642×358 encoded MP4, and prove timeline fit/zoom plus time-to-point
  and zoom-range drag mapping at non-default magnification, verify custom
  cubic-Bézier solving/persistence/rendering, plus verify a true
  alpha-rounded camera PIP in both current-frame and actual MP4 output, and
  prove velocity-driven screen and cursor motion blur in current-frame and
  actual MP4 pixels while keeping disabled/static paths sharp, and
  verify cursor tail-freeze, eased return-to-start, spike removal,
  rapid-change optimization, optional sample interpolation, and arrow/pointer
  replacement, including current-frame and actual MP4 pixel comparisons plus
  bundled cursor artwork, background-music looping,
  independent mix gain, project migration, and real MP4 audio survival, plus
  privacy-range clamping and active/inactive current-frame and MP4 pixels, plus
  spotlight center preservation and timed exterior dimming in current-frame
  and reopened MP4 pixels, plus
  sanitized/deduplicated caption context in the actual on-device speech
  request, plus bit-identical bypass and signal-level noise/gain/limiter proof
  through a real interleaved microphone PCM sample buffer.
  The preset test also verifies versioning, complete style application,
  wallpaper/cursor-replacement/cursor-return/path-cleanup/
  cursor-interpolation/custom-motion migration, and
  missing-image fallback.
- Build/run is owned by `script/build_and_run.sh`; the distributed app is
  assembled with localized resources and a stable designated requirement.
