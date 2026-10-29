#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
app_dir="$repo_dir/dist/Notch Monster.app"
package_stage="$(mktemp -d /tmp/notch-monster-app.XXXXXX)"
staged_app="$package_stage/Notch Monster.app"
trap 'rm -rf "$package_stage"' EXIT
binary="$repo_dir/.build/release/NotchMonster"
signing_identity="${NOTCH_MONSTER_SIGNING_IDENTITY:-}"
notary_profile="${NOTCH_MONSTER_NOTARY_PROFILE:-}"
if [[ -z "$signing_identity" ]]; then
    identities="$(security find-identity -v -p codesigning)"
    if [[ -n "$notary_profile" ]]; then
        signing_identity="$(print -r -- "$identities" | awk -F '\"' '/\"Developer ID Application:/ {print $2; exit}')"
    else
        signing_identity="$(print -r -- "$identities" | awk -F '\"' '/\"Apple Development:/ {print $2; exit}')"
        if [[ -z "$signing_identity" ]]; then
            signing_identity="$(print -r -- "$identities" | awk -F '\"' '/\"Developer ID Application:/ {print $2; exit}')"
        fi
    fi
fi
if [[ -z "$signing_identity" ]]; then
    echo "No signing identity found. Install a certificate or set NOTCH_MONSTER_SIGNING_IDENTITY." >&2
    exit 1
fi
if [[ -n "$notary_profile" && "$signing_identity" != "Developer ID Application:"* ]]; then
    echo "Notarization requires a Developer ID Application signing identity." >&2
    exit 1
fi

cd "$repo_dir"
swift build -c release
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
cp "$binary" "$staged_app/Contents/MacOS/NotchMonster"
cp "$repo_dir/Resources/Info.plist" "$staged_app/Contents/Info.plist"
cp "$repo_dir/Resources/AppIcon.icns" "$staged_app/Contents/Resources/AppIcon.icns"
cp "$repo_dir/LICENSE" "$staged_app/Contents/Resources/Notch-Monster-LICENSE.txt"
mkdir -p "$staged_app/Contents/Resources/Raycast"
rsync -a --exclude=node_modules --exclude=dist --exclude=.DS_Store "$repo_dir/raycast/" "$staged_app/Contents/Resources/Raycast/"
mkdir -p "$staged_app/Contents/Resources/Sounds"
rsync -a --exclude=.DS_Store "$repo_dir/Resources/Sounds/" "$staged_app/Contents/Resources/Sounds/"
# Sign outside the iCloud-backed checkout so Finder metadata cannot race signing.
xattr -cr "$staged_app"
codesign --force --deep --timestamp --options runtime --entitlements "$repo_dir/Resources/NotchMonster.entitlements" --sign "$signing_identity" "$staged_app"
codesign --verify --deep --strict "$staged_app"
if [[ -n "$notary_profile" ]]; then
    ditto -c -k --keepParent --norsrc --noextattr --noqtn "$staged_app" "$package_stage/notarization.zip"
    xcrun notarytool submit "$package_stage/notarization.zip" --keychain-profile "$notary_profile" --wait --output-format json > "$package_stage/notarization.json"
    python3 -c 'import json, sys; result=json.load(open(sys.argv[1])); print("Apple notarization:", result["status"]); sys.exit(0 if result["status"] == "Accepted" else 1)' "$package_stage/notarization.json"
    xcrun stapler staple "$staged_app"
    xcrun stapler validate "$staged_app"
    spctl --assess --type execute --verbose "$staged_app"
else
    echo "Warning: this build is not notarized; downloaded copies may be blocked by Gatekeeper." >&2
fi
mkdir -p "$app_dir"
rsync -a --delete "$staged_app/" "$app_dir/"
xattr -cr "$app_dir"
if [[ -n "$notary_profile" ]]; then
    xcrun stapler validate "$app_dir"
    spctl --assess --type execute --verbose "$app_dir"
fi
echo "$app_dir"
