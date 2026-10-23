// SPDX-License-Identifier: GPL-3.0-or-later
// Native macOS frontend, modified 2026-10-17. Not an EA product.
import SwiftUI

@main struct MicropolisMacApp: App {
    @AppStorage("appLanguage") private var language="system"
    @AppStorage("appAppearance") private var appearance="system"
    @NSApplicationDelegateAdaptor(CityAppDelegate.self) private var appDelegate
    var body: some Scene {
        // 1.0 owns one editable city per application process.
        Window("Micropolis Native",id:"city") { CityWindow() }
            .defaultLaunchBehavior(.presented)
            .defaultSize(width:1200,height:860)
            .commands { CityCommands() }
        Window(L("ライセンスとクレジット"),id:"licenses") {
            LicenseView().id(language)
                .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
        }
            .defaultSize(width:640,height:540)
        Settings { AppearanceSettings() }
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
    @AppStorage("appLanguage") private var language="system"
    @FocusedValue(\.cityModel) private var focused
    @Environment(\.openWindow) private var openWindow
    private var model: CityModel? { focused ?? CityWindows.shared.entries.values.first?.model }
    private var window: NSWindow? { CityWindows.shared.window(for:model) }
    var body: some Commands {
        let _ = language
        CommandGroup(replacing:.newItem) {
            Button(L("新規都市")) {
                if let model { Task { await CityFiles.newCity(model,window:window) } }
                else { openWindow(id:"city") }
            }.keyboardShortcut("n").disabled(model?.documentBusy == true)
            Button(L("都市を開く…")) {
                Task {
                    if let model { await CityFiles.open(model,window:window) }
                    else { await CityFiles.openWithoutCity() }
                }
            }.keyboardShortcut("o").disabled(model?.documentBusy == true)
            Menu(L("最近使った都市")) {
                ForEach(RecentCities.shared.entries) { entry in
                    Button(entry.name) {
                        do {
                            let url=try RecentCities.shared.resolve(entry)
                            if let model { Task { await CityFiles.open(model,window:window,url:url) } }
                            else { CityWindows.shared.openFiles([url]) }
                        } catch {
                            if let model { model.errorMessage=L("都市へのアクセスを再取得するため「都市を開く」を使ってください。") }
                            else { Task { await CityFiles.openWithoutCity() } }
                        }
                    }.disabled(model?.documentBusy == true)
                }
                Divider(); Button(L("履歴を消去")) { RecentCities.shared.clear() }
            }
        }
        CommandGroup(replacing:.saveItem) {
            Button(L("保存")) { if let model { Task { _ = await CityFiles.save(model,window:window) } } }.keyboardShortcut("s").disabled(model?.available != true)
            Button(L("別名で保存…")) { if let model { Task { _ = await CityFiles.save(model,window:window,saveAs:true) } } }.keyboardShortcut("s",modifiers:[.command,.shift]).disabled(model?.available != true)
        }
        CommandMenu(L("シミュレーション")) {
            Button(model?.started == true ? L("停止") : L("開始")) { Task { await model?.startOrStop() } }.keyboardShortcut("r").disabled(model?.available != true)
            Button(model?.frame?.paused == true ? L("再開") : L("一時停止")) { Task { await model?.togglePause() } }.keyboardShortcut(" ",modifiers:[]).disabled(model?.available != true || model?.started != true)
            Divider()
            ForEach(1...4,id:\.self) { speed in
                Button([L("低速"),L("中速"),L("高速"),L("超高速")][speed-1]) { Task { await model?.setSpeed(Int32(speed)) } }.disabled(model?.available != true)
            }
            Divider()
            Button(L("予算・税率…")) { model?.panel = .budget }.keyboardShortcut("b").disabled(model?.available != true)
            Button(L("都市評価…")) { model?.panel = .evaluation }.keyboardShortcut("e").disabled(model?.available != true)
            Button(L("履歴グラフ…")) { model?.panel = .graphs }.keyboardShortcut("g").disabled(model?.available != true)
            Button(L("都市からのお知らせ…")) { model?.panel = .messages }.keyboardShortcut("m").disabled(model?.available != true)
            Divider()
            Menu(L("難易度")) {
                ForEach(0...2,id:\.self) { level in
                    Button([L("初級"),L("中級"),L("上級")][level]) { Task { await model?.setOptions(level:Int32(level)) } }
                }
            }.disabled(model?.available != true)
            Toggle(L("効果音"),isOn:Binding(get:{ model?.soundEnabled ?? true },set:{ model?.soundEnabled=$0 }))
            Toggle(L("自動撤去"),isOn:Binding(get:{ model?.frame?.civic.autoBulldoze ?? true },set:{ value in Task { await model?.setOptions(bulldoze:value) } })).disabled(model?.available != true)
            Toggle(L("自動予算"),isOn:Binding(get:{ model?.frame?.details.automaticBudget ?? true },set:{ value in Task { await model?.setOptions(budget:value) } })).disabled(model?.available != true)
        }
        CommandMenu(L("マップ")) {
            ForEach(CityMapLayer.allCases) { layer in Button(layer.title) { model?.mapLayer=layer } }
            Divider()
            Toggle(L("概観マップ"),isOn:Binding(get:{ model?.showOverview ?? true },set:{ model?.showOverview=$0 }))
            Button(L("拡大")) { model?.zoomCommand += 1 }.keyboardShortcut("+")
            Button(L("縮小")) { model?.zoomCommand -= 1 }.keyboardShortcut("-")
        }
        CommandMenu(L("建設")) {
            ForEach(BuildTool.allCases) { tool in
                Button(tool.title) { model?.tool=tool }
                    .keyboardShortcut(tool.rawValue<=9 ? KeyboardShortcut(KeyEquivalent(Character(String(tool.rawValue))),modifiers:[]) : nil)
                    .disabled(model?.acceptsMapInput != true)
            }
        }
        CommandMenu(L("災害")) {
            Toggle(L("自然災害"),isOn:Binding(get:{ model?.frame?.details.disasters ?? false },set:{ value in Task { await model?.setDisasters(value) } })).disabled(model?.available != true)
            Divider()
            ForEach(Disaster.allCases) { disaster in Button(disaster.title+"…") { model?.pendingDisaster=disaster }.disabled(model?.available != true) }
        }
        CommandGroup(after:.appInfo) { Button(L("ライセンスとクレジット…")) { openWindow(id:"licenses") } }
        CommandGroup(replacing:.help) { Button(L("Micropolisの遊び方")) { model?.panel = .guide }.disabled(model == nil) }
    }
}
