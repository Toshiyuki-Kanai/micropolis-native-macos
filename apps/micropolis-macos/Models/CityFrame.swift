// SPDX-License-Identifier: GPL-3.0-or-later
// Native macOS frontend, modified version, 2026-10-17.
import Foundation
import MicropolisNative

struct CityFrame: Sendable {
    static let width = 120
    static let height = 100
    var tiles: [UInt16] // Caller-owned copy, row-major y * 120 + x; includes flags.
    let funds: Int64
    let population: Int64
    let populationPending: Bool
    let time: Int64
    let year: Int32
    let month: Int32
    let speed: Int32
    let paused: Bool
    let details: CityDetails
    var civic = CivicFrame()
    var revision: UInt64
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
    case wire=6, railroad=7, park=8, coal=9, nuclear=10, police=11, fire=12, stadium=13, seaport=14, airport=15, query=16
    var id: Int32 { rawValue }
    var title: String {
        switch self {
        case .road: L("道路")
        case .residential: L("住宅地区")
        case .commercial: L("商業地区")
        case .industrial: L("工業地区")
        case .bulldozer: L("撤去")
        case .wire: L("送電線")
        case .railroad: L("鉄道")
        case .park: L("公園")
        case .coal: L("石炭発電所")
        case .nuclear: L("原子力発電所")
        case .police: L("警察署")
        case .fire: L("消防署")
        case .stadium: L("スタジアム")
        case .seaport: L("港")
        case .airport: L("空港")
        case .query: L("区域調査")
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
        case .query: "magnifyingglass"
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
    var continuous: Bool { size == 1 && self != .query }
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
        case .query: 0
        }
    }
}

enum CityPanel: String, Identifiable { case budget, evaluation, guide, graphs, messages, query, newCity; var id: String { rawValue } }
enum Disaster: Int32, CaseIterable, Identifiable {
    case fire=1, flood, tornado, earthquake, monster, meltdown
    var id: Int32 { rawValue }
    var title: String { [L("火災"), L("洪水"), L("竜巻"), L("地震"), L("怪獣"), L("メルトダウン")][Int(rawValue)-1] }
}

// Copied civic data; no engine pointers escape the session actor.
enum CityMapLayer: Int32, CaseIterable, Identifiable, Sendable {
    case all = -1, population=0, growth, land, crime, pollution, traffic, power, fire, police
    case residential=9, commercial, industrial, transport
    var id: Int32 { rawValue }
    var title: String {
        switch self {
        case .all: L("全区域")
        case .population: L("人口密度")
        case .growth: L("成長率")
        case .land: L("地価")
        case .crime: L("犯罪")
        case .pollution: L("汚染")
        case .traffic: L("交通量")
        case .power: L("電力")
        case .fire: L("消防管轄")
        case .police: L("警察管轄")
        case .residential: L("住宅")
        case .commercial: L("商業")
        case .industrial: L("工業")
        case .transport: L("交通網")
        }
    }
}
struct CivicFrame: Sendable {
    var difficulty: Int32=0
    var autoBulldoze=true
    var budgetPending=false
    var populationDelta: Int64=0
    var scoreDelta: Int32=0
    var earthquakeSequence: Int32=0
    var problems: [(id: Int32, votes: Int32)]=[]
    var events: [CityEvent]=[]
    var sprites: [CitySprite]=[]
    var finances: [CityFinance]=[]
    var sounds: [(kind: Int32,x: Int32,y: Int32)]=[]
}
struct CityEvent: Sendable, Identifiable {
    let id=UUID()
    let number, x, y: Int32
    let important: Bool
    var text: String { CityMessages.text(number) }
}
struct CitySprite: Sendable {
    let kind, frame, x, y, width, height, offsetX, offsetY: Int32
}
struct ZoneInspection: Sendable {
    let category, density, land, crime, pollution, growth, x, y: Int32
    var categoryName: String {
        let names=[L("空き地"),L("水域"),L("森林"),L("瓦礫"),L("洪水"),L("放射能"),L("火災"),L("道路"),L("送電線"),L("鉄道"),L("住宅"),L("商業"),L("工業"),L("港"),L("空港"),L("石炭発電所"),L("消防署"),L("警察署"),L("スタジアム"),L("原子力発電所"),L("跳ね橋"),L("レーダー"),L("噴水"),L("工業"),L("競技場"),L("跳ね橋"),L("特殊施設"),L("不明"),L("不明")]
        return names[max(0,min(names.count-1,Int(category)-1))]
    }
}
// IDs are the existing C++ message protocol, not Java enum ordinals.
enum CityMessages {
    static func text(_ id: Int32) -> String {
        let messages: [Int32:String]=[
            1:L("住宅地区が必要です。"),2:L("商業地区が必要です。"),3:L("工業地区が必要です。"),
            4:L("道路が必要です。"),5:L("鉄道が必要です。"),6:L("電力が必要です。"),
            7:L("スタジアムが必要です。"),8:L("港が必要です。"),9:L("空港が必要です。"),
            10:L("汚染が深刻です。"),11:L("犯罪が深刻です。"),12:L("交通渋滞が発生しています。"),
            13:L("消防署が必要です。"),14:L("警察署が必要です。"),15:L("停電が報告されています。"),
            16:L("税率が高すぎます。"),17:L("道路予算が不足しています。"),18:L("消防予算が不足しています。"),
            19:L("警察予算が不足しています。"),20:L("火災が発生しました。"),21:L("怪獣が現れました。"),
            22:L("竜巻が発生しました。"),23:L("地震が発生しました。"),24:L("航空機が墜落しました。"),
            25:L("船舶事故が発生しました。"),26:L("列車事故が発生しました。"),27:L("ヘリコプター事故が発生しました。"),
            28:L("失業率が高くなっています。"),29:L("資金がありません。"),30:L("爆撃による火災が報告されています。"),
            31:L("公園が必要です。"),32:L("爆発が報告されています。"),
            33:L("建設資金が不足しています。"),34:L("先に撤去してください。"),35:L("人口が2,000人に到達しました。"),36:L("人口が10,000人に到達しました。"),
            37:L("人口が50,000人に到達しました。"),38:L("人口が100,000人に到達しました。"),39:L("人口が500,000人に到達しました。"),40:L("発電能力が不足しています。"),41:L("激しい交通渋滞が報告されています。"),42:L("洪水が発生しました。"),43:L("原子力発電所でメルトダウンが発生しました。"),44:L("暴動が発生しました。"),45:L("新しい都市を作成しました。"),46:L("都市を読み込みました。")
        ]
        return messages[id] ?? L("都市からのお知らせ（エンジン通知 %@）",id)
    }
}

struct CityFinance: Sendable {
    let time, funds, income, operating, capital: Int64
}

struct BudgetQuote: Sendable {
    let income, roadRequest, fireRequest, policeRequest, roadFunded, fireFunded, policeFunded, balance: Int64
}
