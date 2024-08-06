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
internal import PVEmulatorCore

#if SWIFT_PACKAGE
import PVVirtualJaguarC
#endif

internal final class JaguarCoreOptions: Sendable {

    public static var options: [CoreOption] {
        var options = [CoreOption]()

        let biosGroup = CoreOption.group(.init(title: "BIOS", description: nil),
                                         subOptions: [biosOption])

        let hacksGroup = CoreOption.group(
            .init(title: "Hacks",
                  description: "Performance hacks that work with some games better than others."),
            subOptions: [blitterOption,
                         doomResHackOption,
                         forcePalOption,
                         mutliThreadedRenderingOption])

        options.append(biosGroup)
        options.append(hacksGroup)

        return options
    }


    nonisolated(unsafe) static let biosOption: CoreOption = .bool(.init(title: "Jaguar BIOS", description: "Use binary Jaguar BIOS file (you need to download this yourself) otherwise use emualted bios.", requiresRestart: true), defaultValue: false)

    nonisolated(unsafe) static let blitterOption: CoreOption = .bool(.init(title: "Use Fast Blitter", description: "Use fast but maybe more buggy bliter", requiresRestart: true), defaultValue: true)


    nonisolated(unsafe) static let doomResHackOption: CoreOption = .bool(.init(title: "DOOM Res Hack", description: "For DOOM", requiresRestart: true), defaultValue: false)

    nonisolated(unsafe) static let forcePalOption: CoreOption = .bool(.init(title: "Force PAL", description: "Force PAL mode over NTSC. May fix ROMs that are misdetected or coded for NTSC.", requiresRestart: true), defaultValue: false)

    nonisolated(unsafe) static let mutliThreadedRenderingOption: CoreOption = .bool(.init(
        title: "Mutli-threaded Rendering",
        description: "Render audio/video in seperate threads. May or may not improve performance.",
        requiresRestart: true),
                                                                defaultValue: false)

    nonisolated(unsafe) static let doubleBufferOption: CoreOption = .bool(.init(
        title: "Double buffer Rendering",
        description: "Render audio/video in a back buffer. May or may not improve peformance at a 1 frame delay cost.",
        requiresRestart: true),
                                                      defaultValue: true)
}

extension PVJaguarGameCore: CoreOptional {
    public static var options: [PVCoreBridge.CoreOption] {
        JaguarCoreOptions.options
    }
}

@objc
public extension PVJaguarGameCore {
    @objc var virtualjaguar_bios: Bool { PVJaguarGameCore.valueForOption(JaguarCoreOptions.biosOption).asBool }
    @objc var virtualjaguar_usefastblitter: Bool { PVJaguarGameCore.valueForOption(JaguarCoreOptions.blitterOption).asBool }
    @objc var virtualjaguar_doom_res_hack: Bool { PVJaguarGameCore.valueForOption(JaguarCoreOptions.doomResHackOption).asBool }
    @objc var virtualjaguar_pal: Bool { PVJaguarGameCore.valueForOption(JaguarCoreOptions.forcePalOption).asBool }

    @objc var virtualjaguar_mutlithreaded: Bool { PVJaguarGameCore.valueForOption(JaguarCoreOptions.mutliThreadedRenderingOption).asBool }
    @objc var virtualjaguar_double_buffer: Bool {
        get {
            PVJaguarGameCore.valueForOption(JaguarCoreOptions.doubleBufferOption).asBool
        }
        set {
            PVJaguarGameCore.setValue(newValue, forOption: JaguarCoreOptions.doubleBufferOption)
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
