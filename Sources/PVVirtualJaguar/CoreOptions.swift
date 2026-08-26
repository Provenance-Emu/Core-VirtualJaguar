//
//  CoreOptions.swift
//  Core-VirtualJaguar
//
//  Created by Joseph Mattiello on 9/19/21.
//  Copyright © 2021 Provenance Emu. All rights reserved.
//

import Foundation
//import PVSupport
import PVCoreBridge
import PVCoreObjCBridge
import PVEmulatorCore

/// Options for the built-in (native-bridge) Virtual Jaguar core.
///
/// This build does **not** go through libretro's core-option API: the bridge
/// drives the emulator directly, so `libretro.c`'s `check_variables()` never
/// runs even though the file is compiled. Everything here therefore has to be
/// applied by hand in `PVJaguarGameCoreBridge.m`, and an option added here
/// without a matching line there does nothing at all.
///
/// Only options backed by state the bridge can actually reach are exposed:
/// a field on `vjs` (`settings.h`), or an `extern` in a public core header.
/// Options whose value lives in a `libretro.c` file-static — internal
/// resolution, true colour, widescreen, memory track — are deliberately
/// absent, because wiring them would silently do nothing.
internal final class JaguarCoreOptions: CoreOptions, Sendable {

    public static var options: [CoreOption] {
        var options = [CoreOption]()

        let biosGroup = CoreOption.group(.init(title: "BIOS", description: nil),
                                         subOptions: [biosOption, biosTypeOption])

        let speedGroup = CoreOption.group(
            .init(title: "Speed",
                  description: "Make the emulator faster. The fast-forward options cost nothing — identical picture and sound, just less work. The overclocks change what the game itself computes and can break it."),
            subOptions: [idleSkipOption,
                         blitMemoOption,
                         riscClockOption,
                         m68kClockOption])

        let accuracyGroup = CoreOption.group(
            .init(title: "Hardware Timing",
                  description: "Experimental, and the opposite of Speed: these make the emulator slower and closer to real silicon. Still being calibrated."),
            subOptions: [blitterTimingOption,
                         gpuPipelineTimingOption,
                         dramTimingOption])

        let videoGroup = CoreOption.group(
            .init(title: "Video", description: nil),
            subOptions: [blitterOption, forcePalOption])

        options.append(biosGroup)
        options.append(speedGroup)
        options.append(accuracyGroup)
        options.append(videoGroup)

        return options
    }

    // MARK: - BIOS

    nonisolated(unsafe) static let biosOption: CoreOption = .bool(.init(
        title: "Jaguar BIOS",
        description: "Use a real Jaguar BIOS file (you supply it yourself); otherwise the emulated BIOS is used.",
        requiresRestart: true), defaultValue: false)

    nonisolated(unsafe) static let biosTypeOption: CoreOption = .multi(.init(
        title: "BIOS Revision",
        description: "Which boot ROM revision to emulate. Leave on K-Series unless a specific title needs otherwise.",
        requiresRestart: true),
        values: [
            .init(title: "K-Series", description: "Default retail boot ROM", isDefault: true),
            .init(title: "M-Series", description: "Later retail revision"),
        ])

    // MARK: - Speed

    /// The single largest speed-up the core offers, and the one that matters
    /// most on Apple TV: on the titles measured it removes 66–87% of DSP
    /// interpretation. Bit-exact by construction, so save states and the
    /// picture are unaffected.
    nonisolated(unsafe) static let idleSkipOption: CoreOption = .bool(.init(
        title: "DSP Idle-Loop Fast-Forward",
        description: "Skip provably redundant iterations when the DSP is parked in a wait loop — 66-87% less DSP work on the titles measured, with an identical picture and sound. Off by default while the compatibility list grows. NOTE: a non-stock RISC Clock Scale or Blit Memoization turns this off, so those can leave you slower overall.",
        requiresRestart: false), defaultValue: false)

    nonisolated(unsafe) static let blitMemoOption: CoreOption = .bool(.init(
        title: "Blit Memoization",
        description: "Skip blits whose inputs are provably unchanged since an identical earlier one. Output is bit-identical. Helps titles that redraw the same scene while you stand still. Turns off DSP Idle-Loop Fast-Forward while enabled.",
        requiresRestart: false), defaultValue: false)

    /// Percentages, matching `riscClockScalePct` / `m68kClockScalePct`.
    nonisolated(unsafe) static let riscClockOption: CoreOption = .multi(.init(
        title: "RISC (GPU/DSP) Overclock",
        description: "Run the GPU and DSP faster than the stock ~26.6 MHz. Audio and timers stay at stock speed, so nothing pitch-shifts. Helps genuinely GPU-bound titles (Cybermorph gains ~45% at 1.5x) and does nothing for the many titles paced by a field lock or their own frame cap. Anything but 1x switches OFF DSP Idle-Loop Fast-Forward. Report bugs only at 1x.",
        requiresRestart: false),
        values: [
            .init(title: "0.5x", description: "Underclock"),
            .init(title: "1x", description: "Stock", isDefault: true),
            .init(title: "1.5x", description: "Moderate"),
            .init(title: "2x", description: "Aggressive"),
        ])

    nonisolated(unsafe) static let m68kClockOption: CoreOption = .multi(.init(
        title: "M68K Overclock",
        description: "Run the 68000 faster than the stock ~13.3 MHz. The safer of the two scales — it does NOT cost you DSP Idle-Loop Fast-Forward — but it helps less often, because most titles idle-wait their 68000. Report bugs only at 1x.",
        requiresRestart: false),
        values: [
            .init(title: "0.5x", description: "Underclock"),
            .init(title: "1x", description: "Stock", isDefault: true),
            .init(title: "1.5x", description: "Moderate"),
            .init(title: "2x", description: "Aggressive"),
            .init(title: "3x", description: "Maximum — known to hang Defender 2000"),
        ])

    // MARK: - Hardware timing (experimental)

    nonisolated(unsafe) static let blitterTimingOption: CoreOption = .bool(.init(
        title: "Blitter Bus Timing",
        description: "Charge the 68000 the bus time each blit really takes. On hardware the blitter is top-priority bus master and freezes the cacheless 68000 while it runs; zero-time blits let some games run too fast.",
        requiresRestart: false), defaultValue: false)

    nonisolated(unsafe) static let gpuPipelineTimingOption: CoreOption = .bool(.init(
        title: "GPU Pipeline Timing",
        description: "Model the GPU's real instruction costs — the single external-memory gateway, register score-board and ALU interlocks. Without it the emulated GPU finishes renders 2-4x faster than silicon. Turns off DSP Idle-Loop Fast-Forward while enabled.",
        requiresRestart: false), defaultValue: false)

    nonisolated(unsafe) static let dramTimingOption: CoreOption = .bool(.init(
        title: "DRAM Timing",
        description: "Charge the GPU and 68000 realistic DRAM access time once they leave their local buses. Turns off DSP Idle-Loop Fast-Forward while enabled.",
        requiresRestart: false), defaultValue: false)

    // MARK: - Video

    nonisolated(unsafe) static let blitterOption: CoreOption = .bool(.init(
        title: "Use Fast Blitter",
        description: "Faster but less accurate blitter. Known to drop Iron Soldier's briefing wireframe; leave off if a game renders wrongly.",
        requiresRestart: true), defaultValue: true)

    nonisolated(unsafe) static let forcePalOption: CoreOption = .bool(.init(
        title: "Force PAL",
        description: "Force PAL mode over NTSC. May fix ROMs that are misdetected or coded for PAL.",
        requiresRestart: true), defaultValue: false)
}

extension PVJaguarGameCore: CoreOptional {
    public static var options: [PVCoreBridge.CoreOption] {
        JaguarCoreOptions.options
    }
}

@objc
public extension PVJaguarGameCore {

    // MARK: BIOS
    @objc var virtualjaguar_bios: Bool { PVJaguarGameCore.valueForOption(JaguarCoreOptions.biosOption).asBool }

    /// Maps to the `BT_*` enum in `settings.h`: 0 = K-Series, 1 = M-Series.
    @objc var virtualjaguar_bios_type: Int {
        PVJaguarGameCore.valueForOption(JaguarCoreOptions.biosTypeOption).asString == "M-Series" ? 1 : 0
    }

    // MARK: Video
    @objc var virtualjaguar_usefastblitter: Bool { PVJaguarGameCore.valueForOption(JaguarCoreOptions.blitterOption).asBool }
    @objc var virtualjaguar_pal: Bool { PVJaguarGameCore.valueForOption(JaguarCoreOptions.forcePalOption).asBool }

    // MARK: Speed
    @objc var virtualjaguar_risc_idle_skip: Bool { PVJaguarGameCore.valueForOption(JaguarCoreOptions.idleSkipOption).asBool }
    @objc var virtualjaguar_blit_memo: Bool { PVJaguarGameCore.valueForOption(JaguarCoreOptions.blitMemoOption).asBool }

    /// Clock scales reach the core as integer percentages
    /// (`riscClockScalePct` / `m68kClockScalePct`), so "1.5x" becomes 150.
    /// 100 is stock and is also the fallback for an unrecognised value —
    /// an unknown string must never silently overclock the machine.
    @objc var virtualjaguar_risc_clock_pct: Int {
        Self.pct(PVJaguarGameCore.valueForOption(JaguarCoreOptions.riscClockOption).asString)
    }
    @objc var virtualjaguar_m68k_clock_pct: Int {
        Self.pct(PVJaguarGameCore.valueForOption(JaguarCoreOptions.m68kClockOption).asString)
    }

    // MARK: Hardware timing
    @objc var virtualjaguar_blitter_timing: Bool { PVJaguarGameCore.valueForOption(JaguarCoreOptions.blitterTimingOption).asBool }
    @objc var virtualjaguar_gpu_pipeline_timing: Bool { PVJaguarGameCore.valueForOption(JaguarCoreOptions.gpuPipelineTimingOption).asBool }
    @objc var virtualjaguar_dram_timing: Bool { PVJaguarGameCore.valueForOption(JaguarCoreOptions.dramTimingOption).asBool }

    private static func pct(_ value: String) -> Int {
        switch value {
        case "0.5x": return 50
        case "1.5x": return 150
        case "2x":   return 200
        case "3x":   return 300
        default:     return 100
        }
    }
}

//
//extension PVJaguarGameCore: CoreActions {
//	public var coreActions: [CoreAction]? {
//		let bios = CoreAction(title: "Use Jaguar BIOS", options: nil)
//		let fastBlitter =  CoreAction(title: "Use fast blitter", options:nil)
//		return [bios, fastBlitter]
//	}
//
//	public func selected(action: CoreAction) {
//		DLOG("\(action.title), \(String(describing: action.options))")
//	}
//}
