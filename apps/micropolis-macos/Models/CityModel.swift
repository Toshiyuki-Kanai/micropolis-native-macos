// SPDX-License-Identifier: GPL-3.0-or-later
// Gameplay frontend, modified 2026-10-17.
import Foundation
import Observation

@Observable @MainActor
final class CityModel {
    private let session = EngineSession()
    private(set) var frame: CityFrame?
    private(set) var busy = false
    private(set) var polling = false
    private(set) var started = false
    private(set) var engineFailed = false
    private(set) var dirty = false
    private(set) var fileURL: URL?
    private(set) var documentBusy = false
    var tool: BuildTool = .road
    var errorMessage: String?
    var panel: CityPanel?
    var pendingDisaster: Disaster?
    var powerOverlay = false
    private(set) var message = "都市を生成しています…"
    private var lastRevision: UInt64 = 0
    private var queue: [(BuildTool, MapPoint)] = []
    private var strokeTool: BuildTool?
    private var strokeLast: MapPoint?
    private var visited: Set<MapPoint> = []
    private var draining = false

    var available: Bool { frame != nil && !busy && !documentBusy && !engineFailed }
    var acceptsMapInput: Bool { frame != nil && !documentBusy && !engineFailed }
    var running: Bool { started && frame?.paused == false && !engineFailed }
    var title: String { fileURL?.deletingPathExtension().lastPathComponent ?? "名称未設定" }

    func run() async {
        if frame == nil { await newCity() }
        while !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            guard running, !busy, !documentBusy, !draining else { continue }
            polling = true
            do {
                let next = try await session.execute(.step(8))
                if !Task.isCancelled {
                    apply(next); dirty = true
                    if !next.details.automaticBudget { message = "エンジンが資金不足を検知しました。予算・税率を見直してください。" }
                }
            } catch { report(error) }
            polling = false
        }
    }

    /// File actions freeze input/ticks, drain already accepted edits, then prompt.
    func beginDocumentAction() async -> Bool {
        guard !documentBusy else { return false }
        documentBusy = true
        panel=nil; pendingDisaster=nil; errorMessage=nil
        endStroke()
        while busy || polling || draining { try? await Task.sleep(for: .milliseconds(20)) }
        return true
    }
    func endDocumentAction() { documentBusy = false }

    func newCity() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            apply(try await session.execute(.generate(seed: Int32.random(in: 0...Int32.max), speed: 3)))
            queue.removeAll(); endStroke()
            started = false; engineFailed = false; dirty = false; fileURL = nil
            message = "空き地に道路と地区、発電所・送電線を設置して開始してください。"
        } catch { report(error) }
    }
    @discardableResult func load(_ url: URL) async -> Bool {
        guard !busy else { return false }
        busy = true; defer { busy = false }
        do {
            apply(try await session.execute(.load(url)))
            queue.removeAll(); endStroke()
            started = false; engineFailed = false; fileURL = url; dirty = false
            message = "\(url.lastPathComponent)を開きました。開始で続きを進めます。"
            return true
        } catch { report(error); return false }
    }
    @discardableResult func save(to url: URL) async -> Bool {
        guard !busy, !engineFailed else { return false }
        busy = true; defer { busy = false }
        do {
            apply(try await session.execute(.save(url)))
            fileURL = url; dirty = false; message = "\(url.lastPathComponent)を保存しました。"
            return true
        } catch { report(error); return false }
    }

    func startOrStop() async {
        guard available else { return }
        if await perform(.paused(started)) {
            started.toggle()
            message = started ? "シミュレーション実行中" : "停止中 — 都市は保持されています。"
        }
    }
    func togglePause() async {
        guard available, started, let frame else { return }
        if await perform(.paused(!frame.paused)) {
            message = self.frame?.paused == true ? "一時停止中" : "再開しました。"
        }
    }
    func setSpeed(_ speed: Int32) async {
        guard available else { return }
        _ = await perform(.speed(speed))
    }
    @discardableResult func configureBudget(tax: Int32, police: Float, fire: Float, road: Float) async -> Bool {
        guard available else { return false }
        return await perform(.budget(tax: tax, police: police, fire: fire, road: road), changesCity: true)
    }
    func setDisasters(_ enabled: Bool) async {
        guard available else { return }
        _ = await perform(.disasters(enabled), changesCity: true)
    }
    func trigger(_ disaster: Disaster) async {
        guard available else { return }
        _ = await perform(.disaster(disaster.rawValue), changesCity: true)
    }
    func build(x: Int32, y: Int32) async {
        guard available else { return }
        _ = await perform(.build(tool, x: x, y: y), changesCity: true)
    }
    func beginStroke(_ point: MapPoint) {
        guard acceptsMapInput else { return }
        strokeTool = tool; strokeLast = point; visited = []
        enqueue([point])
    }
    func extendStroke(_ point: MapPoint) {
        guard acceptsMapInput, let selected=strokeTool, selected.continuous else { return }
        enqueue(MapPath.between(strokeLast ?? point, point)); strokeLast = point
    }
    func endStroke() { strokeTool = nil; strokeLast = nil; visited = [] }
    private func enqueue(_ points: [MapPoint]) {
        guard let selected=strokeTool else { return }
        for p in points where (0..<120).contains(p.x) && (0..<100).contains(p.y) {
            if queue.count>=12000 { message="建設入力が多すぎます。処理後に再試行してください。"; break }
            if visited.insert(p).inserted { queue.append((selected,p)) }
        }
        guard !draining else { return }
        draining = true
        Task { await drain() }
    }
    private func drain() async {
        defer { draining = false }
        var placed=0, rejected=0
        while !queue.isEmpty, !engineFailed {
            if busy { try? await Task.sleep(for: .milliseconds(10)); continue }
            let selected=queue[0].0
            let batch=Array(queue.prefix(64).prefix(while: { $0.0 == selected }))
            queue.removeFirst(batch.count)
            busy = true
            do {
                let result = try await session.build(selected, points: batch.map { $0.1 })
                apply(result.frame); placed += result.placed; rejected += result.rejected
                if result.placed > 0 { dirty = true }
                message = "\(selected.title): \(placed)箇所配置\(rejected > 0 ? "、\(rejected)箇所は配置不可" : "")"
                if placed == 0, let code=result.firstError { message = EngineFailure(code: code).description }
            } catch { report(error); queue.removeAll() }
            busy = false
        }
    }
    private func perform(_ command: EngineSession.Command, changesCity: Bool = false) async -> Bool {
        busy = true; defer { busy = false }
        do { apply(try await session.execute(command)); if changesCity { dirty = true }; return true }
        catch { report(error); return false }
    }
    private func apply(_ next: CityFrame) {
        guard next.revision >= lastRevision else { return }
        frame = next; lastRevision = next.revision
    }
    private func report(_ error: Error) {
        errorMessage = String(describing: error)
        if let error = error as? EngineFailure, error.retiresSession {
            engineFailed = true; started = false; queue.removeAll(); endStroke()
        }
    }
}
