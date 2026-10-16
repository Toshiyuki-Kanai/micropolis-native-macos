// SPDX-License-Identifier: GPL-3.0-or-later
// Compiled with the actual app EngineSession/CityModel, not a second wrapper.
import Foundation

enum VerificationError: Error { case failed(String) }
func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw VerificationError.failed(message) }
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
}
