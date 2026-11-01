# Security policy

cmdtab runs with the Accessibility permission (and Screen Recording, if window previews are on), so
security reports are taken seriously.

## Reporting a vulnerability

Please **do not open a public issue**. Report it privately through
[GitHub's private vulnerability reporting](https://github.com/2yuri/cmdtab/security/advisories/new).

Include what you found, how to reproduce it, and the macOS and cmdtab versions. You'll get an answer
within a few days; once fixed, the advisory is published with credit unless you prefer otherwise.

## Supported versions

Only the latest release receives fixes.

## Scope

cmdtab makes no network connections and stores only its settings (in `UserDefaults`). Window
snapshots for previews are kept in memory while the switcher is open and are never written to disk.
