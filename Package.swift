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
        "src/tom/blitter_simd_neon.c",
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
        "src/bios/jagstub1bios.c",
        "src/bios/jagstub2bios.c",
        "src/m68000/cpudefs.c",
        "src/m68000/cpuemu.c",
        "src/m68000/cpuextra.c",
        "src/m68000/cpustbl.c",
        "src/m68000/m68kinterface.c",
        "src/m68000/readcpu.c",
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

        // MARK: --------- libjaguar ---------- //

        .target(
            name: "libjaguar",
            dependencies: ["libretro-common"],
            // Point at the submodule root so we can compile the upstream
            // `libretro.c` (which lives at the root) directly, instead of
            // duplicating it under src/ to satisfy SPM's "sources must live
            // under target.path" rule. All other sources live under src/.
            path: "Sources/virtualjaguar-libretro",
            exclude: [
                // The scalar implementation is the no-SIMD fallback. We
                // always have either NEON or SSE2 available on the
                // platforms we target (Apple silicon arm64, Intel x86_64
                // sim slice), so scalar is dead code in the SPM build.
                "src/tom/blitter_simd_scalar.c",
            ],
            sources: Sources.libjaguar,
            publicHeadersPath: "src/core",
            packageAccess: true,
            cSettings: [
                .define("INLINE", to: "inline"),
                .define("__LIBRETRO__", to: "1"),
                .define("HAVE_COCOATOUCH", to: "1"),
                .define("__GCCUNIX__", to: "1"),
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
