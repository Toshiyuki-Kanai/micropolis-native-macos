// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct LicenseView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Micropolis Native macOS").font(.title)
                Text("2026-10-16に作成した変更版です。Electronic Artsの製品ではありません。")
                Text("Copyright (C) 1989–2007 Electronic Arts Inc. (underlying engine)")
                Text("GPL version 3 or laterおよびEA追加条件の下で提供されます。無保証です。ソースとビルド手順は、このアプリを含むmicropolis-native-macosリポジトリにあります。")
                Text("Micropolis is a registered trademark of Micropolis Corporation (Micropolis GmbH) and is licensed here as a courtesy of the owner under the Micropolis Public Name License.")
                Link("Micropolis", destination: URL(string: "https://www.micropolis.com")!)
                ForEach(["gpl-3.0", "MicropolisGPLLicenseNotice", "MicropolisPublicNameLicense"], id: \.self) { name in
                    if let url = Bundle.main.url(forResource: name, withExtension: name == "gpl-3.0" ? "txt" : "md"),
                       let text = try? String(contentsOf: url, encoding: .utf8) {
                        DisclosureGroup(name) { Text(text).font(.system(.caption, design: .monospaced)) }
                    }
                }
            }
            .textSelection(.enabled)
            .padding(24)
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}
