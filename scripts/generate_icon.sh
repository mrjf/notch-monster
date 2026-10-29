#!/bin/zsh
set -euo pipefail
repo_dir="${0:A:h:h}"
icon_stage="$(mktemp -d /tmp/notch-hand-icon.XXXXXX)"
trap 'rm -rf "$icon_stage"' EXIT
swiftc -parse-as-library "$repo_dir/Sources/NotchMonster/PuppetArm.swift" "$repo_dir/scripts/generate_icon.swift" -o "$icon_stage/generate-icon"
"$icon_stage/generate-icon" "$repo_dir"
