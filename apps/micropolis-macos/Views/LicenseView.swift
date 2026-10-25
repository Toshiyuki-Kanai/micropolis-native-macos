// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct LicenseView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Micropolis for macOS").font(.title)
                Text("Version \(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "—") (Build \(Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "—"))")
                    .font(.headline)
                Text(L("非公式のmacOSネイティブ移植版です。Electronic ArtsおよびMicropolis商標権者による公式リリースではありません。"))
                Link(L("ソースコード・ビルド手順"),destination:URL(string:"https://github.com/Toshiyuki-Kanai/micropolis-native-macos")!)
                Text(L("名称使用条件およびGitHub Releasesでの使用の最終確認は未完了です。個別の使用許諾取得や正式公開の承認を示すものではありません。"))
                Text(L("2026-10-25に更新した変更版です。Electronic Artsの製品ではありません。"))
                Text("Copyright (C) 1989–2007 Electronic Arts Inc. (underlying engine)")
                Text(L("GPL version 3 or laterおよびEA追加条件の下で提供されます。無保証です。ソースとビルド手順は、このアプリを含むmicropolis-native-macosリポジトリにあります。"))
                Text("Micropolis is a registered trademark of Micropolis Corporation (Micropolis GmbH) and is licensed here as a courtesy of the owner under the Micropolis Public Name License.")
                Link("Micropolis", destination: URL(string: "https://www.micropolis.com")!)
                Text(L("画像・音声：GPL公開版Micropolisのtiles.xpmおよびobj1〜7のXPMを無損失PNG変換し、res/soundsのWAVを同梱。Copyright (C) 1989–2007 Electronic Arts Inc.。GPL version 3 or laterとEA追加条件。原画像・出典・変換スクリプトを対応ソースに含めます。"))
                ForEach(["ASSET-NOTICE.ja.md", "UPSTREAM-README.txt", "UPSTREAM-COPYING.txt", "provenance.json", "Gameplay/ASSET-NOTICE.ja.md", "Gameplay/provenance.json"],id:\.self) { name in
                    if let url=Bundle.main.resourceURL?.appendingPathComponent("OriginalGraphics/\(name)"),
                       let text=try? String(contentsOf:url,encoding:.utf8) {
                        DisclosureGroup(name) { Text(text).font(.system(.caption,design:.monospaced)) }
                    }
                }
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
