// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

enum Sources {
    static let libjaguar: [String] = [
        "tom/blitter.c",
        "tom/blitter_compare.c",
        "tom/blitter_mmio.c",
        "tom/blitter_simd_neon.c",
        "tom/gpu.c",
        "tom/op.c",
        "tom/tom.c",
        "jerry/dac.c",
        "jerry/dsp.c",
        "jerry/eeprom.c",
        "jerry/jerry.c",
        "jerry/joystick.c",
        "jerry/wavetable.c",
        "core/cheat.c",
        "core/crc32.c",
        "core/event.c",
        "core/file.c",
        "core/filedb.c",
        "core/jaguar.c",
        "core/memtrack.c",
        "core/settings.c",
        "core/universalhdr.c",
        "core/vjag_memory.c",
        "cd/cdintf.c",
        "cd/cdrom.c",
        "bios/jagbios.c",
        "bios/jagcdbios.c",
        "bios/jagdevcdbios.c",
        "bios/jagstub1bios.c",
        "bios/jagstub2bios.c",
        "m68000/cpudefs.c",
        "m68000/cpuemu.c",
        "m68000/cpuextra.c",
        "m68000/cpustbl.c",
        "m68000/m68kinterface.c",
        "m68000/readcpu.c",
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
            path: "Sources/virtualjaguar-libretro/src",
            exclude: [
                "tom/blitter_simd_sse2.c",
                "tom/blitter_simd_scalar.c",
            ],
            sources: Sources.libjaguar,
            publicHeadersPath: "core",
            packageAccess: true,
            cSettings: [
                .define("INLINE", to: "inline"),
                .define("__LIBRETRO__", to: "1"),
                .define("HAVE_COCOATOUCH", to: "1"),
                .define("__GCCUNIX__", to: "1"),
                .headerSearchPath("./"),
                .headerSearchPath("../"),
                .headerSearchPath("core"),
                .headerSearchPath("tom"),
                .headerSearchPath("jerry"),
                .headerSearchPath("cd"),
                .headerSearchPath("bios"),
                .headerSearchPath("m68000"),
                .headerSearchPath("../../virtualjaguar-libretro/libretro-common/include"),
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
