"""Build a Finder layout with a macOS-native, verified background bookmark."""
import base64
import os
import subprocess
import sys

from dmgbuild import build_dmg
from ds_store import DSStore

settings_file, app_path, background, volume_name, output = sys.argv[1:]
mount = None


class NativeBookmark:
    def __init__(self, data):
        self.data = data

    def to_bytes(self):
        return self.data


def remember_mount(mount_point, options):
    global mount
    mount = mount_point


def on_progress(event):
    if event.get('type') != 'operation::finished' or event.get('operation') != 'dsstore::create':
        return
    image = os.path.join(mount, '.background.png')
    helper = os.path.join(os.path.dirname(__file__), 'create_background_bookmark.swift')
    result = subprocess.check_output(['/usr/bin/swift', helper, image], text=True)
    bookmark = base64.b64decode(result.strip(), validate=True)
    with DSStore.open(os.path.join(mount, '.DS_Store'), 'r+') as store:
        store['.']['pBBk'] = NativeBookmark(bookmark)


build_dmg(output, volume_name, settings_file=settings_file,
          settings={'create_hook': remember_mount},
          defines={'app_path': app_path, 'background': background},
          lookForHiDPI=False, callback=on_progress)
