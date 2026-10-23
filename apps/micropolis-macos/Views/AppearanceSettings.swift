// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct AppearanceSettings: View {
    @AppStorage("appAppearance") private var appearance="system"
    @AppStorage("appLanguage") private var language="system"
    var body: some View {
        Form {
            Picker(L("外観"),selection:$appearance) {
                Text(L("システムに合わせる")).tag("system")
                Text(L("ライト")).tag("light")
                Text(L("ダーク")).tag("dark")
            }
            Picker(L("言語"),selection:$language) {
                Text(L("システムに合わせる")).tag("system")
                Text(L("日本語")).tag("ja")
                Text("English").tag("en")
            }
            Text(L("外観と言語は次回起動時も保持されます。")).font(.callout).foregroundStyle(.secondary)
        }
        .formStyle(.grouped).padding().frame(width:440)
        .id(language)
        .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
    }
}
