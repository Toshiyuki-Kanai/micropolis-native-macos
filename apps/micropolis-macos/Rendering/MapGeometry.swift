// SPDX-License-Identifier: GPL-3.0-or-later
import CoreGraphics

struct MapGeometry {
    let tileSize: CGFloat
    let rect: CGRect
    let viewport: CGSize
    init(size: CGSize, zoom: CGFloat = 1, pan: CGSize = .zero) {
        viewport=size
        tileSize = max(0, min(size.width/120, size.height/100)) * zoom
        let width=tileSize*120, height=tileSize*100
        rect=CGRect(x:(size.width-width)/2+pan.width, y:(size.height-height)/2+pan.height, width:width, height:height)
    }
    func tile(at p: CGPoint) -> (x: Int32, y: Int32)? {
        guard tileSize>0, p.x>=rect.minX, p.x<rect.maxX, p.y>=rect.minY, p.y<rect.maxY else { return nil }
        return (Int32((p.x-rect.minX)/tileSize), Int32((p.y-rect.minY)/tileSize))
    }
    func tileRect(x: Int, y: Int) -> CGRect {
        CGRect(x:rect.minX+CGFloat(x)*tileSize, y:rect.minY+CGFloat(y)*tileSize, width:tileSize, height:tileSize)
    }
    var columns: Range<Int> { visible(origin: rect.minX, extent: viewport.width, limit:120) }
    var rows: Range<Int> { visible(origin: rect.minY, extent: viewport.height, limit:100) }
    private func visible(origin: CGFloat, extent: CGFloat, limit: Int) -> Range<Int> {
        guard tileSize>0 else { return 0..<0 }
        let lower=max(0,min(limit,Int(floor(-origin/tileSize))))
        let upper=max(lower,min(limit,Int(ceil((extent-origin)/tileSize))))
        return lower..<upper
    }
    func footprint(_ p: MapPoint, size: Int) -> CGRect {
        let offset=size == 1 ? 0 : 1 // Matches buildBuildingTool's x-1/y-1 anchor.
        let first=tileRect(x:Int(p.x)-offset, y:Int(p.y)-offset)
        return CGRect(origin:first.origin, size:CGSize(width:tileSize*CGFloat(size), height:tileSize*CGFloat(size)))
    }
}

struct MapViewport {
    var zoom: CGFloat=1
    var pan: CGSize = .zero
    mutating func move(_ delta: CGSize, size: CGSize) {
        pan.width += delta.width; pan.height += delta.height; clamp(size)
    }
    mutating func magnify(_ factor: CGFloat, at anchor: CGPoint, size: CGSize) {
        let old=MapGeometry(size:size,zoom:zoom,pan:pan)
        guard old.tileSize>0, factor.isFinite else { return }
        let wx=(anchor.x-old.rect.minX)/old.tileSize, wy=(anchor.y-old.rect.minY)/old.tileSize
        zoom=max(1,min(12,zoom*factor))
        let fresh=MapGeometry(size:size,zoom:zoom)
        pan=CGSize(width:anchor.x-fresh.rect.minX-wx*fresh.tileSize,
                   height:anchor.y-fresh.rect.minY-wy*fresh.tileSize)
        clamp(size)
    }
    mutating func center(at point: CGPoint, size: CGSize) {
        let g=MapGeometry(size:size,zoom:zoom)
        pan=CGSize(width:size.width/2-g.rect.minX-point.x*g.tileSize,
                   height:size.height/2-g.rect.minY-point.y*g.tileSize)
        clamp(size)
    }
    mutating func clamp(_ size: CGSize) {
        let g=MapGeometry(size:size,zoom:zoom)
        let x=max(0,(g.rect.width-size.width)/2), y=max(0,(g.rect.height-size.height)/2)
        pan.width=max(-x,min(x,pan.width)); pan.height=max(-y,min(y,pan.height))
    }
}

/// Four-connected line, so road/wire drag never leaves diagonal gaps.
enum MapPath {
    static func rectangle(_ a: MapPoint,_ b: MapPoint,spacing: Int) -> [MapPoint] {
        let step=max(1,spacing), sx=b.x>=a.x ? step : -step, sy=b.y>=a.y ? step : -step
        let columns=abs(Int(b.x-a.x))/step+1, rows=abs(Int(b.y-a.y))/step+1
        return (0..<rows).flatMap { row in (0..<columns).map { column in
            MapPoint(x:a.x+Int32(column*sx),y:a.y+Int32(row*sy))
        } }
    }
    static func between(_ a: MapPoint, _ b: MapPoint) -> [MapPoint] {
        var x=a.x, y=a.y
        let dx=abs(b.x-x), dy=abs(b.y-y), sx: Int32=x<b.x ? 1 : -1, sy: Int32=y<b.y ? 1 : -1
        var error=dx-dy, result=[a]
        while x != b.x || y != b.y {
            let doubled=2*error
            if doubled > -dy, x != b.x { error -= dy; x += sx; result.append(MapPoint(x:x,y:y)) }
            if doubled < dx, y != b.y { error += dx; y += sy; result.append(MapPoint(x:x,y:y)) }
        }
        return result
    }
}

/// Keeps the grabbed position within the overview frame under the pointer.
struct OverviewDrag {
    private var offset: CGSize?
    mutating func center(start: CGPoint, current: CGPoint, geometry: MapGeometry, viewport: CGRect) -> CGPoint? {
        guard geometry.tileSize>0, !viewport.isNull else { return nil }
        let first=CGPoint(x:(start.x-geometry.rect.minX)/geometry.tileSize,y:(start.y-geometry.rect.minY)/geometry.tileSize)
        if offset == nil {
            guard geometry.rect.contains(start) else { return nil }
            offset=viewport.contains(first) ? CGSize(width:viewport.midX-first.x,height:viewport.midY-first.y) : .zero
        }
        return CGPoint(x:max(0,min(120,(current.x-geometry.rect.minX)/geometry.tileSize+offset!.width)),
                       y:max(0,min(100,(current.y-geometry.rect.minY)/geometry.tileSize+offset!.height)))
    }
    mutating func end() { offset=nil }
}
