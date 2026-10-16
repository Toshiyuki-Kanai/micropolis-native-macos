// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Observation

@Observable @MainActor
final class CityModel {
    private let session = EngineSession()
    private(set) var frame: CityFrame?
    private(set) var busy = false
    private(set) var started = false
    private(set) var engineFailed = false
    var tool: BuildTool = .road
    var errorMessage: String?
    private(set) var message = "都市を生成しています…"
    private var lastRevision: UInt64 = 0

    var available: Bool { frame != nil && !busy && !engineFailed }
    var running: Bool { started && frame?.paused == false && !engineFailed }

    /// View lifetime owns this cancellable loop. No catch-up bursts or queued timers.
    func run() async {
        if frame == nil { await newCity() }
        while !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(100)) }
            catch { return }
            guard running, !busy else { continue }
            do {
                let next = try await session.execute(.step(8))
                if !Task.isCancelled { apply(next) }
            } catch { report(error) }
        }
    }

    func newCity() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let next = try await session.execute(.generate(seed: Int32.random(in: 0...Int32.max), speed: 3))
            apply(next)
            started = false
            engineFailed = false
            message = "新しい都市です。ツールを選び、マップをクリックしてください。"
        } catch { report(error) }
    }

    func startOrStop() async {
        guard available else { return }
        if await perform(.paused(started)) {
            started.toggle()
            message = started ? "シミュレーションを開始しました。" : "停止しました。都市は保持されています。"
        }
    }

    func togglePause() async {
        guard available, started, let frame else { return }
        if await perform(.paused(!frame.paused)) {
            message = self.frame?.paused == true ? "一時停止中です。" : "再開しました。"
        }
    }

    func setSpeed(_ speed: Int32) async {
        guard available else { return }
        _ = await perform(.speed(speed))
    }

    func build(x: Int32, y: Int32) async {
        guard available else { return }
        let selected = tool
        if await perform(.build(selected, x: x, y: y)) {
            message = "\(selected.title) (\(x), \(y)) — 完了しました。"
        }
    }

    private func perform(_ command: EngineSession.Command) async -> Bool {
        busy = true
        defer { busy = false }
        do { apply(try await session.execute(command)); return true }
        catch { report(error); return false }
    }

    private func apply(_ next: CityFrame) {
        // An awaited timer result must not overwrite a newer user operation.
        guard next.revision >= lastRevision else { return }
        frame = next
        lastRevision = next.revision
    }

    private func report(_ error: Error) {
        errorMessage = String(describing: error)
        if let error = error as? EngineFailure, error.retiresSession {
            engineFailed = true
            started = false
        }
    }
}
