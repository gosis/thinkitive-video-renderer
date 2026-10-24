# Outline

Outline is an iOS video editor built around one effect: **text that draws itself on top of your footage, stroke by stroke, like a pen writing it**. Choose a *single-line* font and each letter is drawn as one pen line, like the handwriting animations in pro editing apps. Choose an *outline* font and the border of each letter is traced, then filled in solid. You place it on the video, set when it draws and how long it stays, and export a finished video to Photos.

Built with SwiftUI, AVFoundation and Core Text. No third-party dependencies.

## What you can do

| | |
|---|---|
| **Bring in footage** | Pick a video from Photos, browse Files, or generate a built-in sample clip to try the effect without footage. |
| **Add text** | Add as many text overlays as you like. Duplicate or delete the selected one. Text can have several lines. |
| **Place it** | Drag text directly on the video preview. Tap to select it. |
| **Style it** | 6 single-line fonts (Script, Cursive, Relief, Sans, Serif, Gothic) where every letter is one pen line, plus 12 system fonts whose outlines trace well. Set the size, line width and colour; outline fonts also get an optional fill. |
| **Choose how it draws** | *One by one*: glyphs are traced in reading order, like handwriting. *All at once*: every glyph is traced at the same time. |
| **Time it** | Set the start time and draw duration, hold until the end or fade out at a chosen time, and pick an easing curve (Linear, Smooth, Ease out). |
| **Preview** | Play, or drag anywhere on the timeline to scrub. Each text has its own lane, and the solid part of a lane shows the drawing phase. On iPhone, swipe down to close the keyboard. |
| **Export** | Renders at the video's full resolution and saves to Photos, with a progress readout. |

## How the effect works

1. **Glyph paths.** `GlyphOutline` turns the text into one `CGPath` per letter, built once at a 100 pt reference size, centred on the origin with y pointing down, and cached.
   - **Outline fonts:** laid out with Core Text; each path is the letter's border (`CTFontCreatePathForGlyph`).
   - **Single-line fonts:** `StrokeFont` reads a bundled SVG font in which each letter is stored as the centre line a pen would follow. Tracing it draws the letter with a single line. They're scaled so their capitals match regular fonts at the same size.
2. **Relative geometry.** A `TextOverlay` stores its position as unit coordinates, its size as a fraction of the video height, and its outline width as a fraction of the font size. `OutlineGeometry` turns these into one affine transform for any target size, so a 390 pt preview and a 2160 px export lay out identically.
3. **Timing.** `OutlineTiming` maps a time to *stroke progress* (eased with a cubic Bézier), *fill opacity* (fades in once tracing finishes) and *overall opacity* (fades out after the end time).
4. **One renderer for both preview and export.** `OutlineRenderer` draws an overlay's state at a given time into a `CGContext`. It fills the glyphs (outline fonts only), then strokes each path trimmed to the current progress. The trimming is by path length, which is what creates the "drawing" look.
   - **Preview:** a SwiftUI `Canvas` over an `AVPlayerLayer` calls the renderer through `withCGContext` on every player tick.
   - **Export:** `VideoExporter` builds an `AVMutableVideoComposition` with a Core Image handler. For every frame it draws the visible overlays into a transparent bitmap and composites that over the source frame. Source frames already have the track's orientation applied, so portrait footage stays upright.

   Because both paths call the same code, the export matches the preview.

## Project layout

```
OutlineStudio.xcodeproj         Xcode project (folders are synced, so new files are picked up automatically)
OutlineStudio/
  App/OutlineStudioApp.swift    Entry point, appearance preference
  Theme/Theme.swift             Colour tokens (light + dark), radii, appearance setting
  Model/
    TextOverlay.swift           The overlay: text, font, style, position, timing
    OutlineFont.swift           Font list: single-line and outline
  Engine/
    GlyphOutline.swift          Text → per-glyph CGPaths (cached)
    StrokeFont.swift            SVG single-line font + SVG path parser
    OutlineGeometry.swift       Relative → absolute layout transform
    OutlineTiming.swift         Easing curves, stroke/fill/opacity over time
    OutlineRenderer.swift       Shared Core Graphics renderer
    VideoExporter.swift         Frame-by-frame export + save to Photos
    SampleClip.swift            Generates the built-in sample video
  Editor/
    EditorModel.swift           @Observable state: player, overlays, selection, export
    EditorView.swift            Screen layout (phone: stacked, iPad: side inspector), import
    PreviewCanvas.swift         Video + live overlays + drag/select handles
    TimelineStrip.swift         Ruler/scrubber, playhead, one lane per text
    InspectorPanel.swift        Text / Style / Timing tabs
    EmptyStateView.swift        First screen with a looping demo of the effect
    ExportStatusView.swift      Rendering progress / result card
  Components/                   PlayerLayerView, LabeledSlider, IconButton, timecode, keyboard helper
  Fonts/                        Bundled single-line SVG fonts and LICENSES.md
OutlineStudioUITests/           UI tests: timeline scrubbing, keyboard dismissal
```

## Design

The palette follows the colour roles of pro editing tools. Graphite neutrals keep the footage in focus, and each accent has one job:

| Token | Light | Dark | Role |
|---|---|---|---|
| `background` | `#F4F5F7` | `#111318` | App background |
| `surface` / `surfaceRaised` | `#FFFFFF` / `#ECEEF2` | `#1A1D23` / `#252932` | Panels, controls |
| `canvas` | `#DCDFE5` | `#08090B` | Letterbox behind the video |
| `accent` | `#E0482B` | `#FF6A4D` | Actions, selection (coral) |
| `clip` | `#0F8FB0` | `#3CC6E6` | Text clips on the timeline (cyan) |
| `playhead` | `#E8A400` | `#FFCE3D` | Playhead (amber) |

The app follows the system appearance by default. The half-circle button in the top bar switches it to System, Light or Dark.

## Requirements

- iOS / iPadOS 18+
- Xcode 26+

Open `OutlineStudio.xcodeproj`, choose your development team under *Signing & Capabilities*, and run. In the Simulator, use **Sample clip** to try the editor without footage.

Run the UI tests with ⌘U. The launch argument `-useSampleClip` opens the editor straight on the sample clip. The keyboard test needs the Simulator's software keyboard (*I/O → Keyboard → uncheck Connect Hardware Keyboard*).

## Fonts

The single-line fonts are the Hershey fonts (Dr. A. V. Hershey, U.S. National Bureau of Standards; free to use with attribution) plus Relief SingleLine and a cursive script, both under the SIL Open Font License. Full notices are in `OutlineStudio/Fonts/LICENSES.md`.

## History

This started as `thinkitive-video-renderer` (2023), a CocoaPods library with a UIKit/storyboard demo app. It overlaid any `UIView` on a video by snapshotting views on the main thread for every frame, and the demo used a Lottie animation. Version 2 rewrites the app in SwiftUI and keeps only the text-overlay feature. The Lottie, CocoaPods and still-image-to-video code was removed.
