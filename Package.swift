// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

enum Sources {
    static let libjaguar: [String] = [
        "blitter.c",
        "cdintf.c",
        "cdrom.c",
        "crc32.c",
        "dac.c",
        "dsp.c",
        "eeprom.c",
        "event.c",
        "file.c",
        "filedb.c",
        "gpu.c",
        "jagbios.c",
        "jagbios2.c",
        "jagcdbios.c",
        "jagdevcdbios.c",
        "jagstub1bios.c",
        "jagstub2bios.c",
        "jaguar.c",
        "jerry.c",
        "joystick.c",
        "m68000/cpudefs.c",
        "m68000/cpuemu.c",
        "m68000/cpuextra.c",
        "m68000/cpustbl.c",
        "m68000/m68kinterface.c",
        "m68000/readcpu.c",
        "memtrack.c",
        "mmu.c",
        "op.c",
        "settings.c",
        "tom.c",
        "universalhdr.c",
        "vjag_memory.c",
        "wavetable.c",
    ]

    static let libretro_common: [String] = [
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
        .tvOS("15.4"),
        .watchOS(.v9),
        .macOS(.v11),
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
                "libjaguar",
                "PVVirtualJaguarGameCoreBridge"
            ],
            resources: [
                .process("Resources/Core.plist")
            ],
            cSettings: [
                .define("INLINE", to: "inline"),
                .define("USE_STRUCTS", to: "1"),
                .define("__LIBRETRO__", to: "1"),
                .define("HAVE_COCOATOUCH", to: "1"),
                .define("__GCCUNIX__", to: "1"),
                .headerSearchPath("../virtualjaguar-libretro/src"),
                .headerSearchPath("../virtualjaguar-libretro/src/m68000"),
                .headerSearchPath("../virtualjaguar-libretro/libretro-common"),
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
                .define("USE_STRUCTS", to: "1"),
                .define("__LIBRETRO__", to: "1"),
                .define("HAVE_COCOATOUCH", to: "1"),
                .define("__GCCUNIX__", to: "1"),
                .headerSearchPath("../virtualjaguar-libretro/src"),
                .headerSearchPath("../virtualjaguar-libretro/src/m68000"),
                .headerSearchPath("../virtualjaguar-libretro/libretro-common"),
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
            ],
            sources: Sources.libjaguar,
            //                ,Sources.libretro_common.map { "libretro-common/\($0)" }].flatMap { $0 },
            publicHeadersPath: "./",
            packageAccess: true,
            cSettings: [
                .define("INLINE", to: "inline"),
                .define("USE_STRUCTS", to: "1"),
//                .define("USE_SSE", to: "1"),
                .define("__LIBRETRO__", to: "1"),
                .define("HAVE_COCOATOUCH", to: "1"),
                .define("__GCCUNIX__", to: "1"),
                .headerSearchPath("virtualjaguar-libretro/src"),
                .headerSearchPath("src"),
                .headerSearchPath("libretro-common/include")
            ]
        ),

        // MARK: --------- libjaguar > libretro-common ---------- //

        .target(
            name: "libretro-common",
            path: "Sources/virtualjaguar-libretro/libretro-common",
            exclude: [
                "include/vfs/vfs_implementation_cdrom.h"
            ],
            sources: [
                "encodings/encoding_utf.c",
                "file/file_path.c",
                "file/file_path_io.c",
                "streams/file_stream.c",
                "streams/file_stream_transforms.c",
                "string/stdstring.c",
                "time/rtime.c",
                "vfs/vfs_implementation.c"
            ],
            publicHeadersPath: "include.spm",
            packageAccess: false,
            cSettings: [
                .define("INLINE", to: "inline"),
                .define("USE_STRUCTS", to: "1"),
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
