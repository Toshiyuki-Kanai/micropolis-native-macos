// SPDX-License-Identifier: GPL-3.0-or-later
// Minimal ownership/import example; no SwiftUI or C++ interoperability required.
import MicropolisNative

struct EngineError: Error, CustomStringConvertible {
    let result: Int32
    var description: String { String(cString: mp_result_string(result)) }
}
func checked(_ result: Int32) throws {
    if result != 0 { throw EngineError(result: result) }
}

// Call on one serial execution context in the app (e.g. an EngineSession actor).
// Never expose the handle to SwiftUI, or destroy it during an in-flight call.
final class EngineSession {
    private let handle: OpaquePointer
    init() throws {
        var created: OpaquePointer?
        try checked(mp_create(&created))
        guard let created else { throw EngineError(result: Int32(MP_INTERNAL_ERROR)) }
        handle = created
    }
    deinit { mp_destroy(handle) }
    func generate(seed: Int32) throws { try checked(mp_generate(handle, seed)) }
    func load(path: String) throws {
        try path.withCString { try checked(mp_load_city(handle, $0)) }
    }
    func step(ticks: UInt32) throws { try checked(mp_step(handle, ticks)) }
    func snapshot() throws -> MPSnapshot {
        var state = MPSnapshot()
        try checked(mp_get_snapshot(handle, &state))
        return state
    }
    func tiles() throws -> [UInt16] {
        var result = [UInt16](repeating: 0, count: Int(MP_TILE_COUNT))
        try result.withUnsafeMutableBufferPointer {
            try checked(mp_copy_map(handle, 0, $0.baseAddress, $0.count))
        }
        return result
    }
    func buildRoad(x: Int32, y: Int32) throws {
        try checked(mp_build(handle, Int32(MP_TOOL_ROAD), x, y))
    }
}

let session = try EngineSession()
if CommandLine.arguments.count > 1 {
    try session.load(path: CommandLine.arguments[1])
} else {
    try session.generate(seed: 12345)
    if let index = try session.tiles().firstIndex(where: { $0 & 0x03ff == 0 }) {
        try session.buildRoad(x: Int32(index % 120), y: Int32(index / 120))
    }
}
let before = try session.snapshot()
try session.step(ticks: 2_000)
let after = try session.snapshot()
print("cityTime: \(before.city_time) -> \(after.city_time), funds: \(after.funds)")
print("tiles: \(try session.tiles().count)")
