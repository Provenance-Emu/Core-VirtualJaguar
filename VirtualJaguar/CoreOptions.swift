//
//  CoreOptions.swift
//  Core-VirtualJaguar
//
//  Created by Joseph Mattiello on 9/19/21.
//  Copyright © 2021 Provenance Emu. All rights reserved.
//

import Foundation
import PVSupport
//
//	@objc public enum GBPalette: Int {
//		case peaSoupGreen
//		case pocket
//		case blue
//		case darkBlue
//		case green
//		case darkGreen
//		case brown
//		case darkBrown
//		case red
//		case yellow
//		case orange
//		case pastelMix
//		case inverted
//		case romTitle
//		case grayscale
//	}
//

extension PVJaguarGameCore: CoreOptional {
	public static var options: [CoreOption] = {
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
	}()


	static var biosOption: CoreOption = {
		.bool(.init(title: "Jaguar BIOS", description: "Use binary Jaguar BIOS file (you need to download this yourself) otherwise use emualted bios.", requiresRestart: true), defaultValue: false)
	}()

	static var blitterOption: CoreOption = {
		.bool(.init(title: "Use Fast Blitter", description: "Use fast but maybe more buggy bliter", requiresRestart: true), defaultValue: true)
	}()
    
    static var doomResHackOption: CoreOption = {
		.bool(.init(title: "DOOM Res Hack", description: "For DOOM", requiresRestart: true), defaultValue: false)
    }()
    
    static var forcePalOption: CoreOption = {
		.bool(.init(title: "Force PAL", description: "Force PAL mode over NTSC. May fix ROMs that are misdetected or coded for NTSC.", requiresRestart: true), defaultValue: false)
    }()
    
    static var mutliThreadedRenderingOption: CoreOption = {
        .bool(.init(
                title: "Mutli-threaded Rendering",
                description: "Render audio/video in seperate threads. May or may not improve performance.",
                requiresRestart: true),
            defaultValue: false)
    }()
    
    static var doubleBufferOption: CoreOption = {
        .bool(.init(
                title: "Double buffer Rendering",
                description: "Render audio/video in a back buffer. May or may not improve peformance at a 1 frame delay cost.",
                requiresRestart: true),
            defaultValue: true)
    }()
}

@objc public extension PVJaguarGameCore {
    @objc var virtualjaguar_bios: Bool { PVJaguarGameCore.valueForOption(PVJaguarGameCore.biosOption).asBool }
    @objc var virtualjaguar_usefastblitter: Bool { PVJaguarGameCore.valueForOption(PVJaguarGameCore.blitterOption).asBool }
    @objc var virtualjaguar_doom_res_hack: Bool { PVJaguarGameCore.valueForOption(PVJaguarGameCore.doomResHackOption).asBool }
    @objc var virtualjaguar_pal: Bool { PVJaguarGameCore.valueForOption(PVJaguarGameCore.forcePalOption).asBool }
    
    @objc var virtualjaguar_mutlithreaded: Bool { PVJaguarGameCore.valueForOption(PVJaguarGameCore.mutliThreadedRenderingOption).asBool }
    @objc var virtualjaguar_double_buffer: Bool {
        get {
            PVJaguarGameCore.valueForOption(PVJaguarGameCore.doubleBufferOption).asBool
        }
        set {
            PVJaguarGameCore.setValue(newValue, forOption: PVJaguarGameCore.doubleBufferOption)
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
