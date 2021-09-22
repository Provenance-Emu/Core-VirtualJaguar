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

		let biosGroup = CoreOption.group(display: CoreOptionValueDisplay(title: "Bios", description: nil),
										 subOptions: [biosOption])

		options.append(biosGroup)
		return options
	}()


	static var biosOption: CoreOption = {
		let biosOption = CoreOption.bool(display: .init(title: "Jaguar BIOS", description: "Use binary Jaguar BIOS file (you need to download this yourself) otherwise use emualted bios.", requiresRestart: true), defaultValue: false)
		return biosOption
	}()

	static var blitterOption: CoreOption = {
		let biosOption = CoreOption.bool(display: .init(title: "Use Fast Blitter", description: "Use fast but maybe more buggy bliter", requiresRestart: true), defaultValue: false)
		return biosOption
	}()
}

@objc extension PVJaguarGameCore {
	public func setUSEBios(_ useBios: Bool) {
		
	}
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
