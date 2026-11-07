"""Finder layout for dmgbuild; no Finder or GUI session needed during release builds."""

import os
import plistlib

application = os.path.abspath(defines["app"])
files = [application]
symlinks = {"Applications": "/Applications"}
background = os.path.abspath(defines["background"])
format = "UDZO"
filesystem = "HFS+"

with open(os.path.join(application, "Contents", "Info.plist"), "rb") as file:
    app_info = plistlib.load(file)
icon_name = app_info.get("CFBundleIconFile", "AppIcon.icns")
if not icon_name.endswith(".icns"):
    icon_name += ".icns"
icon = os.path.join(application, "Contents", "Resources", icon_name)

# The frame includes the 32-point Finder title bar above the 640 × 400 artwork.
window_rect = ((200, 160), (640, 432))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True
include_list_view_settings = False
arrange_by = None
icon_size = 112
text_size = 14
label_pos = "bottom"
icon_locations = {"loge.app": (176, 210), "Applications": (464, 210)}
