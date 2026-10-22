// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct CityMapView: View {
    let model: CityModel
    @State private var viewport=MapViewport()
    @State private var hover: MapPoint?
    var body: some View {
        GeometryReader { proxy in
            let g=MapGeometry(size:proxy.size,zoom:viewport.zoom,pan:viewport.pan)
            ZStack(alignment:.topTrailing) {
                if let frame=model.previewFrame ?? model.frame {
                    TerrainCanvas(frame:frame,geometry:g,power:model.powerOverlay).offset(model.shakeOffset)
                    CivicMapCanvas(frame:frame,geometry:g,layer:model.mapLayer,values:model.overlayValues)
                    Canvas { context,_ in
                        if let p=hover {
                            let rect=g.footprint(p,size:model.tool.size)
                            let color: Color=model.previewStatus==0 ? .accentColor : .red
                            context.fill(Path(rect),with:.color(color.opacity(0.2)))
                            context.stroke(Path(rect),with:.color(color),lineWidth:1)
                        }
                    }
                    .allowsHitTesting(false)
                }
                MapInputView(cancel:{ model.cancelStroke() },down: { point in
                    if let p=g.tile(at:point) { model.beginStroke(MapPoint(x:p.x,y:p.y)) }
                }, drag: { point in
                    if let p=g.tile(at:point) { model.extendStroke(MapPoint(x:p.x,y:p.y)) }
                }, up: { model.endStroke() }, hover: { point in
                    hover=point.flatMap { g.tile(at:$0) }.map { MapPoint(x:$0.x,y:$0.y) }
                }, pan: { delta in model.cancelStroke(); hover=nil; viewport.move(delta,size:proxy.size) }, zoom: { factor,point in
                    model.cancelStroke(); hover=nil; viewport.magnify(factor,at:point,size:proxy.size)
                })
                .allowsHitTesting(model.acceptsMapInput)
                .accessibilityLabel("都市マップ、120列100行。クリック・ドラッグで建設。右ドラッグまたはトラックパッドで移動。")
                VStack(alignment:.trailing,spacing:8) {
                if model.previewFrame != nil {
                    Text("建設費用 \(model.previewCost)\(model.previewInsufficientFunds ? " · 資金不足" : "")")
                        .foregroundStyle(model.previewInsufficientFunds ? .red : .primary)
                    Text("マウスを離すと確定 · Escで取消").font(.caption)
                }
                Picker("マップ表示",selection:Binding(get:{ model.mapLayer },set:{ model.mapLayer=$0 })) {
                    ForEach(CityMapLayer.allCases) { layer in Text(layer.title).tag(layer) }
                }.frame(width:170)
                if model.showOverview, let f=model.frame {
                    let mini=MapGeometry(size:CGSize(width:180,height:150))
                    CivicMapCanvas(frame:f,geometry:mini,layer:model.mapLayer,values:model.overlayValues,overview:true)
                        .frame(width:180,height:150).background(.black)
                        .overlay {
                            let visible=CGRect(x:max(0,-g.rect.minX/g.tileSize)*1.5,y:max(0,-g.rect.minY/g.tileSize)*1.5,
                                               width:min(120,proxy.size.width/g.tileSize)*1.5,height:min(100,proxy.size.height/g.tileSize)*1.5)
                            Path(visible).stroke(.white,lineWidth:1)
                        }
                        .gesture(DragGesture(minimumDistance:0).onChanged { value in
                            if let p=mini.tile(at:value.location) { model.focusPoint=MapPoint(x:p.x,y:p.y) }
                        })
                        .accessibilityLabel("概観マップ。クリックまたはドラッグで表示位置を移動。")
                }
                if model.mapLayer != .all {
                    Text(model.mapLayer == .growth ? "緑: 成長　橙・黄: 減少" : model.mapLayer == .power ? "赤: 通電　青: 未通電　灰: 導電" : "灰 → 黄 → 橙 → 赤: 値が大きい")
                        .font(.caption).frame(maxWidth:220)
                }
                HStack(spacing:8) {
                    Text("\(Int(viewport.zoom*100))%") .monospacedDigit()
                    Button { viewport.magnify(1/1.3,at:CGPoint(x:proxy.size.width/2,y:proxy.size.height/2),size:proxy.size) } label: { Image(systemName:"minus.magnifyingglass") }
                    Button { viewport.magnify(1.3,at:CGPoint(x:proxy.size.width/2,y:proxy.size.height/2),size:proxy.size) } label: { Image(systemName:"plus.magnifyingglass") }
                    Button("全体") { viewport=MapViewport() }
                }
                }
                .buttonStyle(.borderless).padding(8).background(.regularMaterial,in:RoundedRectangle(cornerRadius:8)).padding(8)
            }
            .clipped()
            .onChange(of:g.rect,initial:true) { _,_ in
                if g.tileSize>0 {
                    model.visibleTiles=CGRect(x:-g.rect.minX/g.tileSize,y:-g.rect.minY/g.tileSize,width:proxy.size.width/g.tileSize,height:proxy.size.height/g.tileSize)
                }
            }
            .onChange(of:model.focusPoint) { _,point in
                guard let point else { return }
                viewport.zoom=max(viewport.zoom,3)
                let fresh=MapGeometry(size:proxy.size,zoom:viewport.zoom)
                viewport.pan=CGSize(width:proxy.size.width/2-fresh.rect.minX-(CGFloat(point.x)+0.5)*fresh.tileSize,
                                    height:proxy.size.height/2-fresh.rect.minY-(CGFloat(point.y)+0.5)*fresh.tileSize)
                viewport.clamp(proxy.size)
            }
            .onChange(of:model.zoomCommand) { old,new in
                viewport.magnify(new>old ? 1.3 : 1/1.3,at:CGPoint(x:proxy.size.width/2,y:proxy.size.height/2),size:proxy.size)
            }
            .onChange(of:model.tool) { _,_ in model.cancelStroke() }
            .onChange(of:proxy.size) { _,size in viewport.clamp(size); hover=nil }
        }
    }
}

/// One Canvas for the overview and thematic overlays; map values remain core-owned.
struct CivicMapCanvas: View {
    let frame: CityFrame
    let geometry: MapGeometry
    let layer: CityMapLayer
    let values: [Int16]
    var overview=false
    var body: some View {
        Canvas { context,_ in
            var paths: [Int:Path]=[:]
            for y in geometry.rows { for x in geometry.columns {
                let index=y*120+x, raw=frame.tiles[index], tile=Int(raw & 1023)
                let value=values.count==12000 ? Int(values[index]) : 0
                let bucket=bucket(tile:tile,raw:raw,value:value)
                if bucket != -1 { paths[bucket,default:Path()].addRect(geometry.tileRect(x:x,y:y)) }
            } }
            for (key,path) in paths {
                context.fill(path,with:.color(color(key)),style:FillStyle(antialiased:false))
            }
        }.allowsHitTesting(false)
    }
    private func bucket(tile: Int,raw: UInt16,value: Int) -> Int {
        if overview && layer == .all { return 1000+tile }
        if layer.rawValue>=9 {
            let included: Bool
            switch layer {
            case .residential: included=(240..<423).contains(tile)
            case .commercial: included=(423..<612).contains(tile)
            case .industrial: included=(612..<693).contains(tile) || (844...859).contains(tile) || (884...915).contains(tile)
            default: included=(64..<208).contains(tile) || (224..<240).contains(tile) || (828...831).contains(tile) || (948...951).contains(tile)
            }
            return included || tile < (layer == .transport ? 64 : 240) ? 1000+tile : 20
        }
        if layer == .power {
            if raw & 0x0400 != 0 { return raw & 0x8000 != 0 ? 10 : 11 }
            if raw & 0x4000 != 0 { return 12 }
            return overview ? 1000+(tile<64 ? tile : 0) : -1
        }
        if layer == .all { return overview ? 1000+tile : -1 }
        if layer == .growth {
            if value>100 { return 5 };if value>20 { return 4 }
            if value < -100 { return 6 };if value < -20 { return 7 }
            return overview ? 1000+tile : -1
        }
        let adjusted=layer == .pollution ? value+10 : value
        if adjusted<50 { return overview ? 1000+tile : -1 }
        return min(3,(adjusted-50)/50)
    }
    private func color(_ bucket: Int) -> Color {
        if bucket>=1000 { return TilePalette.color(UInt16(bucket-1000)) }
        let palette: [Int:Color]=[0:.gray,1:.yellow,2:.orange,3:.red,4:Color(red:0,green:0.5,blue:0),5:.green,6:.yellow,7:.orange,10:.red,11:.cyan,12:.gray,20:TilePalette.color(0)]
        return (palette[bucket] ?? .clear).opacity(overview || layer.rawValue>=9 ? 1 : 0.65)
    }
}
