# Changelog

## 0.3.0

- Full preview for selectable text, JSON, and original images in a resizable window.
- JSON formatting toggle, image zoom, and Fit controls in preview.
- Preview from item menus, the footer eye button, or Space outside the search field.
- Explicit Paste as Plain Text from item menus, footer paste options, preview, or Option + Return. Uses the original text without RTF or HTML formatting.
- Preview remains open outside the hover trigger and returns keyboard focus to history when closed.

Validation: release build, GUI regression checks for full Unicode text, preview focus/lifecycle, plain text payload, filters, and settings; visual inspection of text, JSON, and image previews. Apple Silicon, macOS 13 or later; ad-hoc signed and not notarized.

## 0.2.0

- Compact cards, streamlined Copy/Pin actions, a more-actions menu, and a lighter footer.
- Pinned items appear above history; All, Text, Images, and Pinned filters combine with search.
- Solid Black theme with clearer card borders, adjustable text size, card density, and background opacity.
- Click-to-paste text to the previously active app with persistent destination and failure feedback.
- Drag text or images into other apps without changing the clipboard.
- Fixed search focus and first-click button handling in hover-opened panels.
- Formatted JSON copying supports objects, arrays, and scalar values while preserving the original history item.
- Custom app icon and backward-compatible display preferences.

Validation: release build, core checks, GUI smoke checks, and rendered panel/settings inspection on Apple Silicon running macOS 27.0.1. The binary targets macOS 13 or later; Intel is not included. The app is ad-hoc signed and not notarized.

## 0.1.0

Initial release of ClipNest for macOS.

- Native notch-style clipboard panel with hover and global shortcut access.
- Text and image history, search, pins, image notes, and formatted JSON copying.
- Source app context, relative timestamps, and copy confirmation.
- Helpful empty states and persistent personal settings.
- Frosted surfaces, light and dark themes, hover actions, refined typography, checkerboard image previews, and accessible motion.
- Local storage with recovery support and clipboard privacy filtering.

The release binary targets macOS 13 or later on Apple Silicon. It is ad-hoc signed and not notarized.
