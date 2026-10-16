// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct ContentView: View {
    @Bindable var model: CityModel
    @State private var confirmNewCity = false

    var body: some View {
        VStack(spacing: 0) {
            if let frame = model.frame {
                HStack(spacing: 24) {
                    Text("資金 \(frame.funds.formatted())")
                    Text("人口 \(frame.population.formatted())")
                    Text("\(String(frame.year))年\(frame.month + 1)月")
                    Spacer()
                    Text("時刻 \(frame.time) · \(model.started ? (frame.paused ? "一時停止" : "実行中") : "停止中")")
                        .foregroundStyle(.secondary)
                }
                .monospacedDigit()
                .padding(12)
                Divider()
                CityMapView(frame: frame, enabled: model.available) { x, y in
                    Task { await model.build(x: x, y: y) }
                }
                .padding(12)
            } else {
                ProgressView("都市を生成しています…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack {
                Text(model.message).lineLimit(1)
                Spacer()
                ForEach([BuildTool.road, .residential, .commercial, .industrial]) { tool in
                    HStack(spacing: 4) {
                        Rectangle().fill(TilePalette.color(for: tool)).frame(width: 10, height: 10)
                        Text(tool.title)
                    }
                }
            }
            .font(.caption)
            .padding(10)
        }
        .frame(minWidth: 820, minHeight: 600)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { confirmNewCity = true } label: { Label("新規都市", systemImage: "plus") }
                    .disabled(model.busy)
                Picker("建設ツール", selection: $model.tool) {
                    ForEach(BuildTool.allCases) { tool in
                        Label(tool.title, systemImage: tool.symbol).tag(tool)
                    }
                }
                .labelStyle(.titleAndIcon)
                .frame(width: 150)
                .disabled(!model.available)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { Task { await model.startOrStop() } } label: {
                    Label(model.started ? "停止" : "開始", systemImage: model.started ? "stop.fill" : "play.fill")
                }
                .help(model.started ? "停止（都市を保持）" : "開始")
                .disabled(!model.available)
                Button { Task { await model.togglePause() } } label: {
                    Label(model.frame?.paused == true ? "再開" : "一時停止",
                          systemImage: model.frame?.paused == true ? "play.fill" : "pause.fill")
                }
                .help(model.frame?.paused == true ? "再開" : "一時停止")
                .disabled(!model.available || !model.started)
                Picker("速度", selection: Binding(
                    get: { model.frame?.speed ?? 3 },
                    set: { speed in Task { await model.setSpeed(speed) } }
                )) {
                    Text("低速").tag(Int32(1))
                    Text("中速").tag(Int32(2))
                    Text("高速").tag(Int32(3))
                }
                .frame(width: 100)
                .disabled(!model.available)
            }
        }
        .confirmationDialog("現在の都市を破棄して新規都市を作成しますか？", isPresented: $confirmNewCity) {
            Button("新規都市を作成", role: .destructive) { Task { await model.newCity() } }
        }
        .alert("操作できませんでした", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .task { await model.run() }
        .focusedSceneValue(\.cityModel, model)
    }
}

struct CityModelFocusKey: FocusedValueKey { typealias Value = CityModel }
extension FocusedValues {
    var cityModel: CityModel? {
        get { self[CityModelFocusKey.self] }
        set { self[CityModelFocusKey.self] = newValue }
    }
}
