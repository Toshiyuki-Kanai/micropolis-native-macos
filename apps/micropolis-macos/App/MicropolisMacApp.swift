// SPDX-License-Identifier: GPL-3.0-or-later
// Native macOS frontend, modified 2026-10-17. Not an EA product.
import SwiftUI

@main struct MicropolisMacApp: App {
    @NSApplicationDelegateAdaptor(CityAppDelegate.self) private var appDelegate
    var body: some Scene {
        // 1.0 owns one editable city per application process.
        Window("Micropolis Native",id:"city") { CityWindow() }
            .defaultLaunchBehavior(.presented)
            .defaultSize(width:1200,height:860)
            .commands { CityCommands() }
        Window("ライセンスとクレジット",id:"licenses") { LicenseView() }
            .defaultSize(width:640,height:540)
    }
}
private struct CityWindow: View {
    @State private var model=CityModel()
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        ContentView(model:model).onAppear { CityWindows.shared.createWindow = { openWindow(id:"city") } }
    }
}
private struct CityCommands: Commands {
    @FocusedValue(\.cityModel) private var focused
    @Environment(\.openWindow) private var openWindow
    private var model: CityModel? { focused ?? CityWindows.shared.entries.values.first?.model }
    private var window: NSWindow? { CityWindows.shared.window(for:model) }
    var body: some Commands {
        CommandGroup(replacing:.newItem) {
            Button("新規都市") {
                if let model { Task { await CityFiles.newCity(model,window:window) } }
                else { openWindow(id:"city") }
            }.keyboardShortcut("n").disabled(model?.documentBusy == true)
            Button("都市を開く…") {
                Task {
                    if let model { await CityFiles.open(model,window:window) }
                    else { await CityFiles.openWithoutCity() }
                }
            }.keyboardShortcut("o").disabled(model?.documentBusy == true)
            Menu("最近使った都市") {
                ForEach(RecentCities.shared.entries) { entry in
                    Button(entry.name) {
                        do {
                            let url=try RecentCities.shared.resolve(entry)
                            if let model { Task { await CityFiles.open(model,window:window,url:url) } }
                            else { CityWindows.shared.openFiles([url]) }
                        } catch {
                            if let model { model.errorMessage="都市へのアクセスを再取得するため「都市を開く」を使ってください。" }
                            else { Task { await CityFiles.openWithoutCity() } }
                        }
                    }.disabled(model?.documentBusy == true)
                }
                Divider(); Button("履歴を消去") { RecentCities.shared.clear() }
            }
        }
        CommandGroup(replacing:.saveItem) {
            Button("保存") { if let model { Task { _ = await CityFiles.save(model,window:window) } } }.keyboardShortcut("s").disabled(model?.available != true)
            Button("別名で保存…") { if let model { Task { _ = await CityFiles.save(model,window:window,saveAs:true) } } }.keyboardShortcut("s",modifiers:[.command,.shift]).disabled(model?.available != true)
        }
        CommandMenu("シミュレーション") {
            Button(model?.started == true ? "停止" : "開始") { Task { await model?.startOrStop() } }.keyboardShortcut("r").disabled(model?.available != true)
            Button(model?.frame?.paused == true ? "再開" : "一時停止") { Task { await model?.togglePause() } }.keyboardShortcut(" ",modifiers:[]).disabled(model?.available != true || model?.started != true)
            Divider()
            ForEach(1...4,id:\.self) { speed in
                Button(["低速","中速","高速","超高速"][speed-1]) { Task { await model?.setSpeed(Int32(speed)) } }.disabled(model?.available != true)
            }
            Divider()
            Button("予算・税率…") { model?.panel = .budget }.keyboardShortcut("b").disabled(model?.available != true)
            Button("都市評価…") { model?.panel = .evaluation }.keyboardShortcut("e").disabled(model?.available != true)
            Button("履歴グラフ…") { model?.panel = .graphs }.keyboardShortcut("g").disabled(model?.available != true)
            Button("都市からのお知らせ…") { model?.panel = .messages }.keyboardShortcut("m").disabled(model?.available != true)
            Divider()
            Menu("難易度") {
                ForEach(0...2,id:\.self) { level in
                    Button(["初級","中級","上級"][level]) { Task { await model?.setOptions(level:Int32(level)) } }
                }
            }.disabled(model?.available != true)
            Toggle("効果音",isOn:Binding(get:{ model?.soundEnabled ?? true },set:{ model?.soundEnabled=$0 }))
            Toggle("自動撤去",isOn:Binding(get:{ model?.frame?.civic.autoBulldoze ?? true },set:{ value in Task { await model?.setOptions(bulldoze:value) } })).disabled(model?.available != true)
            Toggle("自動予算",isOn:Binding(get:{ model?.frame?.details.automaticBudget ?? true },set:{ value in Task { await model?.setOptions(budget:value) } })).disabled(model?.available != true)
        }
        CommandMenu("マップ") {
            ForEach(CityMapLayer.allCases) { layer in Button(layer.title) { model?.mapLayer=layer } }
            Divider()
            Toggle("概観マップ",isOn:Binding(get:{ model?.showOverview ?? true },set:{ model?.showOverview=$0 }))
            Button("拡大") { model?.zoomCommand += 1 }.keyboardShortcut("+")
            Button("縮小") { model?.zoomCommand -= 1 }.keyboardShortcut("-")
        }
        CommandMenu("建設") {
            ForEach(BuildTool.allCases) { tool in
                Button(tool.title) { model?.tool=tool }
                    .keyboardShortcut(tool.rawValue<=9 ? KeyboardShortcut(KeyEquivalent(Character(String(tool.rawValue))),modifiers:[]) : nil)
                    .disabled(model?.acceptsMapInput != true)
            }
        }
        CommandMenu("災害") {
            Toggle("自然災害",isOn:Binding(get:{ model?.frame?.details.disasters ?? false },set:{ value in Task { await model?.setDisasters(value) } })).disabled(model?.available != true)
            Divider()
            ForEach(Disaster.allCases) { disaster in Button(disaster.title+"…") { model?.pendingDisaster=disaster }.disabled(model?.available != true) }
        }
        CommandGroup(after:.appInfo) { Button("ライセンスとクレジット…") { openWindow(id:"licenses") } }
        CommandGroup(replacing:.help) { Button("Micropolisの遊び方") { model?.panel = .guide }.disabled(model == nil) }
    }
}
