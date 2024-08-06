//
//  Test.swift
//  PVVirtualJaguar
//
//  Created by Joseph Mattiello on 8/5/24.
//

import Testing
@testable import PVVirtualJaguar;
@testable import PVVirtualJaguarSwift;

struct Test {

    @Test func VirtualJaguarTest() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
        let core = PVJaguarGameCore()
        await #expect(core != nil)
//        core.jagVideoBuffer = .init(repeating: 0, count: 1024 * 768 * 4)
//        #expect(core.jagVideoBuffer != nil)
    }
}
