// SPDX-License-Identifier: GPL-3.0-or-later
// Native macOS frontend, modified version, 2026-10-17.
import MicropolisNative
import Foundation

struct EngineFailure: Error, Sendable, CustomStringConvertible {
    let code: Int32
    let retiresSession: Bool
    init(code: Int32, sessionRetired: Bool? = nil) {
        self.code=code
        self.retiresSession=sessionRetired ?? (code == MP_OUT_OF_MEMORY || code == MP_INTERNAL_ERROR)
    }
    var description: String {
        switch code {
        case Int32(MP_NO_FUNDS): "資金が不足しています。"
        case Int32(MP_NEEDS_BULLDOZE): "先に撤去してください。"
        case Int32(MP_CANNOT_BUILD): "この場所には建設できません。"
        case Int32(MP_OUT_OF_MEMORY), Int32(MP_INTERNAL_ERROR):
            retiresSession ? "エンジンを継続できません。新規都市を作成してください。" : "都市を置き換えられませんでした。現在の都市は保持されています。"
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
    private var awaitingCensus = false
    private var savedFile: (url: URL, bytes: Data?)?

    enum Command: Sendable {
        case generate(seed: Int32, speed: Int32)
        case step(UInt32)
        case paused(Bool)
        case speed(Int32)
        case build(BuildTool, x: Int32, y: Int32)
        case load(URL)
        case save(URL)
        case budget(tax: Int32, police: Float, fire: Float, road: Float)
        case disasters(Bool)
        case disaster(Int32)
        case read
    }

    func execute(_ command: Command) throws -> CityFrame {
        let needsGame: Bool
        switch command { case .generate, .load: needsGame = true; default: needsGame = false }
        if needsGame, game == nil {
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
            try checkReplacement(mp_generate(pointer, seed))
            try check(mp_set_speed(pointer, speed))
            try check(mp_set_paused(pointer, 1))
            awaitingCensus = false
            savedFile = nil
        case let .step(ticks):
            var before=MPSnapshot()
            try check(mp_get_snapshot(pointer,&before))
            try check(mp_step(pointer,ticks))
            if ticks>=8, before.paused==0, before.speed>0 { awaitingCensus=false }
        case let .paused(paused): try check(mp_set_paused(pointer, paused ? 1 : 0))
        case let .speed(speed): try check(mp_set_speed(pointer, speed))
        case let .build(tool, x, y): try check(mp_build(pointer, tool.rawValue, x, y))
        case let .load(url):
            try checkReplacement(fileOperation(url, writing: false, owner: game!))
            try check(mp_set_paused(pointer, 1))
            awaitingCensus = true
        case let .save(url):
            try check(fileOperation(url, writing: true, owner: game!))
        case let .budget(tax, police, fire, road):
            try check(mp_configure_budget(pointer, tax, police, fire, road))
        case let .disasters(enabled): try check(mp_set_disasters(pointer, enabled ? 1 : 0))
        case let .disaster(kind): try check(mp_trigger_disaster(pointer, kind))
        case .read: break
        }
        return try copyFrame(pointer)
    }

    struct StrokeResult: Sendable {
        let frame: CityFrame
        let placed, rejected: Int
        let firstError: Int32?
    }
    func build(_ tool: BuildTool, points: [MapPoint]) throws -> StrokeResult {
        guard let pointer=game?.pointer else { throw EngineFailure(code: Int32(MP_INTERNAL_ERROR)) }
        var placed=0, rejected=0
        var firstError: Int32?
        // Bound each operation so file commands and polling cannot starve.
        guard points.count <= 64 else { throw EngineFailure(code: Int32(MP_INVALID_ARGUMENT)) }
        for point in points {
            let code=mp_build(pointer, tool.rawValue, point.x, point.y)
            if code == MP_OK { placed += 1 }
            else {
                if EngineFailure(code: code).retiresSession { try check(code) }
                rejected += 1; if firstError == nil { firstError=code }
            }
        }
        return StrokeResult(frame: try copyFrame(pointer), placed: placed, rejected: rejected, firstError: firstError)
    }

    // NSFileCoordinator invokes this accessor synchronously. Retaining the owner
    // keeps the C handle alive; actor state is only touched after coordination.
    private func fileOperation(_ url: URL, writing: Bool, owner: OwnedGame) throws -> Int32 {
        let access=url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let coordinator=NSFileCoordinator()
        var coordinationError: NSError?
        var result=Int32(MP_IO_ERROR)
        let sameFile=savedFile?.url.standardizedFileURL == url.standardizedFileURL
        let expected=sameFile ? savedFile?.bytes : nil
        var newBytes: Data?
        var conflict=false
        var operationError: Error?
        let body: (URL) -> Void = { resolved in
            if writing, sameFile, expected == nil || (try? Data(contentsOf:resolved)) != expected {
                conflict=true; return
            }
            do {
                if writing {
                    let files=FileManager.default
                    var isDirectory: ObjCBool=false
                    let exists=files.fileExists(atPath:resolved.path,isDirectory:&isDirectory)
                    if isDirectory.boolValue { throw CocoaError(.fileWriteInvalidFileName) }
                    // A panel grants the selected file, not arbitrary siblings.
                    // Let macOS provide a same-volume replacement directory so
                    // the C API's sibling temp files stay inside that grant.
                    let staging=try files.url(for:.itemReplacementDirectory,in:.userDomainMask,
                                              appropriateFor:resolved,create:true)
                    defer { try? files.removeItem(at:staging) }
                    let staged=staging.appendingPathComponent("city.cty")
                    result=staged.path.withCString { mp_save_city(owner.pointer,$0) }
                    guard result == MP_OK else { return }
                    let bytes=try Data(contentsOf:staged)
                    if exists {
                        _ = try files.replaceItemAt(resolved,withItemAt:staged)
                    } else {
                        try files.moveItem(at:staged,to:resolved)
                    }
                    newBytes=bytes
                } else {
                    result=resolved.path.withCString { mp_load_city(owner.pointer,$0) }
                    if result == MP_OK { newBytes=try? Data(contentsOf:resolved) }
                }
            } catch {
                operationError=error
            }
        }
        if writing {
            coordinator.coordinate(writingItemAt:url,options:.forReplacing,error:&coordinationError,byAccessor:body)
        } else {
            coordinator.coordinate(readingItemAt:url,options:[],error:&coordinationError,byAccessor:body)
        }
        if let coordinationError { throw coordinationError }
        if let operationError { throw operationError }
        if conflict { throw FileChangedError() }
        if result == MP_OK { savedFile=(url,newBytes) }
        return result
    }

    private func copyFrame(_ pointer: OpaquePointer) throws -> CityFrame {
        var snapshot = MPSnapshot()
        try check(mp_get_snapshot(pointer, &snapshot))
        var tiles = [UInt16](repeating: 0, count: Int(MP_TILE_COUNT))
        try tiles.withUnsafeMutableBufferPointer {
            try check(mp_copy_map(pointer, 0, $0.baseAddress, $0.count))
        }
        var details=MPDetails()
        try check(mp_get_details(pointer, &details))
        // Monotonic even if a failed engine is destroyed and recreated.
        deliveryRevision += 1
        return CityFrame(tiles: tiles, funds: snapshot.funds, population: snapshot.population, populationPending: awaitingCensus,
                         time: snapshot.city_time, year: snapshot.year, month: snapshot.month,
                         speed: snapshot.speed, paused: snapshot.paused != 0,
                         details: CityDetails(details, snapshot: snapshot), revision: deliveryRevision)
    }

    // Generate/load build a replacement before swapping. Even allocation errors
    // preserve the previous city; keep it available for saving or retrying.
    private func checkReplacement(_ code: Int32) throws {
        if code != MP_OK { throw EngineFailure(code:code,sessionRetired:false) }
    }

    private func check(_ code: Int32) throws {
        guard code != MP_OK else { return }
        // C API contract: mutation failure may leave partial state. Retire it.
        if code == MP_OUT_OF_MEMORY || code == MP_INTERNAL_ERROR { game = nil }
        throw EngineFailure(code: code)
    }
}

private struct FileChangedError: Error, Sendable, CustomStringConvertible {
    var description: String { "保存先が外部で変更されています。上書きを防ぐため保存しませんでした。「別名で保存」で別の名前を選んでください。" }
}
