// SPDX-License-Identifier: GPL-3.0-or-later
// Native macOS frontend, modified version, 2026-10-16.
import MicropolisNative

struct EngineFailure: Error, Sendable, CustomStringConvertible {
    let code: Int32
    var retiresSession: Bool { code == MP_OUT_OF_MEMORY || code == MP_INTERNAL_ERROR }
    var description: String {
        switch code {
        case Int32(MP_NO_FUNDS): "資金が不足しています。"
        case Int32(MP_NEEDS_BULLDOZE): "先に撤去してください。"
        case Int32(MP_CANNOT_BUILD): "この場所には建設できません。"
        case Int32(MP_OUT_OF_MEMORY), Int32(MP_INTERNAL_ERROR):
            "エンジンを継続できません。新規都市を作成してください。"
        default: String(cString: mp_result_string(code))
        }
    }
}

/// One actor owns one city. No C handle or borrowed storage leaves this actor.
/// All C calls, including allocation/destruction, run outside MainActor.
actor EngineSession {
    // Sendable only for actor teardown: never shared or returned to a caller.
    // Its last release destroys the handle after any actor operation finishes.
    private final class OwnedGame: @unchecked Sendable {
        let pointer: OpaquePointer
        init(_ pointer: OpaquePointer) { self.pointer = pointer }
        deinit { mp_destroy(pointer) }
    }
    private var game: OwnedGame?
    private var deliveryRevision: UInt64 = 0

    enum Command: Sendable {
        case generate(seed: Int32, speed: Int32)
        case step(UInt32)
        case paused(Bool)
        case speed(Int32)
        case build(BuildTool, x: Int32, y: Int32)
        case read
    }

    func execute(_ command: Command) throws -> CityFrame {
        if case .generate = command, game == nil {
            var pointer: OpaquePointer?
            try check(mp_create(&pointer))
            guard let pointer else { throw EngineFailure(code: Int32(MP_INTERNAL_ERROR)) }
            game = OwnedGame(pointer)
        }
        guard let pointer = game?.pointer else {
            throw EngineFailure(code: Int32(MP_INTERNAL_ERROR))
        }
        switch command {
        case let .generate(seed, speed):
            try check(mp_generate(pointer, seed))
            try check(mp_set_speed(pointer, speed))
            try check(mp_set_paused(pointer, 1))
        case let .step(ticks): try check(mp_step(pointer, ticks))
        case let .paused(paused): try check(mp_set_paused(pointer, paused ? 1 : 0))
        case let .speed(speed): try check(mp_set_speed(pointer, speed))
        case let .build(tool, x, y): try check(mp_build(pointer, tool.rawValue, x, y))
        case .read: break
        }
        var snapshot = MPSnapshot()
        try check(mp_get_snapshot(pointer, &snapshot))
        var tiles = [UInt16](repeating: 0, count: Int(MP_TILE_COUNT))
        try tiles.withUnsafeMutableBufferPointer {
            try check(mp_copy_map(pointer, 0, $0.baseAddress, $0.count))
        }
        // Monotonic even if a failed engine is destroyed and recreated.
        deliveryRevision += 1
        return CityFrame(tiles: tiles, funds: snapshot.funds, population: snapshot.population,
                         time: snapshot.city_time, year: snapshot.year, month: snapshot.month,
                         speed: snapshot.speed, paused: snapshot.paused != 0,
                         revision: deliveryRevision)
    }

    private func check(_ code: Int32) throws {
        guard code != MP_OK else { return }
        // C API contract: mutation failure may leave partial state. Retire it.
        if code == MP_OUT_OF_MEMORY || code == MP_INTERNAL_ERROR { game = nil }
        throw EngineFailure(code: code)
    }
}
