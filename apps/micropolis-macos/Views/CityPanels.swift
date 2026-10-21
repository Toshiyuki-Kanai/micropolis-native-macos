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
                }
            }
            HStack { Spacer(); Button("閉じる") { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(24).frame(width:540)
    }
    private func evaluation(_ d: CityDetails) -> some View {
        Form {
            Section("都市評価") {
                LabeledContent("評価点",value:"\(d.score) / 1000")
                LabeledContent("市長支持率",value:"\(d.approval)%")
                LabeledContent("都市規模",value:["村","町","都市","首都","大都市","巨大都市"][max(0,min(5,Int(d.cityClass)))])
                LabeledContent("資産評価",value:d.assessedValue.formatted())
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
            Text("クリックで配置。道路・鉄道・送電線・公園・撤去はドラッグ対応。右ドラッグ／2本指スクロールでパン。ピンチ／マウスホイール／⌘スクロールでズーム。全体ボタンで表示を戻します。")
            Text("病院は住宅から需要に応じて自動生成されます。既存エンジンに学校・病院の直接建設ツールはありません。赤枠は未通電の区域中心です。建設プレビューは範囲の目安で、建設可否を保証しません。")
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
    init(model: CityModel,details: CityDetails) {
        self.model=model; self.details=details
        _tax=State(initialValue:details.taxRate)
        _police=State(initialValue:Double(details.policeFunding))
        _fire=State(initialValue:Double(details.fireFunding))
        _road=State(initialValue:Double(details.roadFunding))
    }
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
            }
            Section("前回集計された年間予算") {
                LabeledContent("税収",value:details.taxIncome.formatted())
                LabeledContent("道路 / 警察 / 消防の必要額",value:"\(details.roadCost) / \(details.policeCost) / \(details.fireCost)")
                Text("適用すると自動予算になります。徴税・支出・資金不足による配分調整はエンジンが次回の年次決算で行います。")
                    .foregroundStyle(.secondary)
                if !details.automaticBudget { Text("エンジンが資金不足を検知しました。配分・税率を見直して適用してください。").foregroundStyle(.red) }
            }
        }.formStyle(.grouped)
    }
    private func allocation(_ name: String,value: Binding<Double>) -> some View {
        VStack(alignment:.leading) {
            Text("\(name) \(Int((value.wrappedValue*100).rounded()))%")
            Slider(value:value,in:0...1,step:0.05)
        }
    }
}
