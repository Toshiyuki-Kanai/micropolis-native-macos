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
        case Int32(MP_BUDGET_PENDING): "年次予算を承認してから保存してください。都市の状態は保持されています。"
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
        case options(level: Int32, bulldoze: Bool, budget: Bool)
        case acceptBudget
        case generateLevel(seed: Int32, level: Int32)
        case read
    }

    func execute(_ command: Command) throws -> CityFrame {
        let needsGame: Bool
        switch command { case .generate, .generateLevel, .load: needsGame = true; default: needsGame = false }
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
        case let .generateLevel(seed, level):
            try checkReplacement(mp_generate_level(pointer,seed,level))
            try check(mp_set_speed(pointer,3)); try check(mp_set_paused(pointer,1))
            awaitingCensus=false; savedFile=nil
        case let .options(level, bulldoze, budget):
            try check(mp_set_options(pointer,level,bulldoze ? 1 : 0,budget ? 1 : 0))
        case .acceptBudget: try check(mp_accept_budget(pointer))
        case let .step(ticks):
            var before=MPSnapshot()
            try check(mp_get_snapshot(pointer,&before))
            try check(mp_step(pointer,ticks))
            // Exactly one visual frame per UI update, independent of the tick
            // batch size. The C++ core owns animation IDs and status flags.
            if ticks>0 { try check(mp_animate_tiles(pointer)) }
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
        // Sound delivery is polled into bounded copies; playback preference is
        // frontend-local (MicropolisJ likewise ignores the saved sound bit).
        try check(mp_set_sound_events(pointer,1))
        return try copyFrame(pointer)
    }

    struct EditResult: Sendable {
        let tiles: [UInt16]
        let cost: Int64
        let placed, rejected: Int
        let status: Int32
        let frame: CityFrame?
    }
    func edit(_ tool: BuildTool, points: [MapPoint], commit: Bool) throws -> EditResult {
        guard let pointer=game?.pointer else { throw EngineFailure(code:Int32(MP_INTERNAL_ERROR)) }
        var coordinates=points.map { MPPoint(x:$0.x,y:$0.y) }
        var tiles=[UInt16](repeating:0,count:12000), edit=MPEdit()
        let code=coordinates.withUnsafeMutableBufferPointer { p in
            tiles.withUnsafeMutableBufferPointer { t in
                mp_edit_stroke(pointer,tool.rawValue,p.baseAddress,p.count,commit ? 1 : 0,t.baseAddress,t.count,&edit)
            }
        }
        if commit { try check(code) } else { try checkReplacement(code) }
        return EditResult(tiles:tiles,cost:edit.cost,placed:Int(edit.placed),rejected:Int(edit.rejected),status:edit.status,frame:commit ? try copyFrame(pointer) : nil)
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
                    var auxiliary=[UInt16](repeating:0,count:12000)
                    result=auxiliary.withUnsafeMutableBufferPointer { mp_copy_map(owner.pointer,1,$0.baseAddress,$0.count) }
                    guard result == MP_OK else { return }
                    let classic=auxiliary.allSatisfy { $0==0 }
                    result=staged.path.withCString { classic ? mp_save_city_classic(owner.pointer,$0) : mp_save_city(owner.pointer,$0) }
                    guard result == MP_OK else { return }
                    let bytes=try Data(contentsOf:staged)
                    if exists {
                        _ = try files.replaceItemAt(resolved,withItemAt:staged)
                    } else {
                        try files.moveItem(at:staged,to:resolved)
                    }
                    newBytes=bytes
                } else {
                    // MicropolisJ also accepts classic Mac cities with a 128-byte
                    // preamble. Normalize a private copy, preserving the source.
                    if try resolved.resourceValues(forKeys:[.fileSizeKey]).fileSize == 27248 {
                        let original=try Data(contentsOf:resolved)
                        let staging=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
                        try FileManager.default.createDirectory(at:staging,withIntermediateDirectories:false)
                        defer { try? FileManager.default.removeItem(at:staging) }
                        let normalized=staging.appendingPathComponent("classic.cty")
                        try Data(original.dropFirst(128)).write(to:normalized)
                        result=normalized.path.withCString { mp_load_city(owner.pointer,$0) }
                        if result == MP_OK { newBytes=original }
                    } else {
                        result=resolved.path.withCString { mp_load_city(owner.pointer,$0) }
                        if result == MP_OK { newBytes=try? Data(contentsOf:resolved) }
                    }
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
        var result = CityFrame(tiles: tiles, funds: snapshot.funds, population: snapshot.population, populationPending: awaitingCensus,
                         time: snapshot.city_time, year: snapshot.year, month: snapshot.month,
                         speed: snapshot.speed, paused: snapshot.paused != 0,
                         details: CityDetails(details, snapshot: snapshot), revision: deliveryRevision)
        var options=MPOptions(); try check(mp_get_options(pointer,&options))
        result.civic.difficulty=options.difficulty; result.civic.autoBulldoze=options.auto_bulldoze != 0
        result.civic.budgetPending=options.budget_pending != 0
        result.civic.earthquakeSequence=options.earthquake_sequence
        result.civic.populationDelta=options.population_delta; result.civic.scoreDelta=options.score_delta
        let ids=[options.problem_ids.0,options.problem_ids.1,options.problem_ids.2,options.problem_ids.3]
        let votes=[options.problem_votes.0,options.problem_votes.1,options.problem_votes.2,options.problem_votes.3]
        result.civic.problems=zip(ids,votes).map { (id:$0.0,votes:$0.1) }
        var events=[MPEvent](repeating:MPEvent(),count:128), count=0
        try events.withUnsafeMutableBufferPointer { try check(mp_poll_events(pointer,$0.baseAddress,$0.count,&count)) }
        result.civic.events=events.prefix(count).map { CityEvent(number:$0.message,x:$0.x,y:$0.y,important:$0.important != 0) }
        var spriteCount=0
        let spriteStatus=mp_copy_sprites(pointer,nil,0,&spriteCount)
        if spriteStatus != MP_BUFFER_TOO_SMALL { try check(spriteStatus) }
        var sprites=[MPSprite](repeating:MPSprite(),count:spriteCount)
        try sprites.withUnsafeMutableBufferPointer { try check(mp_copy_sprites(pointer,$0.baseAddress,$0.count,&spriteCount)) }
        result.civic.sprites=sprites.map { CitySprite(kind:$0.type,frame:$0.frame,x:$0.x,y:$0.y,width:$0.width,height:$0.height,offsetX:$0.x_offset,offsetY:$0.y_offset) }
        var sounds=[MPSound](repeating:MPSound(),count:32),soundCount=0
        try sounds.withUnsafeMutableBufferPointer { try check(mp_poll_sounds(pointer,$0.baseAddress,$0.count,&soundCount)) }
        result.civic.sounds=sounds.prefix(soundCount).map { (kind:$0.kind,x:$0.x,y:$0.y) }
        var finances=[MPFinance](repeating:MPFinance(),count:120),financeCount=0
        try finances.withUnsafeMutableBufferPointer { try check(mp_copy_finances(pointer,$0.baseAddress,$0.count,&financeCount)) }
        result.civic.finances=finances.prefix(financeCount).map { CityFinance(time:$0.city_time,funds:$0.funds,income:$0.tax_income,operating:$0.operating_expenses,capital:$0.capital_expenses) }
        return result
    }

    func quote(tax: Int32,police: Float,fire: Float,road: Float) throws -> BudgetQuote {
        guard let pointer=game?.pointer else { throw EngineFailure(code:Int32(MP_INVALID_ARGUMENT)) }
        var q=MPBudgetQuote()
        try checkReplacement(mp_quote_budget(pointer,tax,police,fire,road,&q))
        return BudgetQuote(income:q.income,roadRequest:q.road_request,fireRequest:q.fire_request,policeRequest:q.police_request,
                           roadFunded:q.road_funded,fireFunded:q.fire_funded,policeFunded:q.police_funded,balance:q.balance)
    }
    func overlay(_ layer: CityMapLayer) throws -> [Int16] {
        guard let pointer=game?.pointer else { return [] }
        var values=[Int16](repeating:0,count:12000)
        try values.withUnsafeMutableBufferPointer { try check(mp_copy_overlay(pointer,layer.rawValue,$0.baseAddress,$0.count)) }
        return values
    }
    func histories(scale: Int32) throws -> [[Int16]] {
        guard let pointer=game?.pointer else { return [] }
        return try (0..<6).map { kind in
            var values=[Int16](repeating:0,count:120)
            try values.withUnsafeMutableBufferPointer { try check(mp_copy_history(pointer,Int32(kind),scale,$0.baseAddress,$0.count)) }
            return values
        }
    }
    func inspect(_ point: MapPoint) throws -> ZoneInspection {
        guard let pointer=game?.pointer else { throw EngineFailure(code:Int32(MP_INVALID_ARGUMENT)) }
        var q=MPInspection();try check(mp_inspect(pointer,point.x,point.y,&q))
        return ZoneInspection(category:q.category,density:q.density,land:q.land,crime:q.crime,pollution:q.pollution,growth:q.growth,x:q.x,y:q.y)
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
