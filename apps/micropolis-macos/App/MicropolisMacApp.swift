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
            ForEach(1...3,id:\.self) { speed in
                Button(["低速","中速","高速"][speed-1]) { Task { await model?.setSpeed(Int32(speed)) } }.disabled(model?.available != true)
            }
            Divider()
            Button("予算・税率…") { model?.panel = .budget }.keyboardShortcut("b").disabled(model?.available != true)
            Button("都市評価…") { model?.panel = .evaluation }.keyboardShortcut("e").disabled(model?.available != true)
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
