# Core-VirtualJaguar
Atari Jaguar : https://icculus.org/virtualjaguar/

## Updating the core

`Sources/virtualjaguar-libretro` tracks the `provenance` branch of
[Provenance-Emu/virtualjaguar-libretro](https://github.com/Provenance-Emu/virtualjaguar-libretro):
libretro master plus the patches Provenance carries. That fork merges each
libretro master release in automatically (its `sync-upstream` workflow), and
this repo's `Upstream sync` workflow opens a bump PR here when the tip moves.

To bump by hand, from a Provenance checkout:

    Scripts/update-upstream.sh --build

The script moves the submodule, regenerates the `Package.swift` source lists
from upstream's `Makefile.common` (SwiftPM cannot glob), and builds for the
iOS and tvOS Simulator. Then commit here and bump `Cores/VirtualJaguar` in
Provenance. To carry a fix that upstream has not merged yet, cherry-pick it
onto the fork's `provenance` branch. It drops out on its own once upstream
merges it.
