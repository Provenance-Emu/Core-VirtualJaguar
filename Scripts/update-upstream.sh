#!/usr/bin/env bash
# Bump virtualjaguar-libretro to the tip of the Provenance fork's `provenance`
# branch (libretro master + the patches Provenance carries) and regenerate the
# Package.swift source lists from upstream's Makefile.common.
#
#   Scripts/update-upstream.sh            # bump + regenerate
#   Scripts/update-upstream.sh --build    # ...then build iOS + tvOS Simulator
#
# --build needs this repo checked out at Cores/VirtualJaguar inside a
# Provenance checkout: the package depends on ../../PV* by relative path.
# Review and commit the result, then bump the gitlink in Provenance.
#
# The fork's `provenance` branch is kept in step with libretro/master by its
# own sync-upstream workflow. A carried patch that upstream later merges drops
# out on its own the next time master is merged in.
set -euo pipefail

cd "$(dirname "$0")/.."
SUBMODULE=Sources/virtualjaguar-libretro

git submodule sync -- "$SUBMODULE"
git submodule update --init --remote -- "$SUBMODULE"
echo "virtualjaguar-libretro now at $(git -C "$SUBMODULE" describe --tags --always)"

python3 Scripts/sync_upstream_sources.py

if [[ "${1:-}" == "--build" ]]; then
    # Through the parent workspace, not this directory: here xcodebuild would
    # pick the legacy PVVirtualJaguar.xcodeproj (its own stale file list)
    # over Package.swift, which is what the app actually links.
    WORKSPACE=../../Provenance.xcworkspace
    if [[ ! -d "$WORKSPACE" ]]; then
        echo "error: --build needs this repo at Cores/VirtualJaguar in a Provenance checkout" >&2
        exit 1
    fi
    for platform in "iOS Simulator" "tvOS Simulator"; do
        echo "=== Building PVVirtualJaguar for $platform"
        xcodebuild build -workspace "$WORKSPACE" -scheme PVVirtualJaguar \
            -destination "generic/platform=$platform" \
            CODE_SIGNING_ALLOWED=NO \
            -skipPackagePluginValidation -skipMacroValidation \
            -quiet
    done
fi

git status --short -- "$SUBMODULE" Package.swift
