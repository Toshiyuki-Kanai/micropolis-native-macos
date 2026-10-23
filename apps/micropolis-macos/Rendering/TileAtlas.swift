// SPDX-License-Identifier: GPL-3.0-or-later
// Original art copyright and provenance: Resources/OriginalGraphics.
import Foundation
import CoreGraphics
import ImageIO

struct TileAtlas: Sendable {
    static let tileSize=16
    static let tileCount=960
    static let idMask: UInt16=0x03ff
    // 956...959 were unused in the original art; the current engine reuses
    // them for extended churches. Never show those unused original cells.
    static func imageIndex(for raw: UInt16) -> Int? {
        let id=Int(raw & idMask)
        return id<956 ? id : nil
    }
    static let bundled: TileAtlas? = {
        guard let url=Bundle.main.url(forResource:"tiles",withExtension:"png",subdirectory:"OriginalGraphics") else { return nil }
        return TileAtlas(url:url)
    }()
    let rgba: [UInt8]
    let images: [CGImage]
    func tileImage(for raw: UInt16) -> CGImage? {
        guard let id=Self.imageIndex(for:raw) else { return nil }
        return images[id]
    }

    init?(url: URL) {
        guard let source=CGImageSourceCreateWithURL(url as CFURL,nil),
              let image=CGImageSourceCreateImageAtIndex(source,0,[kCGImageSourceShouldCacheImmediately:true] as CFDictionary),
              image.width==16, image.height==16*Self.tileCount else { return nil }
        var bytes=[UInt8](repeating:0,count:image.width*image.height*4)
        let decoded=bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context=CGContext(data:buffer.baseAddress,width:image.width,height:image.height,
                                        bitsPerComponent:8,bytesPerRow:image.width*4,
                                        space:CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
            return true
        }
        guard decoded else { return nil }
        rgba=bytes
        guard let provider=CGDataProvider(data:Data(bytes) as CFData),
              let sheet=CGImage(width:16,height:16*Self.tileCount,bitsPerComponent:8,bitsPerPixel:32,
                                bytesPerRow:64,space:CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),
                                provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) else { return nil }
        var tiles: [CGImage]=[]
        for id in 0..<956 {
            guard let tile=sheet.cropping(to:CGRect(x:0,y:id*16,width:16,height:16)) else { return nil }
            tiles.append(tile)
        }
        images=tiles
    }
}

struct TileRegion: Hashable, Sendable {
    let columns: Range<Int>
    let rows: Range<Int>
    init(_ geometry: MapGeometry) { columns=geometry.columns; rows=geometry.rows }
}
struct TileRenderKey: Hashable {
    let revision: UInt64
    let region: TileRegion
}
struct TileChunk: Sendable {
    let x, y, width, height: Int // Map tiles, independent of screen/Retina scale.
    let image: CGImage
    let ids: [UInt16]
    func matches(_ tiles: [UInt16]) -> Bool {
        for row in 0..<height { for column in 0..<width {
            if tiles[(y+row)*120+x+column] & TileAtlas.idMask != ids[row*width+column] { return false }
        } }
        return true
    }
}

/// Only visible chunks are assembled. Immutable images cross the actor boundary;
/// the engine handle and mutable image cache never enter SwiftUI's renderer.
actor TileImageRenderer {
    static let shared=TileImageRenderer(atlas:TileAtlas.bundled)
    static let chunkSize=16
    private let atlas: TileAtlas?
    private struct CachedChunk { let ids: [UInt16]; let chunk: TileChunk }
    private var cache: [Int:CachedChunk]=[:]
    private var rebuilds=0
    init(atlas: TileAtlas?) { self.atlas=atlas }

    func render(_ tiles: [UInt16], region: TileRegion) -> [TileChunk] {
        guard let atlas, tiles.count==12_000, !region.columns.isEmpty, !region.rows.isEmpty else { return [] }
        var result: [TileChunk]=[]
        for cy in (region.rows.lowerBound/16)...((region.rows.upperBound-1)/16) {
            for cx in (region.columns.lowerBound/16)...((region.columns.upperBound-1)/16) {
                let x=cx*16, y=cy*16, width=min(16,120-x), height=min(16,100-y)
                let key=cy*8+cx
                var ids: [UInt16]=[]
                ids.reserveCapacity(width*height)
                for row in y..<(y+height) { for column in x..<(x+width) {
                    ids.append(tiles[row*120+column] & TileAtlas.idMask)
                } }
                if let saved=cache[key], saved.ids==ids { result.append(saved.chunk); continue }
                // Assemble pixels directly: row zero is the top row. No scaling,
                // interpolation, repeated PNG decoding or per-tile SwiftUI View.
                let pixelWidth=width*16, pixelHeight=height*16
                var pixels=[UInt8](repeating:0,count:pixelWidth*pixelHeight*4)
                pixels.withUnsafeMutableBytes { output in
                    atlas.rgba.withUnsafeBytes { source in
                        for (i,id) in ids.enumerated() {
                            guard let tile=TileAtlas.imageIndex(for:id) else { continue }
                            for row in 0..<16 {
                                let src=(tile*256+row*16)*4
                                let dst=((i/width*16+row)*pixelWidth+i%width*16)*4
                                output.baseAddress!.advanced(by:dst).copyMemory(from:source.baseAddress!.advanced(by:src),byteCount:64)
                            }
                        }
                    }
                }
                guard let provider=CGDataProvider(data:Data(pixels) as CFData),
                      let image=CGImage(width:pixelWidth,height:pixelHeight,bitsPerComponent:8,bitsPerPixel:32,
                                        bytesPerRow:pixelWidth*4,space:CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),
                                        provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) else { continue }
                let chunk=TileChunk(x:x,y:y,width:width,height:height,image:image,ids:ids)
                cache[key]=CachedChunk(ids:ids,chunk:chunk)
                rebuilds += 1; result.append(chunk)
            }
        }
        return result
    }
    func statistics() -> (images: Int, rebuilds: Int, bytes: Int) {
        (cache.count,rebuilds,cache.values.reduce(0) { $0+$1.chunk.image.bytesPerRow*$1.chunk.image.height })
    }
}

/// All 57 original frames fit in a small immutable cache (about 0.45 MiB RGBA).
struct SpriteAtlas: Sendable {
    static let frameCounts=[1:5,2:8,3:11,4:8,5:16,6:3,7:6]
    static let bundled=SpriteAtlas(directory:Bundle.main.resourceURL?.appendingPathComponent("OriginalGraphics/Gameplay"))
    let images: [String:CGImage]
    init(directory: URL?) {
        var decoded: [String:CGImage]=[:]
        if let directory {
            for (kind,count) in Self.frameCounts { for frame in 0..<count {
                let key="obj\(kind)-\(frame)"
                let url=directory.appendingPathComponent(key+".png")
                if let source=CGImageSourceCreateWithURL(url as CFURL,nil),
                   let image=CGImageSourceCreateImageAtIndex(source,0,[kCGImageSourceShouldCacheImmediately:true] as CFDictionary) {
                    decoded[key]=image
                }
            } }
        }
        images=decoded
    }
    func image(kind: Int32,frame: Int32) -> CGImage? { images["obj\(kind)-\(frame-1)"] }
}
