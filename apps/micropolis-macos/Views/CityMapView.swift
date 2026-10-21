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
