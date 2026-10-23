// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct ContentView: View {
    @Bindable var model: CityModel
    @AppStorage("appAppearance") private var appearance="system"
    @AppStorage("appLanguage") private var language="system"
    @State private var availableWidth: CGFloat = 950
    @State private var columns: NavigationSplitViewVisibility = .all
    private var window: NSWindow? { CityWindows.shared.window(for:model) }
    var body: some View {
        NavigationSplitView(columnVisibility:$columns) {
            CitySidebar(model:model)
                .navigationSplitViewColumnWidth(min:210,ideal:260,max:max(210,min(availableWidth*0.75,availableWidth-320)))
                .navigationTitle("")
        } detail: {
            VStack(spacing:0) {
                if model.frame != nil {
                    CityMapView(model:model).frame(maxWidth:.infinity,maxHeight:.infinity)
                } else {
                    ProgressView(L("都市を生成しています…")).frame(maxWidth:.infinity,maxHeight:.infinity)
                }
                if let frame=model.frame {
                    Divider()
                    CityStatusBar(frame:frame)
                }
                Divider()
                HStack(spacing:12) {
                    Circle().fill(TilePalette.color(for:model.tool)).frame(width:10,height:10)
                    Text(L("%@ · 基本費用 %@",model.tool.title,model.tool.baseCost)).fontWeight(.medium).lineLimit(1)
                    Text(model.message).lineLimit(1).help(model.message).foregroundStyle(.secondary).layoutPriority(-1)
                    Spacer(minLength:0)
                    Text(model.started ? (model.frame?.paused == true ? L("一時停止") : L("実行中")) : L("停止中"))
                        .foregroundStyle(.secondary).fixedSize().layoutPriority(1)
                    if model.dirty { Text(L("未保存")).foregroundStyle(.secondary).fixedSize().layoutPriority(1) }
                }.font(.system(size:14)).padding(12)
            }
            .frame(minWidth:320)
            .navigationTitle(model.title)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width:availableWidth)
        .id(language)
        .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
        .environment(\.locale,Locale(identifier:AppText.language))
        .onChange(of:language) { _,_ in model.refreshLanguage() }
        .frame(minWidth:950,minHeight:650)
        .background(CityWindowBridge(model:model).frame(width:0,height:0))
        .background(WindowWidthReader(width:$availableWidth).frame(width:0,height:0))
        .toolbar {
            ToolbarItemGroup(placement:.navigation) {
                Button { Task { await CityFiles.newCity(model,window:window) } } label: { Label(L("新規都市"),systemImage:"plus") }.disabled(model.documentBusy)
                Button { Task { await CityFiles.open(model,window:window) } } label: { Label(L("都市を開く…"),systemImage:"folder") }.disabled(model.documentBusy)
                Button { Task { _ = await CityFiles.save(model,window:window) } } label: { Label(L("保存"),systemImage:"square.and.arrow.down") }.disabled(!model.available)
            }
            ToolbarItemGroup(placement:.primaryAction) {
                Button { Task { await model.play() } } label: {
                    Label(L("再生"),systemImage:"play.fill")
                }.help(L("開始・再開")).disabled(!model.canPlay)
                Button { Task { await model.stop() } } label: {
                    Label(L("停止"),systemImage:"stop.fill")
                }.help(L("停止")).disabled(!model.canStop)
                Picker(L("速度"),selection:Binding(get:{ model.turbo ? 4 : (model.frame?.speed ?? 3) },set:{ value in Task { await model.setSpeed(value) } })) {
                    Text(L("低速")).tag(Int32(1)); Text(L("中速")).tag(Int32(2)); Text(L("高速")).tag(Int32(3)); Text(L("超高速")).tag(Int32(4))
                }.frame(width:95).disabled(!model.available)
                Menu {
                    Button(L("拡大")) { model.zoomCommand += 1 }
                    Button(L("縮小")) { model.zoomCommand -= 1 }
                    Button(L("全体")) { model.fitCommand += 1 }
                } label: { Text("\(Int(model.mapZoom*100))%") }
                Menu {
                    ForEach(CityMapLayer.allCases) { layer in
                        Button { model.mapLayer=layer } label: {
                            if model.mapLayer == layer { Label(layer.title,systemImage:"checkmark") }
                            else { Text(layer.title) }
                        }
                    }
                } label: { Label(L("マップ表示"),systemImage:"map") }
                    .help(L("マップ表示")+": "+model.mapLayer.title)
                Toggle(isOn:$model.powerOverlay) { Label(L("電力表示"),systemImage:"bolt") }.help(L("区域中心: 黄=通電、赤=未通電。導電タイルには黄色の枠。"))
                Menu {
                    Button(L("予算・税率…")) { model.panel = .budget }
                    Button(L("都市評価…")) { model.panel = .evaluation }
                    Button(L("履歴グラフ…")) { model.panel = .graphs }
                    Button(L("都市からのお知らせ…")) { model.panel = .messages }
                    Button(L("遊び方…")) { model.panel = .guide }
                } label: { Label(L("都市情報"),systemImage:"info.circle") }
            }
        }
        .sheet(item:$model.panel) { CityPanels(model:model,panel:$0).id(language) }
        .confirmationDialog(L("%@を発生させますか？",model.pendingDisaster?.title ?? L("災害")),isPresented:Binding(get:{ model.pendingDisaster != nil },set:{ if !$0 { model.pendingDisaster=nil } })) {
            if let disaster=model.pendingDisaster {
                Button(L("発生させる"),role:.destructive) { Task { await model.trigger(disaster) }; model.pendingDisaster=nil }
            }
        } message: { Text(L("都市が被害を受けます。取り消せません。")) }
        .alert(L("操作できませんでした"),isPresented:Binding(get:{ model.errorMessage != nil },set:{ if !$0 { model.errorMessage=nil } })) {
            Button("OK") { model.errorMessage=nil }
        } message: { Text(model.errorMessage ?? "") }
        .task { await model.run() }
        .task(id:model.mapLayer) { await model.refreshInspectionData() }
        .task(id:model.historyScale) { await model.refreshInspectionData() }
        .task(id:model.panel) { await model.refreshInspectionData() }
        .focusedSceneValue(\.cityModel,model)
    }
}
struct CityModelFocusKey: FocusedValueKey { typealias Value=CityModel }
extension FocusedValues {
    var cityModel: CityModel? {
        get { self[CityModelFocusKey.self] }
        set { self[CityModelFocusKey.self]=newValue }
    }
}

/// Read the NSWindow, not the split view's intrinsic width, which can grow while dragging.
private struct WindowWidthReader: NSViewRepresentable {
    @Binding var width: CGFloat
    func makeNSView(context: Context) -> WidthView { WidthView() }
    func updateNSView(_ view: WidthView, context: Context) {
        view.changed={ width=$0 }
        view.publishWidth()
    }
    final class WidthView: NSView {
        var changed: ((CGFloat)->Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            if let window {
                NotificationCenter.default.addObserver(self,selector:#selector(resized),name:NSWindow.didResizeNotification,object:window)
                publishWidth()
            }
        }
        @objc private func resized(_ notification: Notification) { publishWidth() }
        func publishWidth() {
            // SwiftUI state must not change during updateNSView/layout.
            Task { @MainActor [weak self] in
                guard let self, let width=window?.contentView?.bounds.width, width>0 else { return }
                changed?(width)
            }
        }
    }
}
