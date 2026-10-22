// SPDX-License-Identifier: GPL-3.0-or-later
// Gameplay frontend, modified 2026-10-17.
import Foundation
import Observation
import AppKit
import MicropolisNative

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
    var mapLayer: CityMapLayer = .all
    var showOverview = true
    var focusPoint: MapPoint?
    var zoomCommand: Int = 0
    var visibleTiles=CGRect(x:0,y:0,width:120,height:100)
    private(set) var overlayValues: [Int16] = []
    private(set) var histories: [[Int16]] = []
    var historyScale: Int32 = 0
    private(set) var inspection: ZoneInspection?
    private(set) var events: [CityEvent] = []
    var soundEnabled = UserDefaults.standard.object(forKey:"gameSounds") as? Bool ?? true {
        didSet { UserDefaults.standard.set(soundEnabled,forKey:"gameSounds");if !soundEnabled { sounds.values.forEach { $0.stop() } } }
    }
    private var sounds: [Int32:NSSound] = [:]
    var turbo = false
    private var loopCount=0
    private var shakeTask: Task<Void,Never>?
    private(set) var shakeOffset: CGSize = .zero
    private(set) var shaking=false
    private(set) var message = "都市を生成しています…"
    private var lastRevision: UInt64 = 0
    private var queue: [(BuildTool, MapPoint)] = []
    private var strokeTool: BuildTool?
    private var strokeLast: MapPoint?
    private var strokeStart: MapPoint?
    private var strokePoints: [MapPoint]=[]
    private var previewTask: Task<Void,Never>?
    private var previewGeneration: UInt64=0
    private(set) var previewFrame: CityFrame?
    private(set) var previewCost: Int64=0
    private(set) var previewStatus: Int32=0
    var previewInsufficientFunds: Bool { previewStatus == MP_NO_FUNDS }
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
            guard running, !busy, !documentBusy, !draining, strokeTool == nil, !shaking, panel != .budget, panel != .newCity else { continue }
            polling = true
            do {
                loopCount += 1
                let next = try await session.execute(.step(turbo ? 40 : 8))
                if !Task.isCancelled {
                    apply(next); dirty = true
                    if next.civic.budgetPending {
                        message="年次決算の予算を確認してください。"; panel = .budget
                    }
                    if loopCount%5 == 0 { await refreshInspectionData() }
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

    func newCity(seed: Int32? = nil, level: Int32 = 0) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            apply(try await session.execute(.generateLevel(seed: seed ?? Int32.random(in: 0...Int32.max), level: level)))
            queue.removeAll(); cancelStroke(); events=[]; inspection=nil; overlayValues=[]; histories=[]
            shakeTask?.cancel();shakeOffset = .zero;shaking=false
            started = false; engineFailed = false; dirty = false; fileURL = nil
            message = "空き地に道路と地区、発電所・送電線を設置して開始してください。"
        } catch { report(error) }
    }
    @discardableResult func load(_ url: URL) async -> Bool {
        guard !busy else { return false }
        busy = true; defer { busy = false }
        do {
            apply(try await session.execute(.load(url)))
            queue.removeAll(); cancelStroke(); events=[]; inspection=nil; overlayValues=[]; histories=[]
            shakeTask?.cancel();shakeOffset = .zero;shaking=false
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
        if frame?.civic.budgetPending == true { panel = .budget; return }
        if await perform(.paused(started)) {
            started.toggle()
            message = started ? "シミュレーション実行中" : "停止中 — 都市は保持されています。"
        }
    }
    func togglePause() async {
        guard available, started, let frame else { return }
        if frame.civic.budgetPending { panel = .budget; return }
        if await perform(.paused(!frame.paused)) {
            message = self.frame?.paused == true ? "一時停止中" : "再開しました。"
        }
    }
    func setSpeed(_ speed: Int32) async {
        guard available else { return }
        turbo = speed == 4
        _ = await perform(.speed(min(3,speed)))
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
        if tool == .query { await inspect(MapPoint(x:x,y:y)); return }
        _ = await perform(.build(tool, x: x, y: y), changesCity: true)
    }
    func beginStroke(_ point: MapPoint) {
        guard acceptsMapInput, !busy, !draining else { return }
        if tool == .query { Task { await inspect(point) }; return }
        cancelStroke()
        strokeTool=tool;strokeStart=point;strokeLast=point;strokePoints=[point];visited=[point]
        updatePreview()
    }
    func extendStroke(_ point: MapPoint) {
        guard acceptsMapInput, let selected=strokeTool, let start=strokeStart else { return }
        switch selected {
        case .residential,.commercial,.industrial,.park,.bulldozer:
            strokePoints=MapPath.rectangle(start,point,spacing:selected.size)
        case .road,.wire,.railroad:
            for p in MapPath.between(strokeLast ?? point,point) where visited.insert(p).inserted { strokePoints.append(p) }
        default: strokePoints=[point]
        }
        strokeLast=point;updatePreview()
    }
    func endStroke() {
        let points=strokePoints
        if strokeTool != nil, !points.isEmpty { enqueue(points) }
        cancelStroke()
    }
    func cancelStroke() {
        previewTask?.cancel();previewTask=nil;previewGeneration += 1
        strokeTool=nil;strokeStart=nil;strokeLast=nil;strokePoints=[];visited=[];previewFrame=nil;previewCost=0;previewStatus=0
    }
    private func updatePreview() {
        previewTask?.cancel();previewGeneration += 1
        let generation=previewGeneration, points=strokePoints
        guard let selected=strokeTool, var base=frame else { return }
        previewTask=Task {
            do {
                // Debounce pointer events; all work and allocations stay on actor.
                try await Task.sleep(for:.milliseconds(35))
                let result=try await session.edit(selected,points:points,commit:false)
                guard !Task.isCancelled, generation==previewGeneration else { return }
                base.tiles=result.tiles;base.revision=UInt64.max/2+generation
                previewFrame=base;previewCost=result.cost;previewStatus=result.status
            } catch { if !Task.isCancelled { report(error) } }
        }
    }
    private func enqueue(_ points: [MapPoint]) {
        guard let selected=strokeTool else { return }
        for p in points where (0..<120).contains(p.x) && (0..<100).contains(p.y) {
            if queue.count>=12000 { message="建設入力が多すぎます。処理後に再試行してください。"; break }
            queue.append((selected,p))
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
            let batch=Array(queue.prefix(12000).prefix(while: { $0.0 == selected }))
            queue.removeFirst(batch.count)
            busy = true
            do {
                let result = try await session.edit(selected, points:batch.map { $0.1 },commit:true)
                if let frame=result.frame { apply(frame) }
                guard result.status != MP_NO_FUNDS else { message="ストローク全体の資金が不足しています。建設を取り消しました。";busy=false;continue }
                placed += result.placed; rejected += result.rejected
                if result.placed > 0 { dirty = true; if selected != .bulldozer { playSound(1) } }
                else if result.rejected>0 { playSound(2) }
                message = "\(selected.title): \(placed)箇所配置\(rejected > 0 ? "、\(rejected)箇所は配置不可" : "")"
                if placed == 0 { message = EngineFailure(code:result.status).description }
            } catch { report(error); queue.removeAll() }
            busy = false
        }
    }
    func setOptions(level: Int32? = nil, bulldoze: Bool? = nil, budget: Bool? = nil) async {
        guard available, let f=frame else { return }
        _ = await perform(.options(level:level ?? f.civic.difficulty,bulldoze:bulldoze ?? f.civic.autoBulldoze,budget:budget ?? f.details.automaticBudget),changesCity:true)
    }
    func acceptBudget() async {
        guard available, frame?.civic.budgetPending == true else { return }
        if await perform(.acceptBudget,changesCity:true) {
            if started { _ = await perform(.paused(false)) }
            panel=nil
        }
    }
    func inspect(_ point: MapPoint) async {
        guard available else { return }
        busy=true;defer { busy=false }
        do { inspection=try await session.inspect(point);panel = .query }
        catch { report(error) }
    }
    func quote(tax: Int32,police: Float,fire: Float,road: Float) async -> BudgetQuote? {
        do { return try await session.quote(tax:tax,police:police,fire:fire,road:road) }
        catch { report(error);return nil }
    }
    func refreshInspectionData() async {
        guard available else { return }
        busy=true;defer { busy=false }
        do {
            let layer=mapLayer
            if (0...8).contains(layer.rawValue) {
                let values=try await session.overlay(layer)
                if mapLayer == layer { overlayValues=values }
            } else { overlayValues=[] }
            if panel == .graphs { histories=try await session.histories(scale:historyScale) }
        } catch { report(error) }
    }
    private func perform(_ command: EngineSession.Command, changesCity: Bool = false) async -> Bool {
        busy = true; defer { busy = false }
        do { apply(try await session.execute(command)); if changesCity { dirty = true }; return true }
        catch { report(error); return false }
    }
    private func apply(_ next: CityFrame) {
        guard next.revision >= lastRevision else { return }
        let earthquake=next.civic.earthquakeSequence>0 && next.civic.earthquakeSequence != frame?.civic.earthquakeSequence
        frame = next; lastRevision = next.revision
        if earthquake {
            shakeTask?.cancel();shaking=true
            shakeTask=Task {
                for i in 0..<60 {
                    if Task.isCancelled { return }
                    shakeOffset=CGSize(width:i%2==0 ? 4 : -4,height:i%3==0 ? 3 : -3)
                    do { try await Task.sleep(for:.milliseconds(50)) } catch { return }
                }
                shakeOffset = .zero;shaking=false
            }
        }
        events=Array((events+next.civic.events).suffix(128))
        for sound in next.civic.sounds {
            if sound.kind==6 && !visibleTiles.contains(CGPoint(x:Int(sound.x),y:Int(sound.y))) { continue }
            playSound(sound.kind)
        }
        if let event=next.civic.events.last { message=event.text }
    }
    private func playSound(_ kind: Int32) {
        guard soundEnabled else { return }
        let files: [Int32:String]=[1:"build",2:"bop",3:"explosion-high",4:"explosion-low",5:"heavytraffic",6:"honkhonk-low",7:"siren",8:"monster"]
        if sounds[kind] == nil, let file=files[kind],
           let url=Bundle.main.url(forResource:file,withExtension:"wav",subdirectory:"OriginalGraphics/Gameplay") {
            sounds[kind]=NSSound(contentsOf:url,byReference:false)
        }
        // Reuse one instance per effect rather than unbounded audio voices.
        if let sound=sounds[kind], !sound.isPlaying { sound.play() }
    }
    private func report(_ error: Error) {
        errorMessage = String(describing: error)
        if let error = error as? EngineFailure, error.retiresSession {
            engineFailed = true; started = false; queue.removeAll(); endStroke()
        }
    }
}
