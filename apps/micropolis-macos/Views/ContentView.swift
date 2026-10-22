// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct ContentView: View {
    @Bindable var model: CityModel
    private var window: NSWindow? { CityWindows.shared.window(for:model) }
    var body: some View {
        VStack(spacing:0) {
            if let f=model.frame {
                HStack(spacing:20) {
                    Text("資金 \(f.funds.formatted())")
                    Text(f.populationPending ? "人口 集計待ち" : "人口 \(f.population.formatted())")
                    Text("\(String(f.year))年\(f.month+1)月")
                    DemandBars(details:f.details)
                    Text("通電 \(f.details.powered) / 未通電 \(f.details.unpowered)").foregroundStyle(.secondary)
                    Spacer()
                    Text(model.started ? (f.paused ? "一時停止" : "実行中") : "停止中").foregroundStyle(.secondary)
                }.monospacedDigit().padding(12)
                Divider()
                CityMapView(model:model)
            } else {
                ProgressView("都市を生成しています…").frame(maxWidth:.infinity,maxHeight:.infinity)
            }
            Divider()
            HStack(spacing:12) {
                Circle().fill(TilePalette.color(for:model.tool)).frame(width:10,height:10)
                Text("\(model.tool.title) · 基本費用 \(model.tool.baseCost)").fontWeight(.medium)
                Text(model.message).lineLimit(1).foregroundStyle(.secondary)
                Spacer()
                if model.dirty { Text("未保存").foregroundStyle(.secondary) }
            }.font(.caption).padding(10)
        }
        .frame(minWidth:900,minHeight:600)
        .navigationTitle(model.title)
        .background(CityWindowBridge(model:model).frame(width:0,height:0))
        .toolbar {
            ToolbarItemGroup(placement:.navigation) {
                Button { Task { await CityFiles.newCity(model,window:window) } } label: { Label("新規都市",systemImage:"plus") }.disabled(model.documentBusy)
                Picker("建設ツール",selection:$model.tool) {
                    ForEach(BuildTool.allCases) { t in Label(t.title,systemImage:t.symbol).tag(t) }
                }.labelStyle(.titleAndIcon).frame(width:185).disabled(!model.acceptsMapInput)
            }
            ToolbarItemGroup(placement:.primaryAction) {
                Button { Task { await model.startOrStop() } } label: { Label(model.started ? "停止" : "開始",systemImage:model.started ? "stop.fill" : "play.fill") }.help(model.started ? "停止" : "開始").disabled(!model.available)
                Button { Task { await model.togglePause() } } label: { Label(model.frame?.paused == true ? "再開" : "一時停止",systemImage:model.frame?.paused == true ? "play.fill" : "pause.fill") }.help("一時停止・再開").disabled(!model.available || !model.started)
                Picker("速度",selection:Binding(get:{ model.turbo ? 4 : (model.frame?.speed ?? 3) },set:{ value in Task { await model.setSpeed(value) } })) {
                    Text("低速").tag(Int32(1)); Text("中速").tag(Int32(2)); Text("高速").tag(Int32(3)); Text("超高速").tag(Int32(4))
                }.frame(width:95).disabled(!model.available)
                Toggle(isOn:$model.powerOverlay) { Label("電力表示",systemImage:"bolt") }.help("区域中心: 黄=通電、赤=未通電。導電タイルには黄色の枠。")
                Menu {
                    Button("予算・税率…") { model.panel = .budget }
                    Button("都市評価…") { model.panel = .evaluation }
                    Button("履歴グラフ…") { model.panel = .graphs }
                    Button("都市からのお知らせ…") { model.panel = .messages }
                    Button("遊び方…") { model.panel = .guide }
                } label: { Label("都市情報",systemImage:"info.circle") }
            }
        }
        .sheet(item:$model.panel) { CityPanels(model:model,panel:$0) }
        .confirmationDialog("\(model.pendingDisaster?.title ?? "災害")を発生させますか？",isPresented:Binding(get:{ model.pendingDisaster != nil },set:{ if !$0 { model.pendingDisaster=nil } })) {
            if let disaster=model.pendingDisaster {
                Button("発生させる",role:.destructive) { Task { await model.trigger(disaster) }; model.pendingDisaster=nil }
            }
        } message: { Text("都市が被害を受けます。取り消せません。") }
        .alert("操作できませんでした",isPresented:Binding(get:{ model.errorMessage != nil },set:{ if !$0 { model.errorMessage=nil } })) {
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

private struct DemandBars: View {
    let details: CityDetails
    var body: some View {
        Canvas { context,size in
            let values=[details.residentialDemand,details.commercialDemand,details.industrialDemand]
            let colors: [Color]=[.green,.blue,.orange]
            let center=size.height/2
            context.stroke(Path(CGRect(x:0,y:center,width:size.width,height:0)),with:.color(.secondary),lineWidth:1)
            for i in 0..<3 {
                let demand=Double(values[i])/2000
                let height=min(1,abs(demand))*center
                let rect=CGRect(x:Double(i)*12+2,y:demand>=0 ? center-height : center,width:8,height:height)
                context.fill(Path(rect),with:.color(colors[i]))
            }
        }.frame(width:36,height:28)
        .help("需要: 住宅 \(details.residentialDemand)、商業 \(details.commercialDemand)、工業 \(details.industrialDemand)")
        .accessibilityLabel("住宅・商業・工業の需要")
    }
}
