// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

enum Sources {
    // Paths relative to `Sources/virtualjaguar-libretro/` (the submodule
    // root), so the SPM target points at upstream files in place — no
    // duplication. `libretro.c` lives at the submodule root; everything
    // else lives under `src/`.
    static let libjaguar: [String] = [
        "src/tom/blitter.c",
        "src/tom/blitter_compare.c",
        "src/tom/blitter_mmio.c",
        // All three SIMD variants are handed to the compiler; each one
        // guards itself via src/tom/blitter_simd_arch.h and compiles to an
        // empty TU unless it is the right one for the target. Exactly one
        // survives per target -- scalar included, so a target with neither
        // NEON nor SSE2 still gets a blitter_simd_ops rather than a link
        // error. BLITTER_SIMD_AUTODETECT below is what arms that.
        "src/tom/blitter_simd_neon.c",
        "src/tom/blitter_simd_scalar.c",
        "src/tom/blitter_simd_sse2.c",
        "src/tom/gpu.c",
        "src/tom/op.c",
        "src/tom/tom.c",
        "src/jerry/dac.c",
        "src/jerry/dsp.c",
        "src/jerry/eeprom.c",
        "src/jerry/jerry.c",
        "src/jerry/joystick.c",
        "src/jerry/wavetable.c",
        "src/core/cheat.c",
        "src/core/crash_detect.c",
        "src/core/crc32.c",
        "src/core/event.c",
        "src/core/file.c",
        "src/core/filedb.c",
        "src/core/jaguar.c",
        "src/core/memtrack.c",
        "src/core/perf_counters.c",
        "src/core/settings.c",
        "src/core/universalhdr.c",
        "src/core/vjag_memory.c",
        "src/cd/cdintf.c",
        "src/cd/cdrom.c",
        "src/bios/jagbios.c",
        "src/bios/jagcdbios.c",
        "src/bios/jagdevcdbios.c",
        "src/m68000/cpudefs.c",
        "src/m68000/cpuemu.c",
        "src/m68000/cpuextra.c",
        "src/m68000/cpustbl.c",
        "src/m68000/m68kinterface.c",
        "src/m68000/readcpu.c",
        /* Added 2026-08-25 with the bump to v3.5.1. Reconciled against
         * Makefile.common, which is the authoritative source list --
         * hand-maintaining this drifted by 27 files over seven releases. */
        "src/bios/jagbios_m.c",
        "src/cd/jagcd_bios.c",
        "src/cd/jagcd_cart.c",
        "src/cd/jagcd_hle.c",
        "src/core/biosdb.c",
        "src/core/bus_arbiter.c",
        "src/core/jaggd.c",
        "src/core/nvmbios.c",
        "src/core/perf_iface.c",
        "src/core/titledb.c",
        "src/core/titlehook.c",
        "src/core/vjtrace.c",
        "src/jerry/axistune.c",
        "src/jerry/inputdev.c",
        "src/jerry/jlink.c",
        "src/jerry/jlink_discover.c",
        "src/jerry/jlink_netpacket.c",
        "src/jerry/jlink_tcp.c",
        "src/jerry/paddle.c",
        "src/jerry/quadrature.c",
        "src/jerry/uart.c",
        "src/jerry/voicechat.c",
        "src/jerry/voicemodem.c",
        "src/tom/blit_memo.c",
        "src/tom/shadowfb.c",
        "src/tom/texdump.c",
        "src/tom/texreplace.c",
        "libretro.c",
    ]

    static let libretro_common: [String] = [
        "compat/compat_strcasestr.c",
        "compat/compat_snprintf.c",
        "compat/compat_strl.c",
        "compat/compat_posix_string.c",
        "compat/fopen_utf8.c",
        "encodings/encoding_utf.c",
        "file/file_path.c",
        "file/file_path_io.c",
        "streams/file_stream.c",
        "streams/file_stream_transforms.c",
        "string/stdstring.c",
        "time/rtime.c",
        "vfs/vfs_implementation.c"
    ]
}

let package = Package(
    name: "PVCoreVirtualJaguar",
    platforms: [
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v9),
        .macOS(.v14),
        .macCatalyst(.v17),
        .visionOS(.v1)
    ],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "PVVirtualJaguar",
            targets: ["PVVirtualJaguar"]),
        .library(
            name: "PVVirtualJaguar-Dynamic",
            type: .dynamic,
            targets: ["PVVirtualJaguar"]),
        .library(
            name: "PVVirtualJaguar-Static",
            type: .static,
            targets: ["PVVirtualJaguar"]),

    ],
    dependencies: [
        .package(path: "../../PVCoreBridge"),
        .package(path: "../../PVCoreObjCBridge"),
        .package(path: "../../PVPlists"),
        .package(path: "../../PVEmulatorCore"),
        .package(path: "../../PVSupport"),
        .package(path: "../../PVAudio"),
        .package(path: "../../PVLogging"),
        .package(path: "../../PVObjCUtils"),
        .package(name: "PVPrimitives", path: "../../PVPrimitives/"),

        .package(url: "https://github.com/Provenance-Emu/SwiftGenPlugin.git", branch: "develop"),
    ],
    targets: [

        // MARK: --------- PVVirtualJaguar ---------- //

        .target(
            name: "PVVirtualJaguar",
            dependencies: [
                "PVEmulatorCore",
                "PVCoreBridge",
                "PVCoreObjCBridge",
                "PVLogging",
                "PVAudio",
                "PVSupport",
                "PVPrimitives",
                "libjaguar",
                "PVVirtualJaguarGameCoreBridge"
            ],
            resources: [
                .process("Resources/Core.plist")
            ],
            cSettings: [
                .define("INLINE", to: "inline"),
                .define("__LIBRETRO__", to: "1"),
                .define("HAVE_COCOATOUCH", to: "1"),
                .define("__GCCUNIX__", to: "1"),
                .headerSearchPath("../virtualjaguar-libretro/src"),
                .headerSearchPath("../virtualjaguar-libretro/src/core"),
                .headerSearchPath("../virtualjaguar-libretro/src/tom"),
                .headerSearchPath("../virtualjaguar-libretro/src/jerry"),
                .headerSearchPath("../virtualjaguar-libretro/src/cd"),
                .headerSearchPath("../virtualjaguar-libretro/src/bios"),
                .headerSearchPath("../virtualjaguar-libretro/src/m68000"),
                .headerSearchPath("../virtualjaguar-libretro/libretro-common/include"),
            ],
            plugins: [
                .plugin(name: "SwiftGenPlugin", package: "SwiftGenPlugin")
            ]
        ),

        // MARK: --------- PVVirtualJaguarGameCoreBridge ---------- //

        .target(
            name: "PVVirtualJaguarGameCoreBridge",
            dependencies: [
                "libjaguar",
                "PVEmulatorCore",
                "PVCoreBridge",
                "PVCoreObjCBridge",
                "PVSupport",
                "PVPlists",
                "PVObjCUtils",
            ],
            publicHeadersPath: "",
            cSettings: [
                .unsafeFlags([
                    "-fmodules",
                    "-fcxx-modules"
                ]),
                .define("INLINE", to: "inline"),
                .define("__LIBRETRO__", to: "1"),
                .define("HAVE_COCOATOUCH", to: "1"),
                .define("__GCCUNIX__", to: "1"),
                .headerSearchPath("../virtualjaguar-libretro/src"),
                .headerSearchPath("../virtualjaguar-libretro/src/core"),
                .headerSearchPath("../virtualjaguar-libretro/src/tom"),
                .headerSearchPath("../virtualjaguar-libretro/src/jerry"),
                .headerSearchPath("../virtualjaguar-libretro/src/cd"),
                .headerSearchPath("../virtualjaguar-libretro/src/bios"),
                .headerSearchPath("../virtualjaguar-libretro/src/m68000"),
                .headerSearchPath("../virtualjaguar-libretro/libretro-common/include"),
            ],
            cxxSettings: [
                .unsafeFlags([
                    "-fmodules",
                    "-fcxx-modules"
                ])
            ]
        ),

        // MARK: --------- libchdr-virtualjaguar ---------- //

        // Vendored CHD reader. Built exactly the way Makefile.common builds
        // it: one unity translation unit, with miniz's compressor switched
        // back on because texture dump (src/tom/texdump.c) needs
        // tdefl_write_image_to_png_file_in_memory_ex for its preview PNGs.
        //
        // No -std=c99 here, unlike the Makefile: SPM compiles C as gnu11 by
        // default, which is a superset, so the flag is unnecessary rather
        // than omitted by accident.
        //
        // NOT named plain "libchdr": SPM requires target names to be unique
        // across the whole package graph, and Cores/Mednafen vendors its own
        // copy under that name. Two cores each vendoring CHD is expected --
        // they pin different revisions and different build defines -- so the
        // names have to differ. Mednafen's is the older declaration, so this
        // one carries the suffix. The `#include <libchdr/chd.h>` spelling in
        // src/cd/cdintf.c is unaffected: that resolves through
        // publicHeadersPath, not the target name.
        .target(
            name: "libchdr-virtualjaguar",
            path: "Sources/virtualjaguar-libretro/deps/libchdr",
            sources: ["unity.c"],
            publicHeadersPath: "include",
            cSettings: [
                .define("_7ZIP_ST", to: "1"),
                .define("MINIZ_DEFLATE_APIS", to: "1"),
                .define("WANT_RAW_DATA_SECTOR", to: "1"),
                .define("WANT_SUBCODE", to: "1"),
                .define("VERIFY_BLOCK_CRC", to: "1"),
                .headerSearchPath("include"),
                .headerSearchPath("deps/lzma-25.01/include"),
                .headerSearchPath("deps/miniz-3.1.1"),
                .headerSearchPath("deps/zstd-1.5.7"),
                .unsafeFlags(["-Wno-unused-function", "-Wno-unused-variable"]),
            ]
        ),

        // MARK: --------- libjaguar ---------- //

        .target(
            name: "libjaguar",
            dependencies: ["libretro-common", "libchdr-virtualjaguar"],
            // Point at the submodule root so we can compile the upstream
            // `libretro.c` (which lives at the root) directly, instead of
            // duplicating it under src/ to satisfy SPM's "sources must live
            // under target.path" rule. All other sources live under src/.
            path: "Sources/virtualjaguar-libretro",
            sources: Sources.libjaguar,
            publicHeadersPath: "src/core",
            packageAccess: true,
            cSettings: [
                .define("INLINE", to: "inline"),
                .define("__LIBRETRO__", to: "1"),
                .define("HAVE_COCOATOUCH", to: "1"),
                .define("__GCCUNIX__", to: "1"),
                // Makefile.common picks ONE blitter_simd_<arch>.c and passes
                // a matching -DBLITTER_SIMD_<ARCH>; blitter_simd.h uses that
                // -D to decide which implementation blitter.c inlines. We
                // select by arch guard instead, so we have no -D to pass and
                // blitter.c silently inlined the SCALAR ops on arm64 while
                // the linked vtable was NEON -- and the vtable is only used
                // by the core's own tests, so nothing caught it.
                //
                // This tells blitter_simd.h to derive the arch from the
                // compiler's predefined macros. It must be decided there and
                // not here: this manifest is compiled for the HOST, so a
                // check in Swift would hand the x86_64 simulator slice the
                // arm64 answer.
                .define("BLITTER_SIMD_AUTODETECT", to: "1"),
                // Repo root for `<libretro_core_options.h>` and friends
                // referenced by libretro.c, plus per-subsystem header dirs
                // so internal includes like `#include "jaguar.h"` resolve.
                .headerSearchPath("./"),
                .headerSearchPath("src"),
                .headerSearchPath("src/core"),
                .headerSearchPath("src/tom"),
                .headerSearchPath("src/jerry"),
                .headerSearchPath("src/cd"),
                .headerSearchPath("src/bios"),
                // CHD disc images: src/cd/cdintf.c includes <libchdr/chd.h>
                // unconditionally since the v3.4.0 CHD work (#322/#476).
                .headerSearchPath("deps/libchdr/include"),
                .headerSearchPath("src/m68000"),
                .headerSearchPath("libretro-common/include"),
            ]
        ),

        // MARK: --------- libjaguar > libretro-common ---------- //

        .target(
            name: "libretro-common",
            path: "Sources/virtualjaguar-libretro/libretro-common",
            exclude: [
                "include/vfs/vfs_implementation_cdrom.h"
            ],
            sources: Sources.libretro_common,
            publicHeadersPath: "include",
            packageAccess: false,
            cSettings: [
                .define("INLINE", to: "inline"),
                .define("__LIBRETRO__", to: "1"),
                .define("HAVE_COCOATOUCH", to: "1"),
                .define("__GCCUNIX__", to: "1"),
                .headerSearchPath("./"),
                .headerSearchPath("./include"),
            ]
        ),
        // MARK: Tests
        .testTarget(
            name: "PVVirtualJaguarTests",
            dependencies: [
                "PVVirtualJaguar",
                "PVCoreBridge",
                "PVEmulatorCore",
                "libjaguar"
            ],
            resources: [
                .copy("VirtualJaguarTests/Resources/jag_240p_test_suite_v0.5.1.jag")
            ])
    ],
    swiftLanguageModes: [.v5, .v6],
    cLanguageStandard: .gnu11,
    cxxLanguageStandard: .gnucxx14
)
