#!/usr/bin/env python3
"""Archive the signed app without iCloud/Finder metadata from the checkout."""
from pathlib import Path
import os
import plistlib
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
app = root / "dist/Notch Monster.app"
version = plistlib.loads((app / "Contents/Info.plist").read_bytes())["CFBundleShortVersionString"]
archive = root / "website/dist/assets" / f"Notch-Monster-{version}.zip"
with tempfile.TemporaryDirectory(prefix="notch-monster-download-") as directory:
    stage = Path(directory)
    staged_app = stage / app.name
    shutil.copytree(app, staged_app)
    subprocess.run(["xattr", "-cr", str(staged_app)], check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(staged_app)], check=True)
    signature = subprocess.run(["codesign", "-dv", "--verbose=4", str(staged_app)], capture_output=True, text=True, check=True).stderr
    ad_hoc = "Signature=adhoc" in signature
    allow_ad_hoc = ad_hoc and os.environ.get("NOTCH_MONSTER_ALLOW_AD_HOC_RELEASE") == "1"
    if not allow_ad_hoc and not any(authority in signature for authority in ("Authority=Apple Development:", "Authority=Developer ID Application:")):
        raise SystemExit("Refusing to distribute an app without an Apple code-signing identity. Set NOTCH_MONSTER_ALLOW_AD_HOC_RELEASE=1 explicitly for an ad hoc interim release that may require new permission grants after updates.")
    if plistlib.loads((staged_app / "Contents/Info.plist").read_bytes())["CFBundleIdentifier"] != "com.notchmonster.app":
        raise SystemExit("Refusing to distribute a local preview.")
    notarized = "Authority=Developer ID Application:" in signature and subprocess.run(
        ["xcrun", "stapler", "validate", str(staged_app)], capture_output=True).returncode == 0
    if notarized:
        trust_note = "This build is Developer ID signed and notarized by Apple."
    elif "Authority=Developer ID Application:" in signature:
        raise SystemExit("Refusing to archive a Developer ID release without a valid stapled notarization ticket.")
    elif ad_hoc:
        trust_note = "This interim build is ad hoc signed and is not notarized by Apple. macOS may block it on first launch. After opening it once, use System Settings → Privacy & Security → Open Anyway and confirm Open. An update can invalidate earlier Accessibility and Screen Recording grants: if a permission is enabled but Settings still cannot verify access, remove the old Notch Monster entry from that privacy list, add /Applications/Notch Monster.app again, and enable it. Quit and reopen the app when macOS asks, then use Check permissions again."
    else:
        trust_note = "This early build is development signed and not notarized. macOS may block it because it has not been verified by Apple."
    (stage / "Read Me.txt").write_text(f"""Notch Monster — early build {version}

Requires macOS 15 or later on Apple silicon.

Move Notch Monster.app to Applications and open it. Settings opens at launch; click the Dock icon or reopen the app to return, even if the menu-bar icon is hidden. Settings checks Accessibility and performs a one-pixel capture test before enabling window grabbing. Allow both permissions and use Check permissions again after changing them. If macOS asks to quit and reopen, do so.

Move toward the notch to meet the hand. Moving five points away releases it; smaller wobbles stay attached. Pausing after release leaves it released, so you can place the window there. Move closer again to reattach. Arm length in Settings controls its reach and is saved between launches.

Sound effects in Settings can be muted or switched between Fuzzy, Rubber, and Arcade. Preview lets you hear the selected set. These Earshot-made sounds are bundled with the app; your selection is saved between launches.

Eating an application's last open window also asks it to quit normally. Minimized windows count as open. Save confirmations are respected, and applications are never force-quit.

Files go to Trash by default. Choose Send to Raycast in Settings to use the companion extension; the setup button opens its instructions in a writable folder. Original files stay where they are when sent to Raycast.

{trust_note}
""")
    archive.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["ditto", "-c", "-k", "--norsrc", "--noextattr", "--noqtn", str(stage), str(archive)], check=True)
print(archive)
