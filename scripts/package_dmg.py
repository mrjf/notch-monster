#!/usr/bin/env python3
"""Create the drag-to-Applications installer and verify its mounted contents.

Install scripts/dmg-requirements.txt in a virtualenv, then run with its Python.
The app must already be built and signed by scripts/package_app.sh.
"""
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

import dmgbuild
from ds_store import DSStore

root = Path(__file__).resolve().parents[1]
source = root / "dist/Notch Monster.app"
info = plistlib.loads((source / "Contents/Info.plist").read_bytes())
version = info["CFBundleShortVersionString"]
destination = root / "website/dist/assets" / f"Notch-Monster-{version}.dmg"
volume_name = "Notch Monster"
signature = subprocess.run(["codesign", "-dv", "--verbose=4", str(source)],
                           capture_output=True, text=True, check=True).stderr
developer_id = "Authority=Developer ID Application:" in signature
notarized = developer_id and subprocess.run(["xcrun", "stapler", "validate", str(source)],
                                           capture_output=True).returncode == 0
if developer_id and not notarized:
    raise SystemExit("Developer ID releases require a stapled notarization ticket.")

with tempfile.TemporaryDirectory(prefix="notch-monster-installer-") as directory:
    stage = Path(directory)
    app = stage / source.name
    shutil.copytree(source, app, symlinks=True)
    subprocess.run(["xattr", "-cr", str(app)], check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    artwork = stage / "artwork"
    render = ["swift", str(root / "scripts/dmg_background.swift"), str(artwork)]
    if notarized:
        render.append("--notarized")
    subprocess.run(render, check=True)

    image = stage / destination.name
    dmgbuild.build_dmg(str(image), volume_name, settings={
        "format": "UDZO", "filesystem": "HFS+", "size": "64M",
        "files": [str(app)], "symlinks": {"Applications": "/Applications"},
        "icon": str(app / "Contents/Resources/AppIcon.icns"),
        "background": str(artwork / "installer.png"),
        "window_rect": ((180, 160), (840, 700)),
        "icon_locations": {source.name: (230, 205), "Applications": (610, 205)},
        "icon_size": 128, "text_size": 13,
        "grid_spacing": 80, "label_pos": "bottom", "arrange_by": None,
        "default_view": "icon-view", "include_icon_view_settings": True,
        "include_list_view_settings": False, "show_icon_preview": False,
        "show_toolbar": False, "show_sidebar": False, "show_status_bar": False,
        "show_pathbar": False, "show_tab_view": False,
    })
    subprocess.run(["hdiutil", "verify", str(image)], check=True)
    mount_info = plistlib.loads(subprocess.check_output([
        "hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen", "-plist", str(image)]))
    mounted = next(Path(item["mount-point"]) for item in mount_info["system-entities"] if "mount-point" in item)
    try:
        assert (mounted / "Applications").is_symlink()
        assert (mounted / "Applications").readlink() == Path("/Applications")
        assert (mounted / ".background.tiff").is_file()
        with DSStore.open(str(mounted / ".DS_Store"), "r") as store:
            assert store[source.name]["Iloc"] == (230, 205)
            assert store["Applications"]["Iloc"] == (610, 205)
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(mounted / source.name)], check=True)
        if notarized:
            subprocess.run(["xcrun", "stapler", "validate", str(mounted / source.name)], check=True)
    finally:
        subprocess.run(["hdiutil", "detach", str(mounted)], check=True)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(image, destination)

print(f"Verified installer: {destination}")
print("Includes the signed app, Applications shortcut, Retina artwork, and saved Finder layout.")
