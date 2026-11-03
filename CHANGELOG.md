# Changelog

All notable changes to cmdtab are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.3.0] - 2026-11-03

### Added
- The CmdTab Island, off by default: a live strip in the notch (a pill on Macs without one) that stays
  the notch's size until something happens. Every module starts off and runs nothing until it's on.
  - Overview: what's playing, CPU and memory (read only while it's open), battery, your agents' limits
    and what's next.
  - Agents: Claude Code and Codex sessions, their limits, and Allow / Deny right in the island.
  - Music from any app, the Shelf for files (and new downloads and screenshots), this desktop's windows,
    Calendar (week, month, year, new events), meetings with Join, a Pomodoro, world clocks, weather a
    week ahead, and moments for headphones, the charger and a low battery.
  - Closed, it shows several things at once: the song and the Pomodoro on the left, the agents on the
    right.
  - Drag a window up to the notch to put it on a half, fill or centre it, or, with Tiling on, move or
    stack it among your columns.
- Tiling: tabs (⌃⌥T, or T in Arrange mode): one window at a time in a column, full height, the others
  peeking out behind; ⌃⌥↑ ↓ switches. The strip map shows tabs and stacks.

### Changed
- ⌘⇥ keeps working while you drag a file.

### Fixed
- Tiling: dialogs (database apps' connection windows, say) float instead of becoming columns; columns
  no longer renumber themselves; closing a window goes back to the one you were on; an app swapping
  one window for another keeps its place.
- If CmdTab ever crashes, the macOS ⌘⇥ comes back instead of staying off.

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

[Unreleased]: https://github.com/2yuri/cmdtab/compare/v1.3.0...HEAD
[1.3.0]: https://github.com/2yuri/cmdtab/releases/tag/v1.3.0
[1.2.1]: https://github.com/2yuri/cmdtab/releases/tag/v1.2.1
[1.2.0]: https://github.com/2yuri/cmdtab/releases/tag/v1.2.0
[1.0.0]: https://github.com/2yuri/cmdtab/releases/tag/v1.0.0
