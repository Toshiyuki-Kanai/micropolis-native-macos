// SPDX-License-Identifier: GPL-3.0-or-later
// Native macOS frontend, modified version, 2026-10-16.
import Foundation

struct CityFrame: Sendable {
    static let width = 120
    static let height = 100
    let tiles: [UInt16] // Caller-owned copy, row-major y * 120 + x; includes flags.
    let funds: Int64
    let population: Int64
    let time: Int64
    let year: Int32
    let month: Int32
    let speed: Int32
    let paused: Bool
    let revision: UInt64
}

enum BuildTool: Int32, CaseIterable, Identifiable, Sendable {
    case road = 1, residential = 2, commercial = 3, industrial = 4, bulldozer = 5
    var id: Int32 { rawValue }
    var title: String {
        switch self {
        case .road: "道路"
        case .residential: "住宅地区"
        case .commercial: "商業地区"
        case .industrial: "工業地区"
        case .bulldozer: "撤去"
        }
    }
    var symbol: String {
        switch self {
        case .road: "road.lanes"
        case .residential: "house"
        case .commercial: "building.2"
        case .industrial: "gearshape.2"
        case .bulldozer: "hammer"
        }
    }
}
