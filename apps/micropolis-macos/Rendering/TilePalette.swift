// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

enum TilePalette {
    static func color(_ raw: UInt16) -> Color {
        switch raw & 0x03ff {
        case 0...1: Color(red: 0.53, green: 0.64, blue: 0.40)
        case 2...20, 48...51: .blue
        case 21...43: Color(red: 0.16, green: 0.39, blue: 0.24)
        case 44...47: .brown
        case 56...63: .red
        case 64...206: Color(white: 0.32) // Roads, bridges and traffic variants
        case 208...239: .gray // Power and rail
        case 240...404: .green
        case 423...611: .cyan
        case 612...692: .orange
        default: .purple // Civic buildings and other engine tiles
        }
    }
    static func color(for tool: BuildTool) -> Color {
        switch tool {
        case .road: Color(white: 0.32)
        case .residential: .green
        case .commercial: .cyan
        case .industrial: .orange
        case .bulldozer: .brown
        }
    }
}
