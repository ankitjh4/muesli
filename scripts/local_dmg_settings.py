"""Deterministic Finder layout for dmgbuild (no Automation permission needed)."""
import os

app_path = defines['app_path']
format = 'UDZO'
files = [app_path]
symlinks = {'Applications': '/Applications'}
background = defines['background']
window_rect = ((100, 100), (1080, 760))
icon_size = 152
text_size = 14
icon_locations = {os.path.basename(app_path): (260, 305), 'Applications': (820, 305)}
show_toolbar = False
show_status_bar = False
show_sidebar = False
default_view = 'icon-view'
include_icon_view_settings = True
include_list_view_settings = False
