// SPDX-License-Identifier: GPL-3.0-or-later
// Native macOS frontend, modified version, 2026-10-17.
import Foundation
import MicropolisNative

struct CityFrame: Sendable {
    static let width = 120
    static let height = 100
    let tiles: [UInt16] // Caller-owned copy, row-major y * 120 + x; includes flags.
    let funds: Int64
    let population: Int64
    let populationPending: Bool
    let time: Int64
    let year: Int32
    let month: Int32
    let speed: Int32
    let paused: Bool
    let details: CityDetails
    let revision: UInt64
}

struct CityDetails: Sendable {
    let taxIncome, roadCost, policeCost, fireCost, assessedValue: Int64
    let taxRate, score, approval, cityClass, powered, unpowered, coal, nuclear: Int32
    let residentialDemand, commercialDemand, industrialDemand, pollution, crime, traffic: Int32
    let disasters, automaticBudget: Bool
    let policeFunding, fireFunding, roadFunding: Float
    init(_ d: MPDetails, snapshot: MPSnapshot) {
        taxIncome=d.tax_income; roadCost=d.road_cost; policeCost=d.police_cost; fireCost=d.fire_cost
        assessedValue=d.assessed_value; taxRate=d.tax_rate; score=d.score; approval=d.approval
        cityClass=d.city_class; powered=d.powered_zones; unpowered=d.unpowered_zones
        coal=d.coal_plants; nuclear=d.nuclear_plants; residentialDemand=d.residential_demand
        commercialDemand=d.commercial_demand; industrialDemand=d.industrial_demand
        pollution=d.pollution; crime=d.crime; traffic=d.traffic
        disasters=d.disasters != 0; automaticBudget=d.auto_budget != 0
        policeFunding=snapshot.police_fraction; fireFunding=snapshot.fire_fraction; roadFunding=snapshot.road_fraction
    }
}

struct MapPoint: Hashable, Sendable {
    let x: Int32
    let y: Int32
}

enum BuildTool: Int32, CaseIterable, Identifiable, Sendable {
    case road=1, residential=2, commercial=3, industrial=4, bulldozer=5
    case wire=6, railroad=7, park=8, coal=9, nuclear=10, police=11, fire=12, stadium=13, seaport=14, airport=15
    var id: Int32 { rawValue }
    var title: String {
        switch self {
        case .road: "道路"
        case .residential: "住宅地区"
        case .commercial: "商業地区"
        case .industrial: "工業地区"
        case .bulldozer: "撤去"
        case .wire: "送電線"
        case .railroad: "鉄道"
        case .park: "公園"
        case .coal: "石炭発電所"
        case .nuclear: "原子力発電所"
        case .police: "警察署"
        case .fire: "消防署"
        case .stadium: "スタジアム"
        case .seaport: "港"
        case .airport: "空港"
        }
    }
    var symbol: String {
        switch self {
        case .road: "road.lanes"
        case .residential: "house"
        case .commercial: "building.2"
        case .industrial: "gearshape.2"
        case .bulldozer: "hammer"
        case .wire: "bolt"
        case .railroad: "tram"
        case .park: "tree"
        case .coal, .nuclear: "bolt.circle"
        case .police: "shield"
        case .fire: "flame"
        case .stadium: "sportscourt"
        case .seaport: "ferry"
        case .airport: "airplane"
        }
    }
    var size: Int {
        switch self {
        case .residential, .commercial, .industrial, .police, .fire: 3
        case .coal, .nuclear, .stadium, .seaport: 4
        case .airport: 6
        default: 1
        }
    }
    var continuous: Bool { size == 1 }
    // Display estimates only; actual costs and clearing are always decided by C++.
    var baseCost: Int {
        switch self {
        case .road, .park: 10
        case .residential, .commercial, .industrial: 100
        case .bulldozer: 1
        case .wire: 5
        case .railroad: 20
        case .coal, .seaport: 3000
        case .nuclear, .stadium: 5000
        case .police, .fire: 500
        case .airport: 10000
        }
    }
}

enum CityPanel: String, Identifiable { case budget, evaluation, guide; var id: String { rawValue } }
enum Disaster: Int32, CaseIterable, Identifiable {
    case fire=1, flood, tornado, earthquake, monster, meltdown
    var id: Int32 { rawValue }
    var title: String { ["火災", "洪水", "竜巻", "地震", "怪獣", "メルトダウン"][Int(rawValue)-1] }
}
