# Contributing to cmdtab

Thanks for helping! cmdtab is deliberately small, so before writing code for a new feature, please
open an issue to talk about it.

## What fits

- Fixes, performance and battery improvements, accessibility, macOS compatibility.
- Small features that do nothing until ⌘⇥ is pressed.

What doesn't: anything that needs always-on background work (polling, timers, observers that run while
the switcher is closed, continuous screen capture), telemetry, or network access.

## Setup

```sh
brew install xcodegen
make project   # generates CmdTab.xcodeproj from project.yml (the .xcodeproj is not committed)
make test      # unit tests
make install   # signed Release build into /Applications
```

`project.yml` signs with the maintainer's team. Use your own with
`make install DEVELOPMENT_TEAM=YOURTEAMID`, or check tests without signing with `make ci`.

Accessibility permission is tied to the app's signature: if you switch teams, remove cmdtab from
System Settings → Privacy & Security → Accessibility and grant it again.

Running a second copy of cmdtab next to an installed one hands ⌘⇥ back and forth, so Debug builds have
a preview mode that opens one screen without touching ⌘⇥:

```sh
B=build/Build/Products/Debug/CmdTab.app/Contents/MacOS/CmdTab
CMDTAB_PREVIEW=settings:dark:privacy $B
CMDTAB_PREVIEW=onboarding:light $B
# The switcher with your windows. Options: CMDTAB_PREVIEW_STYLE=icons|previews|titles,
# CMDTAB_PREVIEW_GROUPED=1, CMDTAB_PREVIEW_SELECTED=1, CMDTAB_PREVIEW_SEARCH=<query>,
# CMDTAB_PREVIEW_SEARCH_MODE=1, CMDTAB_PREVIEW_ALL_SPACES=1
CMDTAB_PREVIEW=switcher:dark:medium $B
```

## Code

- Swift 6 with complete strict concurrency; the build must have **no warnings**.
- English everywhere: code, comments, UI text, commits.
- Keep logic that can be pure (ordering, filtering, grouping, geometry) out of AppKit types and cover
  it with unit tests in `Tests/CmdTabTests`.
- Comments explain *why*, not *what*.
- Private macOS APIs live only in `Sources/CmdTab/System/PrivateAPI.swift`, resolved with `dlsym`.
- UI follows the design: dark-first, Volt (`#B6F23A`) only for selection and brand moments. For
  visual changes, attach a screenshot or mockup to the issue first.

## Pull requests

- One topic per PR, with a short description of what and why.
- `make test` passes and the build has no new warnings.
- Mention how you tested it manually (macOS version, single or multiple displays).

By contributing you agree that your work is licensed under the [GPL-3.0](LICENSE).
Please follow the [Code of Conduct](CODE_OF_CONDUCT.md).
