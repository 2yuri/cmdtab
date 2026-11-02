#!/bin/sh
# Packs a built CmdTab.app into a drag-to-Applications disk image with the branded background.
#
#   scripts/make-dmg.sh path/to/CmdTab.app build/CmdTab-v1.2.3.dmg
#
# Needs dmgbuild (installed into build/dmg-venv on first run). Signing and notarizing the DMG is
# done by the caller.
set -eu
cd "$(dirname "$0")/.."

APP="${1:?usage: make-dmg.sh <CmdTab.app> <output.dmg>}"
OUT="${2:?usage: make-dmg.sh <CmdTab.app> <output.dmg>}"

if [ ! -x build/dmg-venv/bin/dmgbuild ]; then
  python3 -m venv build/dmg-venv
  build/dmg-venv/bin/pip install --quiet "dmgbuild==1.6.1"
fi

rm -f "$OUT"
# dmgbuild also stores the background as a bookmark (pBBk) next to the alias. Finder on recent macOS
# prefers the bookmark, can't resolve it on the mounted image and shows no background, so leave it out
# and keep only the alias, like other drag-to-install images do.
build/dmg-venv/bin/python -I - "$APP" "$PWD/Resources/dmg" "$OUT" <<'PY'
import sys
import dmgbuild.core as core

class _NoBookmark:
    @staticmethod
    def for_file(path):
        return None

core.Bookmark = _NoBookmark
app, settings_dir, out = sys.argv[1:]
core.build_dmg(out, "cmdtab", settings_file=settings_dir + "/settings.py",
               defines={"app": app, "settings_dir": settings_dir})
PY
echo "Built $OUT"
