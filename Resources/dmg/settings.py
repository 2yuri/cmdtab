# dmgbuild layout for the cmdtab disk image. Positions match "DMG / Background" in the design file:
# a 660×400 window, the app on the left and the Applications shortcut on the right, 96 pt icons.
import os.path

app = defines["app"]  # noqa: F821  (dmgbuild injects `defines`)
app_name = os.path.basename(app)
here = os.path.dirname(os.path.abspath(defines["settings_dir"] + "/x"))  # noqa: F821

format = "UDZO"
filesystem = "HFS+"
files = [app]
icon = os.path.join(app, "Contents/Resources/AppIcon.icns")
symlinks = {"Applications": "/Applications"}
hide_extensions = [app_name]

# dmgbuild turns background.png + background@2x.png into a Retina background.
background = os.path.join(here, "background.png")
window_rect = ((200, 120), (660, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 96
text_size = 12
icon_locations = {
    app_name: (176, 216),
    "Applications": (484, 216),
    # Hidden files, placed below the window for anyone who shows hidden files in Finder.
    ".background.tiff": (176, 640),
    ".VolumeIcon.icns": (484, 640),
}
