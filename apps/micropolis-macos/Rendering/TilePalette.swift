// SPDX-License-Identifier: GPL-3.0-or-later
// Original schematic art only; no legacy image assets.
import SwiftUI

enum TilePalette {
    static func color(_ raw: UInt16) -> Color {
        switch raw & 0x03ff {
        case 0...1: Color(red:0.55,green:0.66,blue:0.43)
        case 2...20, 48...51: .blue
        case 21...43: Color(red:0.16,green:0.39,blue:0.24)
        case 44...47: .brown
        case 52: .purple
        case 56...63: .red
        case 64...79, 828...831, 948...951: Color(white:0.28)
        case 80...143: Color(red:0.50,green:0.42,blue:0.27)
        case 144...206: Color(red:0.75,green:0.27,blue:0.18)
        case 208...223: .yellow
        case 224...239: Color(white:0.6)
        case 240...404: .green
        case 405...422: .pink
        case 423...611: .cyan
        case 612...692, 852...859: .orange
        case 693...708: .indigo
        case 709...744, 832...839: .teal
        case 745...760, 916...931: .brown
        case 761...769: .red
        case 770...778: .blue
        case 779...810, 932...947: .mint
        case 811...826: .purple
        case 840...843: .green
        default: .gray
        }
    }
    static func symbol(_ raw: UInt16) -> String? {
        switch raw & 0x03ff {
        case 244..<405: "R"
        case 409: "H"
        case 418: "+"
        case 427..<612: "C"
        case 616..<693: "I"
        case 698: L("港")
        case 716: L("空")
        case 750: L("炭")
        case 765: L("消")
        case 774: L("警")
        case 784, 800: L("球")
        case 816: L("核")
        default: nil
        }
    }
    static func color(for tool: BuildTool) -> Color {
        switch tool {
        case .road: Color(white:0.28)
        case .residential, .park: .green
        case .commercial: .cyan
        case .industrial: .orange
        case .bulldozer, .coal: .brown
        case .wire: .yellow
        case .railroad: .gray
        case .nuclear: .purple
        case .police: .blue
        case .fire: .red
        case .stadium: .mint
        case .seaport: .indigo
        case .airport: .teal
        case .query: .primary
        }
    }
}
