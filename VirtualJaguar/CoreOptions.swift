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

		let biosGroup = CoreOption.group(display: CoreOptionValueDisplay(title: "BIOS", description: nil),
										 subOptions: [biosOption])
        
        let hacksGroup = CoreOption.group(display: CoreOptionValueDisplay(title: "Hacks", description: "Performance hacks that work with some games better than others."),
                                         subOptions: [blitterOption, doomResHackOption, forcePalOption])

		options.append(biosGroup)
        options.append(hacksGroup)

		return options
	}()


	static var biosOption: CoreOption = {
		let biosOption = CoreOption.bool(display: .init(title: "Jaguar BIOS", description: "Use binary Jaguar BIOS file (you need to download this yourself) otherwise use emualted bios.", requiresRestart: true), defaultValue: false)
		return biosOption
	}()

	static var blitterOption: CoreOption = {
		let blitterOption = CoreOption.bool(display: .init(title: "Use Fast Blitter", description: "Use fast but maybe more buggy bliter", requiresRestart: true), defaultValue: false)
		return blitterOption
	}()
    
    static var doomResHackOption: CoreOption = {
        let doomResHackOption = CoreOption.bool(display: .init(title: "DOOM Res Hack", description: "For DOOM", requiresRestart: true), defaultValue: false)
        return doomResHackOption
    }()
    
    static var forcePalOption: CoreOption = {
        let forcePalOption = CoreOption.bool(display: .init(title: "Force PAL", description: "Force PAL mode over NTSC. May fix ROMs that are misdetected or coded for NTSC.", requiresRestart: true), defaultValue: false)
        return forcePalOption
    }()
}

@objc extension PVJaguarGameCore {
	public func setUSEBios(_ useBios: Bool) {
		
	}
}

@objc extension PVJaguarGameCore {
    @objc var virtualjaguar_bios: Bool { PVJaguarGameCore.valueForOption(Bool.self, "Jaguar BIOS") ?? false }
    @objc var virtualjaguar_usefastblitter: Bool { PVJaguarGameCore.valueForOption(Bool.self, "Use Fast Blitter") ?? false }
    @objc var virtualjaguar_doom_res_hack: Bool { PVJaguarGameCore.valueForOption(Bool.self, "DOOM Res Hack") ?? false }
    @objc var virtualjaguar_pal: Bool { PVJaguarGameCore.valueForOption(Bool.self, "Force PAL") ?? false }
}


extension PVJaguarGameCore: CoreActions {
	public var coreActions: [CoreAction]? {
		let bios = CoreAction(title: "Use Jaguar BIOS", options: nil)
		let fastBlitter =  CoreAction(title: "Use fast blitter", options:nil)
		return [bios, fastBlitter]
	}

	public func selected(action: CoreAction) {
		DLOG("\(action.title), \(String(describing: action.options))")
	}
}
