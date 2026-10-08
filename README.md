# ClipNest

A native macOS clipboard manager for text, code, links, and images. Hover at the center of the top edge of your screen or use a global shortcut to open a compact notch-style panel.

Built with Swift, SwiftUI, and AppKit. No external dependencies, backend, telemetry, or OCR.

## Features

- Clipboard history with exact text, whitespace, Unicode, and original image representations.
- Search text, image notes, item types, and source app names.
- Best-effort source app names and icons with relative copy times.
- Pin useful items, edit image notes, and copy formatted JSON.
- Green copy confirmation before the panel closes.
- Dedicated empty states for new history, paused recording, and searches with no results.
- Frosted panel, light/dark/system appearance, rounded cards, hover actions, and transparent image previews.
- Smooth motion that respects Reduce Motion and Reduce Transparency.
- Personal settings for launch at login, global shortcuts, hover timing, history count, and storage limits.
- Local storage with recovery handling and filtering for concealed, transient, and app-generated clipboard content.

## Download

Get the app from [GitHub Releases](https://github.com/ekosiswoyo/clipnest/releases).

The v0.2.0 binary is for **Apple Silicon (arm64)** and targets **macOS 13 or later**. Extract the ZIP and move `ClipNest.app` to Applications. This development release is ad-hoc signed and is not notarized; macOS may require approving it in Privacy & Security before the first launch. Intel binaries are not included.

## Usage

Copy text or an image in another app, then hover at the center of the screen’s top edge. Click a text card to paste it at the cursor in the previously active app. On the first attempt, macOS asks for Accessibility access; enable ClipNest in System Settings → Privacy & Security → Accessibility, then click the card again. Focus your destination text field before opening history. Image cards and explicit Copy actions copy to the clipboard for manual **Command + V**.

The default global shortcut is **Control + Option + Space**. It opens the panel with keyboard focus; hover opening does not take focus. Use Up/Down to select, Return to paste text (copy images), Command + Return to copy, and Escape to close. Click the search field to search. Copy, Pin, and Delete appear on hover or selection, and right-click offers additional actions.

The menu bar provides history, pause/resume, Settings, cleanup, and Quit. Warning states appear in its icon and tooltip.

For valid JSON, hover over or select its card and click the **{}** button (**Copy formatted JSON**), or use the right-click menu. This copies indented JSON with sorted keys while keeping the original history text. Objects, arrays, and standalone JSON values are supported; invalid JSON has no formatting action.

The footer has buttons to paste/copy the selected item and close history, with shortcut hints and the destination app name. Hover over a card or use Up/Down to select it. Drag the grip at the top of a card's action column into an app that accepts text or images. Dragging keeps the original history item and does not change the system clipboard. The panel stays open during dragging, closes after an accepted drop, and remains open when the drag is cancelled.

## Settings

Settings save automatically:

- **Launch at login:** managed by macOS, available when running the app bundle. If approval is required, Settings links to Login Items.
- **Appearance:** System, Dark, Light, or Black. Black uses a solid pure black history background without transparency.
- **Display:** compact cards, text size from 11–16 pt, and background opacity from 30–100%. Black stays fully opaque.

History shows pinned items first, with All, Text, Images, and Pinned filters that work together with search. Cards show Copy and Pin on hover or selection; the more menu contains Delete and formatted JSON copying. The footer names the paste destination and keeps paste feedback visible even when new clipboard entries arrive.
- **Hover:** enable or disable opening; set open and close delays.
- **Shortcut:** choose a modifier combination and Space, C, V, H, J, or K. Registration conflicts are reported.
- **History:** 50, 100, 250, or 500 unpinned items; 100, 200, 500, or 1024 MiB storage.

Lowering limits removes oldest unpinned items. Pins are preserved; new items cannot be saved if pins fill storage. Individual items are limited to 1 MiB for text and 20 MiB / 40 MP for images.

## Storage and privacy

History, images, and preferences are stored in `~/Library/Application Support/ClipNest/`. Nothing is uploaded. Source app attribution is inferred from the foreground app at capture time and can be inaccurate when switching apps quickly. Older items without source metadata display “Unknown app.”

Clipboard filtering is best-effort. Apps that do not mark sensitive clipboard content can still have that content recorded. Pause recording from the menu bar when needed.

Corrupt history metadata stops recording while preserving image files. Restore a backup or use Delete All to start fresh.

## Build

Requires a macOS Swift toolchain with Command Line Tools and Swift 5.9 or later.

```sh
./scripts/build-app.sh
open build/ClipNest.app
```

`VERSION` controls the app’s version. The build script creates and ad-hoc signs `build/ClipNest.app`.

Create a release ZIP and checksum:

```sh
./scripts/package-release.sh
```

The ZIP architecture follows the build machine. The published v0.2.0 build was produced on arm64.

## Verification

```sh
swift build -c release
.build/release/ClipNestChecks
CLIPNEST_DATA_DIR="$(mktemp -d)" build/ClipNest.app/Contents/MacOS/ClipNest --smoke-test
CLIPNEST_DATA_DIR="$(mktemp -d)" build/ClipNest.app/Contents/MacOS/ClipNest --panel-check
```

Core checks cover text fidelity, deduplication, persistence, source metadata compatibility, history limits, pinning, image lifecycle, recovery, and clipboard filtering. The GUI smoke test temporarily exercises and restores the clipboard, and covers hover, focus, copy feedback, and preference persistence. Use isolated data directories for GUI checks.

This release was tested on Apple Silicon running macOS 27.0.1. macOS 13, Intel, and launch-at-login across a full login cycle have not been directly tested.
