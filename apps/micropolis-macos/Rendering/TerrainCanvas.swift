// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct TerrainCanvas: View {
    let frame: CityFrame
    let geometry: MapGeometry
    let power: Bool
    @State private var chunks: [TileChunk]=[]
    var body: some View {
        TileMapCanvas(frame:frame,geometry:geometry,power:power,chunks:chunks)
            .task(id:TileRenderKey(revision:frame.revision,region:TileRegion(geometry))) {
                let images=await TileImageRenderer.shared.render(frame.tiles,region:TileRegion(geometry))
                if !Task.isCancelled { chunks=images }
            }
            .overlay(alignment:.bottomLeading) {
                if TileAtlas.bundled == nil {
                    Text("タイル画像を読み込めないため簡易表示中")
                        .font(.caption).padding(6).background(.regularMaterial).padding(8)
                }
            }
    }
}

/// Pure drawing surface shared by the app and offscreen rendering tests.
struct TileMapCanvas: View {
    let frame: CityFrame
    let geometry: MapGeometry
    let power: Bool
    let chunks: [TileChunk]
    var asynchronous=true
    var body: some View {
        Canvas(opaque:false,rendersAsynchronously:asynchronous) { context,_ in
            let g=geometry
            // Also covers unsupported extended IDs, decode failure and a newly
            // exposed viewport while its images are being built off MainActor.
            var paths: [UInt16:Path]=[:]
            for y in g.rows { for x in g.columns {
                let id=frame.tiles[y*120+x] & TileAtlas.idMask
                paths[id,default:Path()].addRect(g.tileRect(x:x,y:y))
            } }
            for (tile,path) in paths { context.fill(path,with:.color(TilePalette.color(tile)),style:FillStyle(antialiased:false)) }
            for chunk in chunks {
                let origin=g.tileRect(x:chunk.x,y:chunk.y).origin
                let rect=CGRect(origin:origin,size:CGSize(width:CGFloat(chunk.width)*g.tileSize,height:CGFloat(chunk.height)*g.tileSize))
                context.draw(Image(decorative:chunk.image,scale:1,orientation:.up).interpolation(.none),in:rect)
            }
            let drawn=Set(chunks.map { ($0.y/16)*8+$0.x/16 })
            for y in g.rows { for x in g.columns {
                let raw=frame.tiles[y*120+x], id=raw & TileAtlas.idMask, r=g.tileRect(x:x,y:y)
                let illustrated=TileAtlas.imageIndex(for:raw) != nil && drawn.contains((y/16)*8+x/16)
                if power, raw & 0x4000 != 0 {
                    if raw & 0x0400 != 0 {
                        context.fill(Path(r),with:.color(raw & 0x8000 != 0 ? .yellow.opacity(0.5) : .red.opacity(0.5)))
                    } else { context.stroke(Path(r.insetBy(dx:0.5,dy:0.5)),with:.color(.yellow.opacity(0.4)),lineWidth:1) }
                }
                if raw & 0x0400 != 0 {
                    if raw & 0x8000 == 0 {
                        context.stroke(Path(r.insetBy(dx:1,dy:1)),with:.color(.red),lineWidth:1.5)
                    }
                    if !illustrated, g.tileSize>=8, let symbol=TilePalette.symbol(raw) {
                        context.draw(Text(symbol).font(.system(size:max(7,g.tileSize*0.8),weight:.bold)).foregroundStyle(.black),at:CGPoint(x:r.midX,y:r.midY))
                    }
                } else if !illustrated, g.tileSize>=6 {
                    if (208...223).contains(id) || (224...238).contains(id) {
                        context.stroke(Path(r.insetBy(dx:g.tileSize*0.28,dy:g.tileSize*0.28)),with:.color(id<224 ? .black : .white),lineWidth:1)
                    } else if (249...404).contains(id) || (432...611).contains(id) || (621...692).contains(id) {
                        context.fill(Path(r.insetBy(dx:g.tileSize*0.28,dy:g.tileSize*0.28)),with:.color(.black.opacity(0.22)))
                    }
                }
            } }
        }
    }
}
