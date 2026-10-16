// SPDX-License-Identifier: GPL-3.0-or-later
// Native macOS frontend, modified version, 2026-10-16. Not an EA product.
import SwiftUI

@main
struct MicropolisMacApp: App {
    var body: some Scene {
        WindowGroup("Micropolis Native", id: "city") {
            CityWindow()
        }
        .defaultSize(width: 1100, height: 860)
        .commands { CityCommands() }

        Window("ライセンスとクレジット", id: "licenses") {
            LicenseView()
        }
        .defaultSize(width: 640, height: 540)
    }
}

private struct CityWindow: View {
    @State private var model = CityModel()
    var body: some View { ContentView(model: model) }
}

private struct CityCommands: Commands {
    @FocusedValue(\.cityModel) private var model
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandMenu("シミュレーション") {
            Button(model?.started == true ? "停止" : "開始") {
                Task { await model?.startOrStop() }
            }
            .keyboardShortcut("r")
            .disabled(model?.available != true)
            Button(model?.frame?.paused == true ? "再開" : "一時停止") {
                Task { await model?.togglePause() }
            }
            .keyboardShortcut(" ", modifiers: [])
            .disabled(model?.available != true || model?.started != true)
            Divider()
            ForEach(1...3, id: \.self) { speed in
                Button(["低速", "中速", "高速"][speed - 1]) {
                    Task { await model?.setSpeed(Int32(speed)) }
                }
                .disabled(model?.available != true)
            }
        }
        CommandMenu("建設") {
            ForEach(BuildTool.allCases) { tool in
                Button(tool.title) { model?.tool = tool }
                    .keyboardShortcut(KeyEquivalent(Character(String(tool.rawValue))), modifiers: [])
                    .disabled(model?.available != true)
            }
        }
        CommandGroup(after: .appInfo) {
            Button("ライセンスとクレジット…") { openWindow(id: "licenses") }
        }
    }
}
