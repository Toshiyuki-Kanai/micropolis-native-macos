// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct CityPanels: View {
    let model: CityModel
    let panel: CityPanel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            if model.frame?.populationPending == true { Text("読込後の人口・評価は、開始するとエンジンが再集計します。").foregroundStyle(.secondary) }
            if let details=model.frame?.details {
                switch panel {
                case .budget: BudgetView(model:model,details:details)
                case .evaluation: evaluation(details)
                case .guide: guide
                case .graphs: HistoryView(model:model)
                case .query: if let q=model.inspection { InspectionView(q:q) }
                case .newCity: NewCityView(model:model)
                case .messages:
                    Text("都市からのお知らせ").font(.title2)
                    ScrollView {
                        LazyVStack(alignment:.leading,spacing:12) {
                            ForEach(model.events.reversed()) { event in
                                HStack {
                                    Text(event.text).fontWeight(event.important ? .semibold : .regular)
                                    Spacer()
                                    if event.x>=0 && event.y>=0 && event.x<120 && event.y<100 {
                                        Button("場所を表示") { model.focusPoint=MapPoint(x:event.x,y:event.y);dismiss() }
                                    }
                                }
                            }
                            if model.events.isEmpty { Text("通知はありません。") }
                        }
                    }.frame(height:300)
                }
            }
            HStack { Spacer(); Button("閉じる") { dismiss() }.keyboardShortcut(.cancelAction).disabled(panel == .budget && model.frame?.civic.budgetPending == true) }
        }
        .padding(24).frame(width:600,height:panel == .budget ? 700 : nil)
        .interactiveDismissDisabled(panel == .budget && model.frame?.civic.budgetPending == true)
    }
    private func evaluation(_ d: CityDetails) -> some View {
        Form {
            Section("都市評価") {
                LabeledContent("評価点",value:"\(d.score) / 1000")
                LabeledContent("市長支持率",value:"\(d.approval)%")
                LabeledContent("都市規模",value:["村","町","都市","首都","大都市","巨大都市"][max(0,min(5,Int(d.cityClass)))])
                LabeledContent("資産評価",value:d.assessedValue.formatted())
                if let f=model.frame {
                    LabeledContent("人口 / 増減",value:"\(f.population) / \(f.civic.populationDelta)")
                    LabeledContent("評価点の増減",value:"\(f.civic.scoreDelta)")
                    LabeledContent("難易度",value:["初級","中級","上級"][Int(f.civic.difficulty)])
                    ForEach(Array(f.civic.problems.enumerated()),id:\.offset) { _,problem in
                        if problem.id>=0 && problem.id<7 {
                            LabeledContent(["犯罪","汚染","住宅費","税金","交通","失業","火災"][Int(problem.id)],value:"\(problem.votes)%")
                        }
                    }
                }
            }
            Section("需要・環境（エンジン集計値）") {
                LabeledContent("住宅 / 商業 / 工業需要",value:"\(d.residentialDemand) / \(d.commercialDemand) / \(d.industrialDemand)")
                LabeledContent("交通 / 汚染 / 犯罪",value:"\(d.traffic) / \(d.pollution) / \(d.crime)")
                LabeledContent("通電 / 未通電の区域",value:"\(d.powered) / \(d.unpowered)")
                LabeledContent("石炭 / 原子力発電所",value:"\(d.coal) / \(d.nuclear)")
            }
        }.formStyle(.grouped)
    }
    private var guide: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("都市を育てる").font(.title2)
            Text("1. 空き地に道路を延ばし、道路に隣接する住宅・商業・工業地区を配置します。\n2. 発電所を設置し、送電線で地区へ接続します。電力表示で区域中心の通電を確認できます。\n3. 開始ボタンで時間を進めます。地区の需要・交通・電力・税率などに応じてエンジンが都市を発展させます。\n4. 予算で税率と道路・警察・消防の資金配分を変更し、ファイルメニューから都市を保存します。")
            Text("操作").font(.headline)
            Text("マウスを離して確定、Escapeで取消。道路・鉄道・送電線は経路ドラッグ、住宅・商業・工業・公園・撤去は矩形ドラッグ。右ドラッグ／2本指スクロールでパン。ピンチ／マウスホイール／⌘スクロールでズーム。全体ボタンで表示を戻します。")
            Text("病院は住宅から需要に応じて自動生成されます。既存エンジンに学校・病院の直接建設ツールはありません。赤枠は未通電の区域中心です。建設プレビューは仮エンジンで料金と配置を計算します。赤枠は配置不可や資金不足です。確定時には実都市の状態で再判定します。")
            Text("保存は従来の.cty形式です。乱数・派生タイル・実行中の停止状態は保存形式の仕様上完全再現されません。読込後は停止状態で開きます。")
                .foregroundStyle(.secondary)
        }
    }
}

private struct BudgetView: View {
    let model: CityModel
    let details: CityDetails
    @State private var tax: Int32
    @State private var police: Double
    @State private var fire: Double
    @State private var road: Double
    @State private var quote: BudgetQuote?
    @State private var original: CityDetails
    init(model: CityModel,details: CityDetails) {
        self.model=model; self.details=details
        _original=State(initialValue:details)
        _tax=State(initialValue:details.taxRate)
        _police=State(initialValue:Double(details.policeFunding))
        _fire=State(initialValue:Double(details.fireFunding))
        _road=State(initialValue:Double(details.roadFunding))
    }
    private var quoteKey: String { "\(tax)/\(police)/\(fire)/\(road)" }
    var body: some View {
        Form {
            Section("税率と資金配分") {
                Stepper("税率 \(tax)%",value:$tax,in:0...20)
                allocation("道路",value:$road)
                allocation("警察",value:$police)
                allocation("消防",value:$fire)
                Button("適用") {
                    Task { _ = await model.configureBudget(tax:tax,police:Float(police),fire:Float(fire),road:Float(road)) }
                }.disabled(!model.available)
                Button("開いた時の設定に戻す") {
                    tax=original.taxRate;police=Double(original.policeFunding);fire=Double(original.fireFunding);road=Double(original.roadFunding)
                }
            }
            if let quote {
                Section("現在の都市規模での年次見積り") {
                    LabeledContent("税収",value:quote.income.formatted())
                    LabeledContent("道路 要求 / 配分",value:"\(quote.roadRequest) / \(quote.roadFunded)")
                    LabeledContent("消防 要求 / 配分",value:"\(quote.fireRequest) / \(quote.fireFunded)")
                    LabeledContent("警察 要求 / 配分",value:"\(quote.policeRequest) / \(quote.policeFunded)")
                    LabeledContent("決算後の見積残高",value:quote.balance.formatted())
                    Text("仮エンジンで現時点の人口・地価・施設数を使った見積りです。今後の都市成長は含めません。実都市の資金は変えません。").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("過去3年の財政（今回の起動中の決算）") {
                if let entries=model.frame?.civic.finances, !entries.isEmpty {
                    ForEach(Array(entries.prefix(3).enumerated()),id:\.offset) { _,entry in
                        VStack(alignment:.leading) {
                            Text("\(String(1900+entry.time/48))年 · 残高 \(entry.funds.formatted())").fontWeight(.medium)
                            Text("税収 \(entry.income) · 運営費 \(entry.operating) · 建設等 \(entry.capital)").font(.caption)
                        }
                    }
                } else { Text("最初の年次決算後に表示します。財政明細は保存形式には含まれません。") }
            }
            Section("前回集計された年間予算") {
                LabeledContent("税収",value:details.taxIncome.formatted())
                LabeledContent("道路 / 警察 / 消防の必要額",value:"\(details.roadCost) / \(details.policeCost) / \(details.fireCost)")
                Text("徴税・支出・資金不足による配分調整はエンジンが年次決算で行います。適用は自動予算の設定を変更しません。")
                    .foregroundStyle(.secondary)
                Toggle("自動予算",isOn:Binding(get:{ model.frame?.details.automaticBudget ?? true },set:{ value in Task { await model.setOptions(budget:value) } }))
                if model.frame?.civic.budgetPending == true {
                    Text("決算直前で停止しています。設定を適用してから決算を承認してください。")
                    Button("設定を適用して決算を承認") {
                        Task {
                            if await model.configureBudget(tax:tax,police:Float(police),fire:Float(fire),road:Float(road)) { await model.acceptBudget() }
                        }
                    }.disabled(!model.available)
                }
            }
        }.formStyle(.grouped)
        .task(id:quoteKey) {
            let result=await model.quote(tax:tax,police:Float(police),fire:Float(fire),road:Float(road))
            if !Task.isCancelled { quote=result }
        }
    }
    private func allocation(_ name: String,value: Binding<Double>) -> some View {
        VStack(alignment:.leading) {
            Text("\(name) \(Int((value.wrappedValue*100).rounded()))%")
            Slider(value:value,in:0...1,step:0.05)
        }
    }
}

private struct HistoryView: View {
    @Bindable var model: CityModel
    @State private var selected: Set<Int>=[3,5]
    private let names=["住宅人口","商業人口","工業人口","収支","犯罪","汚染"]
    private let colors: [Color]=[.green,.blue,.orange,.brown,.red,.purple]
    var body: some View {
        VStack(alignment:.leading) {
            Text("都市の履歴").font(.title2)
            Picker("期間",selection:$model.historyScale) { Text("10年").tag(Int32(0));Text("120年").tag(Int32(1)) }.pickerStyle(.segmented)
            HStack { ForEach(0..<6,id:\.self) { i in
                Toggle(names[i],isOn:Binding(get:{ selected.contains(i) },set:{ if $0 { selected.insert(i) } else { selected.remove(i) } })).toggleStyle(.button).tint(colors[i])
            } }
            Canvas { context,size in
                let plot=CGRect(x:12,y:16,width:size.width-24,height:size.height-40)
                context.stroke(Path(plot),with:.color(.secondary.opacity(0.5)))
                let scale=max(256,model.histories.flatMap { $0 }.max().map(Double.init) ?? 256)
                for i in selected.sorted() where model.histories.count>i && model.histories[i].count==120 {
                    let values=model.histories[i]
                    // All series share a scale, as in the reference GraphsPane.
                    let upper=scale
                    var path=Path()
                    for n in 0..<120 {
                        let value=max(0,Double(values[119-n]))
                        let p=CGPoint(x:plot.minX+Double(n)*plot.width/119,y:plot.maxY-value/upper*plot.height)
                        if n==0 { path.move(to:p) } else { path.addLine(to:p) }
                    }
                    context.stroke(path,with:.color(colors[i]),lineWidth:2)
                }
                let unit: Int64=model.historyScale==0 ? 4 : 48
                let period: Int64=model.historyScale==0 ? 12 : 10
                let latest=(model.frame?.time ?? 0)/unit
                for n in 0..<120 {
                    let sample=latest-119+Int64(n)
                    if sample%period==0 {
                        let x=plot.minX+Double(n)*plot.width/119
                        var grid=Path();grid.move(to:CGPoint(x:x,y:plot.minY));grid.addLine(to:CGPoint(x:x,y:plot.maxY))
                        context.stroke(grid,with:.color(.secondary.opacity(0.15)),lineWidth:1)
                        context.draw(Text(String(1900+sample*unit/48)).font(.caption2),at:CGPoint(x:x,y:size.height-10))
                    }
                }
            }.frame(height:240)
            Text("各系列はエンジンの履歴値です。6系列は共通尺度で表示し、収支・犯罪・汚染はエンジンが正規化した履歴値を用います。負の収支はエンジンの履歴形式で正規化されています。") .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct NewCityView: View {
    let model: CityModel
    @Environment(\.dismiss) private var dismiss
    @State private var preview: CityFrame?
    @State private var seeds: [Int32]=[Int32.random(in:0...Int32.max)]
    @State private var index=0
    @State private var level: Int32=0
    @State private var working=false
    @State private var failure: String?
    private let generator=EngineSession()
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("新しい都市").font(.title2)
            if let preview {
                TerrainCanvas(frame:preview,geometry:MapGeometry(size:CGSize(width:480,height:280)),power:false).frame(width:480,height:280)
            } else { ProgressView().frame(width:480,height:280) }
            HStack {
                Button("前の地形") { index -= 1 }.disabled(index==0 || working)
                Button("次の地形") {
                    if index+1==seeds.count { seeds.append(Int32.random(in:0...Int32.max)) }
                    index += 1
                }.disabled(working)
                Spacer()
                Picker("難易度",selection:$level) {
                    Text("初級 · 20,000").tag(Int32(0));Text("中級 · 10,000").tag(Int32(1));Text("上級 · 5,000").tag(Int32(2))
                }.frame(width:215)
            }
            if let failure { Text(failure).foregroundStyle(.red) }
            Button("この都市で開始") {
                let seed=seeds[index], chosen=level
                working=true
                Task {
                    dismiss()
                    await Task.yield()
                    await CityFiles.createSelected(model,window:CityWindows.shared.window(for:model),seed:seed,level:chosen)
                }
            }.keyboardShortcut(.defaultAction).disabled(working || preview==nil)
        }
        .task(id:index) {
            working=true;defer { working=false }
            do { preview=try await generator.execute(.generateLevel(seed:seeds[index],level:level)) }
            catch { failure=String(describing:error) }
        }
    }
}

private struct InspectionView: View {
    let q: ZoneInspection
    var body: some View {
        Form {
            LabeledContent("位置",value:"\(q.x), \(q.y)")
            LabeledContent("建物・地形",value:q.categoryName)
            LabeledContent("人口密度",value:["低密度","中密度","高密度","非常に高密度"][max(0,min(3,Int(q.density)-1))])
            LabeledContent("地価",value:["低い","中程度","高い","非常に高い"][max(0,min(3,Int(q.land)-5))])
            LabeledContent("犯罪",value:["安全","軽度","多い","危険"][max(0,min(3,Int(q.crime)-9))])
            LabeledContent("汚染",value:["少ない","中程度","多い","非常に多い"][max(0,min(3,Int(q.pollution)-13))])
            LabeledContent("成長",value:["減少","安定","成長","急成長"][max(0,min(3,Int(q.growth)-17))])
        }.formStyle(.grouped)
    }
}
