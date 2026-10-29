# Notch Monster

[Website & interactive demo](https://notchmonster.com/) · [Download for Mac](https://notchmonster.com/assets/Notch-Monster-0.1.12.dmg)

A native macOS creature that lives in the display notch and eats clutter. It stays invisible until triggered; then a stiff, fuzzy purple puppet arm snaps straight to the cursor. The palm and forearm stay rigid while the fingers curl around the item.

This repository contains both the native app and the Snow Leopard-style website.

- `Sources/NotchMonster/` — native Swift/SwiftUI app.
- `website/dist/` — static website, interactive desktop demo, and web artwork.
- `raycast/` — companion extension for sending caught files to Raycast.
- `scripts/` — icon, sound, signing, ZIP, and DMG build tools.
- `Tests/` and `website/tests/` — app and browser interaction tests.

The download requires macOS 15 or later on Apple silicon. Version 0.1.12 is an
interim, ad hoc-signed build without Apple notarization. Quit the older app, open
the DMG, and drag Notch Monster to Applications. After the first blocked launch,
use **System Settings → Privacy & Security → Open Anyway**. Open the copy in
Applications, enable both window permissions in its Settings, and quit and reopen
when macOS asks. Settings is always available from the Dock or by reopening the app.
See the [installation and permission guide](https://notchmonster.com/setup.html)
if a permission is already enabled but the app cannot use it.

## Run it

Requires macOS 15 or later and Swift 6.2 / Xcode 26 or later. Build and run the signed app bundle:

```sh
scripts/package_app.sh
open "dist/Notch Monster.app"
```

The packaging script selects an installed Apple Development identity by default. Select a particular identity with `NOTCH_MONSTER_SIGNING_IDENTITY`:

```sh
NOTCH_MONSTER_SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)" scripts/package_app.sh
```

Use the same signing identity across builds so macOS can retain the app's permission grants. Release packaging and the ZIP/DMG exporters require an Apple signing certificate by default. The interim-release override below explicitly allows ad hoc distribution while Developer ID signing is being set up.

For a local build without a signing certificate:

```sh
NOTCH_MONSTER_LOCAL_PREVIEW=1 scripts/package_app.sh
open "dist/Notch Monster Preview.app"
```

This creates **Notch Monster Preview** with bundle identifier `com.notchmonster.preview`. Its permission entries are separate from the release app. Keep it outside Applications and quit the release app while testing native drags. Ad hoc preview grants may need renewing after a rebuild. A preview is not a distributable release.

## How it works

- Pass an empty pointer just below the center of the notch and the arm comes out for a short wave.
- **Bat the cursor away** is an optional Settings mode, off by default and remembered between launches. When your empty pointer approaches, the hand swats it away in a short flight within the same display. Moving or clicking takes control back immediately. Reduced motion disables cursor flight.
- Drag a file into the arm's reach and drop it. The native file drop moves it to Trash, then the arm snaps its icon into the notch in about 130 ms. Files can be restored from Trash.
- Drag a window by its title bar and release within reach. The app captures an image, closes that exact window, and squeezes the screenshot into an accordion fold during a roughly 180 ms yank.
- Eating an application's last window also asks it to quit normally. Other windows, including minimized ones, keep it running. Save confirmations and refused closes never trigger a quit.
- Moving five points away releases the hand, even inside its reach; smaller wobbles stay attached. Pausing after release keeps it released, so you can place a window near the notch. Moving closer again reattaches it. Moving inward or pausing while attached keeps the hand ready.
- Use Settings from the Dock or purple-hand menu-bar icon to set **Arm length** (80–360 pt, remembered between launches), disable window closing, reduce motion, or quit.
- **Sound effects** are off by default. Enable the Earshot-made reach and yank cues in Settings, choose **Fuzzy**, **Rubber**, or **Arcade**, and use **Preview** to hear it. Mute and the selected set are remembered. All sounds are bundled and play locally; see [sound design](sound-design/README.md) for reproducible recipes.
- To keep files and choose another action, select **Send to Raycast** in Settings. Install the [local Raycast companion](raycast/README.md) once, then drop one or more files into the notch for Open With, Quick Look, Reveal, Copy, or Trash actions. The file action is remembered between launches; the default is Trash.

Settings opens when the app launches. Return to it by clicking Notch Monster in the Dock or reopening it from Applications, even when its menu-bar icon is hidden.

Window feeding requires **Accessibility** permission to control the window and **Screen Recording** permission to capture its image. The checklist at the top of Settings shows which permissions are missing, with an Enable button for each System Settings pane. Enable Notch Monster in both panes; if macOS asks you to quit and reopen the app, do so. On every launch, the app checks Accessibility and verifies ScreenCaptureKit by taking and discarding a single-pixel capture. The checklist reports the actual capture error if a grant is stale or unusable; use Check permissions again after changing permissions. Until both checks pass, window grabbing stays off; file drops still work. No Automation or System Events permission is needed.

A temporary capture failure does not mean permission was revoked. Settings distinguishes denied access from an unfinished check. Once capture has succeeded, temporary failures allow another grab; a successful retry clears the error. Only an explicit ScreenCaptureKit permission denial asks you to repair the Screen Recording grant.

If an enabled permission still reports denied after updating, quit Notch Monster. In the affected **System Settings → Privacy & Security** pane, remove its old entry with **−**, then use **+** to add **/Applications/Notch Monster.app** and enable it again. Reopen the app and use **Retry capture check**. Do the same for Accessibility if that permission is also unavailable. Ad hoc signing identifies a particular binary, so a rebuilt app can need fresh grants even when the old entry is still enabled.

If an application refuses to close or asks for confirmation, the window remains open. Reduced motion uses a short fade.

## Public distribution

The current 0.1.12 download is ad hoc signed and not notarized. It works after the user approves the first launch and grants Accessibility and Screen Recording, but updates can require granting those permissions again. Build this interim release explicitly:

```sh
NOTCH_MONSTER_ALLOW_AD_HOC_RELEASE=1 scripts/package_app.sh
NOTCH_MONSTER_ALLOW_AD_HOC_RELEASE=1 python3 scripts/package_download.py
NOTCH_MONSTER_ALLOW_AD_HOC_RELEASE=1 python3 scripts/package_dmg.py
```

The override does not apply to the isolated Preview app, which cannot be exported. Keep the resulting binary unchanged once published so its permission identity stays consistent for that version.

A paid Apple Developer Program membership, a **Developer ID Application** certificate with its private key, and notarization credentials are required to remove the unverified-developer Gatekeeper warning. The existing Apple Development certificate cannot replace Developer ID distribution signing.

Once those are available, store the notarization credentials in a Keychain profile using `xcrun notarytool store-credentials`, then package with:

```sh
NOTCH_MONSTER_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTCH_MONSTER_NOTARY_PROFILE='notch-monster' ./scripts/package_app.sh
python3 scripts/package_download.py
```

The packaging script waits for Apple to accept the submission, staples and validates the ticket, and checks Gatekeeper before exporting the app. Without a notarization profile it prints a warning and produces an unnotarized build. Download notes report the actual signing/notarization status.

The Mac application icon is `Resources/AppIcon.icns`, rendered directly from the app's fuzzy `PuppetArm` artwork with a transparent background. Run `./scripts/generate_icon.sh` to regenerate the full set of icon sizes and its PNG preview.

## Drag-to-Applications installer

Build the styled DMG after packaging the app:

```sh
python3 -m venv /tmp/notch-dmg-tools
/tmp/notch-dmg-tools/bin/pip install -r scripts/dmg-requirements.txt
/tmp/notch-dmg-tools/bin/python scripts/package_dmg.py
```

The DMG has the real app and an Applications shortcut over Retina artwork, with a saved 840×700 Finder window and 840×640 Retina artwork. The artwork includes first-launch “Open Anyway” instructions for development builds; a verified notarized build gets regular onboarding instructions instead. Building an installer does not remove Gatekeeper checks. The script mounts the finished image read-only to verify its app signature, shortcut, background, and icon positions, then detaches it. The website's main download is the DMG; existing ZIP links remain available.

## Website development and tests

The website is a buildless static site. Serve it locally:

```sh
python3 -m http.server 4173 --directory website/dist
```

Open `http://localhost:4173`. To run the test suites:

```sh
swift test
npm --prefix website test
```

See [website/README.md](website/README.md) for deployment details. Installer
binaries and build caches are excluded from Git; build the app and DMG before
deploying if you need to host the download yourself. The live site is
[notchmonster.com](https://notchmonster.com/).

## License

Notch Monster's original code, fuzzy-hand artwork, and procedural sounds are
available under the [MIT license](LICENSE). Historical Apple artwork and the
GitHub mark retain their original rights and notices; see
[third-party notices](THIRD_PARTY_NOTICES.md) and
[asset sources](website/ASSET-SOURCES.md).
