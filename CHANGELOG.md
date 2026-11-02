# Changelog

All notable changes to cmdtab are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.2.1] - 2026-11-02

### Fixed
- ⌘⇥ in a full-screen app now lists the desktop you came from, and full-screen apps show up from
  the desktop. Choosing a window on another Space switches to it.

## [1.2.0] - 2026-11-02

### Added
- Tiling (beta), off by default: Scroll Lock strip, column widths and stack heights, sizes remembered
  per app, stacking by dragging, Arrange mode (⌃⌥A), floating apps, screen padding, gap and dimming.
- Automatic updates: one check a day against the latest GitHub release, signed with EdDSA. Settings →
  About turns it off or checks now.
- Every release also ships `CmdTab.dmg`, so `releases/latest/download/CmdTab.dmg` is always the newest.

## [1.0.0] - 2026-11-01

### Added
- ⌘⇥ / ⌘⇧⇥ window switcher that lists only the windows on the current desktop (or all desktops).
- Three styles: icons, window previews and a list of titles; small, medium and large sizes.
- Search with ⌘F, or "Open in search mode" so the search bar is always there.
- Optional grouping of windows by app, with a window count.
- Preview of the selected window in place on screen.
- ⌘W / ⌘M / ⌘Q to close, minimize or quit without switching.
- Exceptions: hide apps, or leave ⌘⇥ to an app while it is in front.
- Desktop number on windows from other desktops when showing all desktops.
- Settings window, menu bar menu and first-launch permission guide.
- Light and dark themes, Reduce Transparency and VoiceOver labels.

[Unreleased]: https://github.com/2yuri/cmdtab/compare/v1.2.1...HEAD
[1.2.1]: https://github.com/2yuri/cmdtab/releases/tag/v1.2.1
[1.2.0]: https://github.com/2yuri/cmdtab/releases/tag/v1.2.0
[1.0.0]: https://github.com/2yuri/cmdtab/releases/tag/v1.0.0
