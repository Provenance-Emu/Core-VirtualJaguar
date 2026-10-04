#!/usr/bin/env python3
"""Keep Package.swift in step with the upstream virtualjaguar-libretro build.

SwiftPM cannot glob, so Package.swift has to name every .c file the core
compiles. Hand-maintaining that list drifted by 27 files over seven releases
(see the v3.5.1 bump). Upstream's Makefile.common is the authoritative list,
so this script derives the lists from it instead.

    Scripts/sync_upstream_sources.py           # rewrite the generated blocks
    Scripts/sync_upstream_sources.py --check   # exit 1 if anything drifted

What it owns (between `BEGIN GENERATED` / `END GENERATED` markers):
  * libjaguar        -- every $(CORE_DIR)/*.c in a SOURCES_C list, plus all
                        three blitter_simd_*.c (each self-guards by arch).
  * libretro_common  -- every $(LIBRETRO_COMM_DIR)/*.c in a SOURCES_C list.
  * libchdr-deps     -- the vendored lzma/miniz/zstd include dirs, whose
                        version numbers are baked into their directory names.

What it only verifies: every -I$(CORE_DIR)/... dir in INCFLAGS is a
headerSearchPath of the libjaguar target, every generated path exists, and
SOURCES_LIBCHDR is still the single unity.c this manifest builds.

Pure stdlib, so the drift check runs on Linux CI without Xcode.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PACKAGE = ROOT / "Package.swift"
CORE = ROOT / "Sources" / "virtualjaguar-libretro"
MAKEFILE = CORE / "Makefile.common"
LIBCHDR = CORE / "deps" / "libchdr"

SIMD_RE = re.compile(r"\$\(CORE_DIR\)/(src/tom/blitter_simd_\w+\.c)")
SOURCES_START_RE = re.compile(r"^\s*SOURCES_C\s*[:+]?=")


def sources_c_lines(makefile: str) -> list[str]:
    """Every line belonging to a `SOURCES_C :=` / `SOURCES_C +=` statement,
    following backslash continuations."""
    lines, out, in_block = makefile.splitlines(), [], False
    for line in lines:
        if not in_block and SOURCES_START_RE.match(line):
            in_block = True
        if in_block:
            out.append(line)
            in_block = line.rstrip().endswith("\\")
    return out


def parse_makefile(makefile: str) -> dict[str, list[str]]:
    block = "\n".join(sources_c_lines(makefile))
    core = set(re.findall(r"\$\(CORE_DIR\)/(\S+\.c)\b", block))
    # Makefile.common picks ONE SIMD file per platform; we hand SwiftPM all
    # three and let blitter_simd_arch.h compile the wrong ones to nothing.
    core |= set(SIMD_RE.findall(makefile))
    common = set(re.findall(r"\$\(LIBRETRO_COMM_DIR\)/(\S+\.c)\b", block))
    chdr_deps = re.findall(r"-I\$\(LIBCHDR_DIR\)/(deps/\S+)", makefile)
    inc_dirs = re.findall(r"-I\$\(CORE_DIR\)/(\S+)", makefile)
    chdr_srcs = re.findall(r"SOURCES_LIBCHDR\s*:?=\s*(.+)", makefile)
    return {
        "libjaguar": sorted(core),
        "libretro_common": sorted(common),
        "libchdr-deps": chdr_deps,
        "inc_dirs": inc_dirs,
        "libchdr_sources": [s.strip() for s in chdr_srcs],
    }


def render(name: str, paths: list[str], indent: str) -> str:
    if name == "libchdr-deps":
        return "".join(f'{indent}.headerSearchPath("{p}"),\n' for p in paths)
    body = "".join(f'{indent}    "{p}",\n' for p in paths)
    return f"{indent}static let {name}: [String] = [\n{body}{indent}]\n"


def replace_block(text: str, name: str, paths: list[str]) -> str:
    pattern = re.compile(
        rf"(?P<head>^(?P<indent>[ \t]*)// BEGIN GENERATED {re.escape(name)}\b[^\n]*\n)"
        rf".*?"
        rf"(?P<tail>^[ \t]*// END GENERATED {re.escape(name)}\b[^\n]*$)",
        re.S | re.M,
    )
    match = pattern.search(text)
    if not match:
        sys.exit(f"error: no `// BEGIN GENERATED {name}` block in {PACKAGE.name}")
    new = match["head"] + render(name, paths, match["indent"]) + match["tail"]
    return text[: match.start()] + new + text[match.end():]


def target_block(text: str, target: str) -> str:
    start = text.find(f'name: "{target}"')
    if start < 0:
        sys.exit(f"error: target {target} not found in {PACKAGE.name}")
    end = text.find(".target(", start)
    return text[start: end if end > 0 else len(text)]


def verify(parsed: dict[str, list[str]], text: str) -> list[str]:
    problems = []
    for rel in parsed["libjaguar"]:
        if not (CORE / rel).is_file():
            problems.append(f"libjaguar source missing on disk: {rel}")
    for rel in parsed["libretro_common"]:
        if not (CORE / "libretro-common" / rel).is_file():
            problems.append(f"libretro-common source missing on disk: {rel}")
    for rel in parsed["libchdr-deps"]:
        if not (LIBCHDR / rel).is_dir():
            problems.append(f"libchdr include dir missing on disk: {rel}")
    if parsed["libchdr_sources"] != ["$(LIBCHDR_DIR)/unity.c"]:
        problems.append(
            f"SOURCES_LIBCHDR changed to {parsed['libchdr_sources']}; "
            "the libchdr-virtualjaguar target builds only unity.c"
        )
    libjaguar = target_block(text, "libjaguar")
    for rel in parsed["inc_dirs"]:
        if f'.headerSearchPath("{rel}")' not in libjaguar:
            problems.append(f'libjaguar lacks .headerSearchPath("{rel}") (in INCFLAGS)')
    for name in ("libjaguar", "libretro_common"):
        if not parsed[name]:
            problems.append(f"parsed zero {name} sources -- Makefile.common layout changed?")
    return problems


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", action="store_true", help="fail instead of rewriting")
    args = ap.parse_args()

    if not MAKEFILE.is_file():
        sys.exit(f"error: {MAKEFILE} not found -- run `git submodule update --init`")

    parsed = parse_makefile(MAKEFILE.read_text())
    original = PACKAGE.read_text()
    updated = original
    for name in ("libjaguar", "libretro_common", "libchdr-deps"):
        updated = replace_block(updated, name, parsed[name])

    problems = verify(parsed, updated)
    for p in problems:
        print(f"error: {p}", file=sys.stderr)

    if updated != original:
        if args.check:
            print(
                f"error: {PACKAGE.name} is out of date with Makefile.common; "
                "run Scripts/sync_upstream_sources.py",
                file=sys.stderr,
            )
            return 1
        PACKAGE.write_text(updated)
        print(f"updated {PACKAGE.name}")
    else:
        print(f"{PACKAGE.name} already matches Makefile.common")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
