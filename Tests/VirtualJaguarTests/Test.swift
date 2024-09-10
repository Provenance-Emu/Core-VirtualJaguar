//
//  Test.swift
//  PVVirtualJaguar
//
//  Created by Joseph Mattiello on 8/5/24.
//

import Testing
import PVEmulatorCore
@testable import libjaguar
@testable import PVVirtualJaguar

struct Test {
    
    let testRomFilename: String = "jag_240p_test_suite_v0.5.1.jag"

    @Test func VirtualJaguarTest() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
        let core = PVJaguarGameCore()
        #expect(core != nil)
    }
    
    @Test func LoadFileTest() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
        let core = PVJaguarGameCore()
        #expect(core != nil)

//        do {
//            try core.loadFile(atPath: testRomFilename)
//        } catch {
//            print("Failed to load file: \(error.localizedDescription)")
//            throw error
//        }
    }
}
