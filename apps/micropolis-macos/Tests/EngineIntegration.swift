// SPDX-License-Identifier: GPL-3.0-or-later
// Compiled with the actual app EngineSession/CityModel, not a second wrapper.
import Foundation

enum VerificationError: Error { case failed(String) }
func expect(_ condition: Bool, _ message: String) throws {
    if !condition { throw VerificationError.failed(message) }
}

@main struct EngineIntegration {
    static func main() async throws {
        let session = EngineSession()
        let initial = try await session.execute(.generate(seed: 12345, speed: 3))
        try expect(initial.tiles.count == 12_000 && initial.paused, "generated map starts paused")
        let dirt = initial.tiles.indices.first {
            initial.tiles[$0] & 0x03ff == 0 && $0 % 120 > 1 && $0 % 120 < 118 && $0 / 120 > 1 && $0 / 120 < 98
        }!
        let x = Int32(dirt % 120), y = Int32(dirt / 120)
        let road = try await session.execute(.build(.road, x: x, y: y))
        try expect(road.funds == initial.funds - 10, "road costs exactly 10")
        try expect((road.tiles[dirt] & 0x03ff) != 0, "road changes clicked tile")
        print("PASS Swift EngineSession road (\(x),\(y)), funds \(initial.funds) -> \(road.funds)")
        var frame = road
        for tool in [BuildTool.residential, .commercial, .industrial] {
            let index = (2..<98).flatMap { row in (2..<118).map { row * 120 + $0 } }.first { index in
                (-1...1).allSatisfy { dy in (-1...1).allSatisfy { dx in
                    frame.tiles[index + dy * 120 + dx] & 0x03ff == 0
                } }
            }!
            let previous = frame
            frame = try await session.execute(.build(tool, x: Int32(index % 120), y: Int32(index / 120)))
            try expect(frame.funds < previous.funds && frame.tiles[index] != previous.tiles[index], "\(tool) footprint and funds")
        }
        frame = try await session.execute(.build(.bulldozer, x: x, y: y))
        try expect(frame.tiles[dirt] != road.tiles[dirt], "bulldozer changes road tile")
        print("PASS Swift residential/commercial/industrial/bulldozer")
        _ = try await session.execute(.paused(false))
        let advanced = try await session.execute(.step(2_000))
        try expect(advanced.time > initial.time, "time advances")
        _ = try await session.execute(.paused(true))
        let paused = try await session.execute(.step(2_000))
        try expect(paused.time == advanced.time, "pause holds time")
        for speed: Int32 in [1, 2, 3] {
            let changed = try await session.execute(.speed(speed))
            try expect(changed.speed == speed && changed.paused, "speed retained while paused")
        }
        _ = try await session.execute(.paused(false))
        let resumed = try await session.execute(.step(2_000))
        try expect(resumed.time > paused.time, "resume advances")
        print("PASS Swift 2000 ticks: \(initial.time) -> \(advanced.time), pause/resume/speeds")
        try geometry()
        try await modelLifecycle()
        try await filesAndStrokes()
        try transformedGeometry()
    }

    static func geometry() throws {
        for size in [CGSize(width: 1200, height: 1000), CGSize(width: 1600, height: 600),
                     CGSize(width: 820, height: 1200), CGSize(width: 937.5, height: 713.25)] {
            let geometry = MapGeometry(size: size)
            for y in 0..<100 {
                for x in 0..<120 {
                    let rect = geometry.tileRect(x: x, y: y)
                    let tile = geometry.tile(at: CGPoint(x: rect.midX, y: rect.midY))
                    try expect(tile?.x == Int32(x) && tile?.y == Int32(y), "resize coordinate roundtrip")
                }
            }
            try expect(geometry.tile(at: CGPoint(x: geometry.rect.maxX, y: geometry.rect.midY)) == nil, "right edge excluded")
            try expect(geometry.tile(at: CGPoint(x: geometry.rect.midX, y: geometry.rect.maxY)) == nil, "bottom edge excluded")
            try expect(geometry.tile(at: CGPoint(x: -1, y: -1)) == nil, "padding excluded")
        }
        try expect(MapGeometry(size: .zero).tile(at: .zero) == nil, "empty viewport")
        print("PASS map hit testing: 48000 tile centers, resized landscape/portrait/fractional viewports, boundaries")
    }

    @MainActor static func modelLifecycle() async throws {
        let model = CityModel()
        await model.newCity()
        try expect(model.available && !model.started && model.frame?.paused == true, "model initially stopped")
        let loop = Task { await model.run() }
        defer { loop.cancel() }
        await model.startOrStop()
        try await Task.sleep(for: .seconds(1))
        let runningTime = model.frame!.time
        try expect(runningTime > 0, "background loop advances")
        await model.togglePause()
        let pausedTime = model.frame!.time
        try await Task.sleep(for: .milliseconds(400))
        try expect(model.frame!.time == pausedTime, "model pause holds time")
        await model.setSpeed(2)
        await model.togglePause()
        try await Task.sleep(for: .seconds(1))
        try expect(model.frame!.time > pausedTime && model.frame!.speed == 2, "model resumes selected speed")
        await model.startOrStop()
        let stoppedTime = model.frame!.time
        try await Task.sleep(for: .milliseconds(400))
        try expect(!model.started && model.frame!.time == stoppedTime, "stop retains city without stepping")
        await model.startOrStop()
        try expect(model.running, "start after stop")
        loop.cancel()
        await loop.value
        print("PASS actual CityModel timer/start/stop/pause/resume/speed/cancellation")
    }
    static func transformedGeometry() throws {
        let size=CGSize(width:900,height:700)
        var viewport=MapViewport()
        let anchor=CGPoint(x:450,y:350)
        let before=MapGeometry(size:size).tile(at:anchor)!
        viewport.magnify(4,at:anchor,size:size)
        viewport.move(CGSize(width:130,height:-90),size:size)
        for outputSize in [size,CGSize(width:1400,height:700),CGSize(width:900,height:1200)] {
            viewport.clamp(outputSize)
            let geometry=MapGeometry(size:outputSize,zoom:viewport.zoom,pan:viewport.pan)
            for y in geometry.rows { for x in geometry.columns {
                let rect=geometry.tileRect(x:x,y:y)
                let p=geometry.tile(at:CGPoint(x:rect.midX,y:rect.midY))
                try expect(p?.x==Int32(x) && p?.y==Int32(y), "pan/zoom/resize inverse mapping")
            } }
        }
        let zoomed=MapGeometry(size:size,zoom:4).tile(at:anchor)!
        try expect(before.x==zoomed.x && before.y==zoomed.y,"zoom anchor preservation")
        let path=MapPath.between(MapPoint(x:2,y:3),MapPoint(x:40,y:21))
        try expect(path.first==MapPoint(x:2,y:3) && path.last==MapPoint(x:40,y:21),"stroke endpoints")
        for i in 1..<path.count {
            try expect(abs(path[i].x-path[i-1].x)+abs(path[i].y-path[i-1].y)==1,"four-connected stroke")
        }
        print("PASS pan/zoom/resize coordinate transforms and four-connected drag path")
    }

    @MainActor static func filesAndStrokes() async throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let output=root.appendingPathComponent("build/gameplay-validation",isDirectory:true)
        let testFile=output.appendingPathComponent("swift-gameplay.cty")
        // Native acceptance fixture starts with a funded empty city; clear map
        // comes from the engine's normal mp_create, never a frontend simulator.
        let source=root.appendingPathComponent("build/native/gameplay-grown.cty")
        for tool in BuildTool.allCases {
            let session=EngineSession()
            let initial=try await session.execute(.load(source))
            if tool == .bulldozer { _ = try await session.execute(.build(.road,x:90,y:60)) }
            let built=try await session.execute(.build(tool,x:90,y:60))
            try expect(built.funds<initial.funds,"Swift tool mapping and cost: \(tool)")
        }
        print("PASS all 15 Swift tool mappings through actual EngineSession")
        let model=CityModel()
        try expect(await model.load(source),"load native growth fixture in actual UI model")
        try expect(!model.dirty && model.frame!.time>0 && model.frame!.populationPending,"load restores time and marks census pending")
        try expect(await model.configureBudget(tax:8,police:0.4,fire:0.6,road:0.8),"UI budget configuration")
        try expect(model.dirty && model.frame!.details.taxRate==8,"budget marks document dirty")
        let original=model.frame!
        model.tool = .road
        model.beginStroke(MapPoint(x:80,y:80)); model.extendStroke(MapPoint(x:90,y:84)); model.extendStroke(MapPoint(x:90,y:84)); model.endStroke()
        try expect(await model.beginDocumentAction(),"file action gate")
        // beginDocumentAction drains accepted input, even a fast drag.
        try expect(model.dirty && model.frame!.funds==original.funds-150,"road drag processes 15 unique cells exactly once before save")
        let saved=model.frame!
        try expect(await model.save(to:testFile),"coordinated atomic save")
        try expect(!model.dirty,"successful save clears dirty")
        model.endDocumentAction()
        let second=CityModel()
        try expect(await second.load(testFile),"reopen saved UI city in a new engine")
        try expect(second.frame!.funds==saved.funds && second.frame!.time==saved.time,"save restores funds/time")
        try expect(second.frame!.details.taxRate==saved.details.taxRate,"save restores tax")
        try expect(abs(second.frame!.details.policeFunding-saved.details.policeFunding)<1/65536,"classic 16.16 funding precision")
        try expect(second.frame!.tiles[80*120+80] & 0x03ff != 0,"save restores road tile")
        await second.startOrStop()
        let loop=Task { await second.run() }
        try await Task.sleep(for:.seconds(1))
        loop.cancel(); await loop.value
        try expect(second.frame!.time>saved.time && second.frame!.population>0 && !second.frame!.populationPending && second.dirty,"continue population growth after reopening")
        let before=try Data(contentsOf:testFile)
        try expect(!(await second.save(to:output)),"save onto a directory fails")
        try expect(second.dirty && !second.engineFailed,"save failure keeps unsaved state and valid engine")
        let after=try Data(contentsOf:testFile)
        try expect(before==after,"save failure protects prior city file")
        var external=before; external[0] ^= 1
        try external.write(to:testFile)
        try expect(!(await second.save(to:testFile)),"external file change refuses stale overwrite")
        try expect(try Data(contentsOf:testFile)==external,"external changes protected")
        try before.write(to:testFile)
        try expect(second.dirty && !second.engineFailed,"conflict retains unsaved city")
        try expect(await second.beginDocumentAction(),"document freeze for wire drag")
        second.endDocumentAction()
        second.tool = .wire
        let beforeWire=second.frame!.funds
        second.beginStroke(MapPoint(x:80,y:85)); second.extendStroke(MapPoint(x:90,y:89)); second.endStroke()
        try expect(await second.beginDocumentAction(),"drain wire input")
        try expect(second.frame!.funds==beforeWire-75 && second.dirty,"wire drag processes 15 connected cells and marks dirty")
        second.endDocumentAction()
        second.errorMessage=nil
        let previous=second.frame!
        try expect(!(await second.load(output.appendingPathComponent("missing.cty"))),"failed load")
        try expect(second.frame!.funds==previous.funds && second.frame!.time==previous.time && second.dirty,"failed load preserves city and dirty state")
        let haight=root.appendingPathComponent("content/micropolis/cities/haight.cty")
        try expect(await second.load(haight),"Swift haight load")
        try expect(second.frame!.funds==1000000 && second.frame!.time==4839,"classic city decoded")
        print("PASS actual UI model: drag queue, file gate, save/recreate/load/continue, failed I/O protection, haight")
    }

}
