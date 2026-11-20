# dmgbuild settings for the AirBuds DMG window. scripts/make-dmg.sh passes
# app=, background= and icon= with -D. The window size and icon positions match
# the art drawn by scripts/dmg-background.swift.

app = defines["app"]  # noqa: F821 (provided by dmgbuild)

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = defines["icon"]  # noqa: F821
background = defines["background"]  # noqa: F821

window_rect = ((200, 120), (640, 400))
icon_size = 112
text_size = 13
icon_locations = {
    "AirBuds.app": (170, 200),
    "Applications": (470, 200),
}
hide_extensions = ["AirBuds.app"]
