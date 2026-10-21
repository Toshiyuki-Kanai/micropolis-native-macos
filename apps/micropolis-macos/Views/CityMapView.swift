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
                if let frame=model.frame {
                    TerrainCanvas(frame:frame,geometry:g,power:model.powerOverlay)
                    Canvas { context,_ in
                        if let p=hover {
                            let rect=g.footprint(p,size:model.tool.size)
                            context.fill(Path(rect),with:.color(.accentColor.opacity(0.2)))
                            context.stroke(Path(rect),with:.color(.primary),lineWidth:1)
                        }
                    }
                    .allowsHitTesting(false)
                }
                MapInputView(down: { point in
                    if let p=g.tile(at:point) { model.beginStroke(MapPoint(x:p.x,y:p.y)) }
                }, drag: { point in
                    if let p=g.tile(at:point) { model.extendStroke(MapPoint(x:p.x,y:p.y)) }
                    else { model.endStroke() }
                }, up: { model.endStroke() }, hover: { point in
                    hover=point.flatMap { g.tile(at:$0) }.map { MapPoint(x:$0.x,y:$0.y) }
                }, pan: { delta in model.endStroke(); hover=nil; viewport.move(delta,size:proxy.size) }, zoom: { factor,point in
                    model.endStroke(); hover=nil; viewport.magnify(factor,at:point,size:proxy.size)
                })
                .allowsHitTesting(model.acceptsMapInput)
                .accessibilityLabel("都市マップ、120列100行。クリック・ドラッグで建設。右ドラッグまたはトラックパッドで移動。")
                HStack(spacing:8) {
                    Text("\(Int(viewport.zoom*100))%") .monospacedDigit()
                    Button { viewport.magnify(1/1.3,at:CGPoint(x:proxy.size.width/2,y:proxy.size.height/2),size:proxy.size) } label: { Image(systemName:"minus.magnifyingglass") }
                    Button { viewport.magnify(1.3,at:CGPoint(x:proxy.size.width/2,y:proxy.size.height/2),size:proxy.size) } label: { Image(systemName:"plus.magnifyingglass") }
                    Button("全体") { viewport=MapViewport() }
                }
                .buttonStyle(.borderless).padding(8).background(.regularMaterial,in:RoundedRectangle(cornerRadius:8)).padding(8)
            }
            .clipped()
            .onChange(of:model.tool) { _,_ in model.endStroke() }
            .onChange(of:proxy.size) { _,size in viewport.clamp(size); hover=nil }
        }
    }
}

private struct TerrainCanvas: View {
    let frame: CityFrame
    let geometry: MapGeometry
    let power: Bool
    var body: some View {
        Canvas(opaque:false,rendersAsynchronously:true) { context,_ in
            let g=geometry
            var paths: [UInt16:Path]=[:]
            for y in g.rows { for x in g.columns {
                let raw=frame.tiles[y*120+x], id=raw & 0x03ff
                paths[id,default:Path()].addRect(g.tileRect(x:x,y:y))
            } }
            for (tile,path) in paths { context.fill(path,with:.color(TilePalette.color(tile)),style:FillStyle(antialiased:false)) }
            for y in g.rows { for x in g.columns {
                let raw=frame.tiles[y*120+x], id=raw & 0x03ff, r=g.tileRect(x:x,y:y)
                if power, raw & 0x4000 != 0 {
                    // Power is stored on zone centers, not every conductive tile.
                    if raw & 0x0400 != 0 {
                        context.fill(Path(r),with:.color(raw & 0x8000 != 0 ? .yellow : .red))
                    } else { context.stroke(Path(r.insetBy(dx:0.5,dy:0.5)),with:.color(.yellow.opacity(0.4)),lineWidth:1) }
                }
                if raw & 0x0400 != 0 {
                    if raw & 0x8000 == 0 {
                        context.stroke(Path(r.insetBy(dx:1,dy:1)),with:.color(.red),lineWidth:1.5)
                    }
                    if g.tileSize>=8, let symbol=TilePalette.symbol(raw) {
                        context.draw(Text(symbol).font(.system(size:max(7,g.tileSize*0.8),weight:.bold)).foregroundStyle(.black),at:CGPoint(x:r.midX,y:r.midY))
                    }
                } else if g.tileSize>=6 {
                    // Minimal original line work distinguishes utilities at high zoom.
                    if (208...223).contains(id) || (224...238).contains(id) {
                        let inset=r.insetBy(dx:g.tileSize*0.28,dy:g.tileSize*0.28)
                        context.stroke(Path(inset),with:.color(id<224 ? .black : .white),lineWidth:1)
                    } else if (249...404).contains(id) || (432...611).contains(id) || (621...692).contains(id) {
                        context.fill(Path(r.insetBy(dx:g.tileSize*0.28,dy:g.tileSize*0.28)),with:.color(.black.opacity(0.22)))
                    }
                }
            } }
        }
    }
}
