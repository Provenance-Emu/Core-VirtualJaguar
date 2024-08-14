//
//  PVJaguarGameCore.swift
//  PVVirtualJaguar
//
//  Created by Joseph Mattiello on 5/21/24.
//  Copyright © 2024 Provenance EMU. All rights reserved.
//

import Foundation
import PVCoreBridge
import GameController
import PVLogging
import PVAudio
public import PVEmulatorCore
import PVVirtualJaguarC
import libjaguar

@objc
@objcMembers
open class PVJaguarGameCore: PVEmulatorCore, @unchecked Sendable {
    
//    public var core: any PVCoreBridge.ObjCBridgedCoreBridge
    

//    @MainActor
    @objc public var jagVideoBuffer: UnsafeMutablePointer<JagBuffer>?
//    @MainActor
    @objc public var videoWidth: UInt32 = UInt32(VIDEO_WIDTH)
//    @MainActor
    @objc public var videoHeight: Int = Int(VIDEO_HEIGHT)
//    @MainActor
    @objc public var frameTime: Float = 0.0
    @objc public var multithreaded: Bool { virtualjaguar_mutlithreaded }

    // MARK: Audio
    @objc public override var sampleRate: Double { Double(AUDIO_SAMPLERATE) }
//    @MainActor
    @objc public var audioBufferSize: Int16 = 0

    // MARK: Queues
    @objc  public let audioQueue: DispatchQueue = .init(label: "com.provenance.jaguar.audio", qos: .userInteractive, autoreleaseFrequency: .inherit)
    @objc public let videoQueue: DispatchQueue = .init(label: "com.provenance.jaguar.video", qos: .userInteractive, autoreleaseFrequency: .inherit)
    @objc public let renderGroup: DispatchGroup = .init()

    @objc  public let waitToBeginFrameSemaphore: DispatchSemaphore = .init(value: 0)

    // MARK: Controls
//    @MainActor
    @objc public init(valueChangedHandler: GCExtendedGamepadValueChangedHandler? = nil) {
        self.valueChangedHandler = valueChangedHandler
//        self.core = PVJaguarCoreBridge(valueChangedHandler: valueChangedHandler)
    }

//    @MainActor
    @objc public var valueChangedHandler: GCExtendedGamepadValueChangedHandler? = nil

    // MARK: Video

    @objc public override var isDoubleBuffered: Bool {
        // TODO: Fix graphics tearing when this is on
        // return self.virtualjaguar_double_buffer
        return false
    }

//    @MainActor
    @objc public override var videoBufferSize: CGSize {
        return .init(width: Int(videoWidth), height: videoHeight)
    }

//    @MainActor
    @objc public override var aspectSize: CGSize {
        return .init(width: Int(videoWidth), height: videoHeight)
    }

    // MARK: Lifecycle

    @objc public required init() {
        super.init()
    }
}

@objc
public extension PVJaguarGameCore {

    @objc(BUTTON_SWIFT) enum BUTTON: Int {
        case u = 0
        case d = 1
        case l = 2
        case r = 3
        case s = 4
        case seven = 5
        case four = 6
        case one = 7
        case zero = 8
        case eight = 9
        case five = 10
        case two = 11
        case d_ = 12
        case nine = 13
        case six = 14
        case three = 15
        case a = 16
        case b = 17
        case c = 18
        case option = 19
        case pause = 20

        static var first: BUTTON { u }
        static var last: BUTTON { .pause }
    }

    @objc func getIndexForPVJaguarButton(_ btn: PVJaguarButton) -> Int {
        switch btn {
        case .up:
            return BUTTON.u.rawValue
        case .down:
            return BUTTON.d.rawValue
        case .left:
            return BUTTON.l.rawValue
        case .right:
            return BUTTON.r.rawValue
        case .a:
            return BUTTON.a.rawValue
        case .b:
            return BUTTON.b.rawValue
        case .c:
            return BUTTON.c.rawValue
        case .pause:
            return BUTTON.pause.rawValue
        case .option:
            return BUTTON.option.rawValue
        case .button1:
            return BUTTON.one.rawValue
        case .button2:
            return BUTTON.two.rawValue
        case .button3:
            return BUTTON.three.rawValue
        case .button4:
            return BUTTON.four.rawValue
        case .button5:
            return BUTTON.five.rawValue
        case .button6:
            return BUTTON.six.rawValue
        case .button7:
            return BUTTON.seven.rawValue
        case .button8:
            return BUTTON.eight.rawValue
        case .button9:
            return BUTTON.nine.rawValue
        case .button0:
            return BUTTON.zero.rawValue
        case .asterisk:
            return BUTTON.s.rawValue
        case .pound:
            return BUTTON.d_.rawValue
        case .count:
            return -1
        }
    }


    @objc func didReleaseJaguarButton(_ button: PVJaguarButton, forPlayer player: Int) {

        // Function to set a value at a specific index
        func setButtonValue(_ player: UInt32, at index: Int32, to value: UInt8) {
            guard index >= 0 && index < 21 else {
                print("Index out of bounds")
                return
            }

            SetJoyPadValue(player, index, value)
        }

        let index = getIndexForPVJaguarButton(button)
        setButtonValue(UInt32(player), at: Int32(index), to: 0x00)
     }
}
