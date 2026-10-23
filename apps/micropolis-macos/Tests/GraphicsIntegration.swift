// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import ImageIO
import CryptoKit

enum GraphicsTestError: Error { case failed(String) }
func require(_ condition: Bool,_ message: String) throws {
    if !condition { throw GraphicsTestError.failed(message) }
}
@main struct GraphicsIntegration {
    @MainActor static func main() async throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let output=root.appendingPathComponent("build/original-graphics")
        let resources=root.appendingPathComponent("apps/micropolis-macos/Resources/OriginalGraphics")
        let gameplay=resources.appendingPathComponent("Gameplay")
        let soundFiles=try FileManager.default.contentsOfDirectory(at:gameplay,includingPropertiesForKeys:nil).filter { $0.pathExtension=="wav" }
        try require(soundFiles.count==11,"eleven verified original WAV files")
        for url in soundFiles { try require(NSSound(contentsOf:url,byReference:false) != nil,"macOS can decode \(url.lastPathComponent)") }
        print("PASS eleven original WAVs decode with macOS NSSound (playback remains a manual check)")
        let sprites=SpriteAtlas(directory:resources.appendingPathComponent("Gameplay"))
        try require(sprites.images.count==57,"all seven sprite kinds and 57 frames decode")
        for (kind,count) in SpriteAtlas.frameCounts { for frame in 1...count {
            let image=sprites.image(kind:Int32(kind),frame:Int32(frame))
            try require(image != nil && image!.width==(kind<=2 ? 32 : 48),"sprite geometry matches core")
        } }
        try require(sprites.image(kind:8,frame:1)==nil && sprites.image(kind:1,frame:0)==nil,"unsupported/inactive sprites are not drawn")
        print("PASS 57 original sprite frames, seven kinds, dimensions, inactive/unsupported rejection")
        let atlas=TileAtlas(url:resources.appendingPathComponent("tiles.png"))!
        let provenance=try JSONSerialization.jsonObject(with:Data(contentsOf:resources.appendingPathComponent("provenance.json"))) as! [String:Any]
        let generated=provenance["generated"] as! [String:Any]
        let digest=SHA256.hash(data:Data(atlas.rgba)).map { String(format:"%02x",$0) }.joined()
        try require(digest==generated["rgbaSHA256"] as! String,"decoded image matches original XPM pixels and orientation")
        try require(TileAtlas(url:output.appendingPathComponent("absent.png")) == nil,"missing image falls back")
        let corrupt=output.appendingPathComponent("corrupt.png")
        try Data([0,1,2]).write(to:corrupt)
        try require(TileAtlas(url:corrupt) == nil,"corrupt image falls back")
        for raw in UInt32(0)...65535 {
            let id=Int(raw & 0x03ff)
            try require(TileAtlas.imageIndex(for:UInt16(raw)) == (id<956 ? id : nil),"all flags separate from image ID")
        }
        let session=EngineSession()
        let base=try await session.execute(.generate(seed:12345,speed:3))
        try statusBarLayout(base)
        let geometry=MapGeometry(size:CGSize(width:1920,height:1600))
        let renderer=TileImageRenderer(atlas:atlas)
        var tiles=(0..<12000).map { UInt16($0%1024) }
        let start=ContinuousClock.now
        let chunks=await renderer.render(tiles,region:TileRegion(geometry))
        let firstTime=start.duration(to:.now)
        try require(chunks.count==56,"bounded full-map chunks")
        try require(chunks.allSatisfy { $0.matches(tiles) },"cached chunks match live map")
        var previewTiles=tiles;previewTiles[0]=(previewTiles[0]+1)&1023
        try require(!chunks[0].matches(previewTiles),"stale image cannot cover new construction preview")
        previewTiles=tiles;previewTiles[0] ^= 0x8000
        try require(chunks[0].matches(previewTiles),"status flags alone do not invalidate tile art")
        for chunk in chunks {
            let bytes=chunk.image.dataProvider!.data! as Data
            for ty in 0..<chunk.height { for tx in 0..<chunk.width {
                let id=tiles[(chunk.y+ty)*120+chunk.x+tx]
                for row in 0..<16 {
                    let dst=((ty*16+row)*chunk.image.width+tx*16)*4
                    if let image=TileAtlas.imageIndex(for:id) {
                        let src=(image*256+row*16)*4
                        try require(bytes[dst..<(dst+64)].elementsEqual(atlas.rgba[src..<(src+64)]),"every tile row has the correct source pixels")
                    } else {
                        try require(bytes[dst..<(dst+64)].allSatisfy { $0==0 },"extended IDs are transparent for fallback")
                    }
                }
            } }
        }
        let initial=await renderer.statistics()
        let unchangedStart=ContinuousClock.now
        for _ in 0..<100 { _ = await renderer.render(tiles,region:TileRegion(geometry)) }
        let unchangedTime=unchangedStart.duration(to:.now)
        tiles=tiles.map { $0 | 0xfc00 }
        _ = await renderer.render(tiles,region:TileRegion(geometry))
        try require(await renderer.statistics().rebuilds==initial.rebuilds,"unchanged IDs and changed flags reuse images")
        tiles[0]=1
        _ = await renderer.render(tiles,region:TileRegion(geometry))
        try require(await renderer.statistics().rebuilds==initial.rebuilds+1,"one tile rebuilds one chunk")
        let zoomed=MapGeometry(size:CGSize(width:1200,height:1000),zoom:6,pan:CGSize(width:250,height:-300))
        let visible=await renderer.render(tiles,region:TileRegion(zoomed))
        try require(!visible.isEmpty && visible.count<56,"pan and zoom draw visible chunks only")
        let fallback=TileImageRenderer(atlas:nil)
        try require(await fallback.render(tiles,region:TileRegion(geometry)).isEmpty,"failed atlas returns simple-drawing fallback")
        print("PASS 65536 raw values, lossless decoding, all tile rows, missing/corrupt/extended fallback, cache invalidation, visible chunks")
        print("PERF cold full map: \(firstTime); 100 unchanged maps: \(unchangedTime); cache \(initial.images) images / \(initial.bytes) bytes")

        // Render the actual Canvas synchronously at 1x and Retina 2x.
        let plain=(0..<12000).map { UInt16($0%956) }
        let plainChunks=await renderer.render(plain,region:TileRegion(geometry))
        // A chunk may lag one animation/construction frame behind the engine.
        // Rendering must match a fresh chunk, never flash a whole region to colors.
        var previous=plainChunks
        for tick in 0..<8 {
            var changed=plain
            changed[50*120+60]=UInt16(916+tick) // Animated facility cell.
            changed[50*120+61]=UInt16(64+tick) // Neighboring connection change.
            let next=copy(base,tiles:changed)
            let fresh=await renderer.render(changed,region:TileRegion(geometry))
            let lagging=ImageRenderer(content:TileMapCanvas(frame:next,geometry:geometry,power:false,chunks:previous,tileAtlas:atlas,asynchronous:false).frame(width:1920,height:1600))
            let current=ImageRenderer(content:TileMapCanvas(frame:next,geometry:geometry,power:false,chunks:fresh,tileAtlas:atlas,asynchronous:false).frame(width:1920,height:1600))
            guard let laggingImage=lagging.cgImage, let currentImage=current.cgImage else { throw GraphicsTestError.failed("animation patch Canvas") }
            try require(zip(rgba(laggingImage),rgba(currentImage)).allSatisfy { abs(Int($0)-Int($1))<=2 },"lagging animated chunks match current graphics without fallback flash")
            previous=fresh
        }
        print("PASS eight animated/connected tile updates with stale chunk images: identical to fresh Canvas, no region fallback")
        let frame=copy(base,tiles:plain)
        for scale: CGFloat in [1,2] {
            let surface=TileMapCanvas(frame:frame,geometry:geometry,power:false,chunks:plainChunks,asynchronous:false)
                .frame(width:1920,height:1600)
            let rasterStart=ContinuousClock.now
            let imageRenderer=ImageRenderer(content:surface); imageRenderer.scale=scale
            guard let image=imageRenderer.cgImage else { throw GraphicsTestError.failed("Canvas rasterization") }
            print("PERF Canvas offscreen \(Int(scale))x: \(rasterStart.duration(to:.now))")
            try require(image.width==Int(1920*scale) && image.height==Int(1600*scale),"Retina dimensions")
            let actual=rgba(image)
            for id in 0..<956 {
                for (px,py) in [(0,0),(3,7),(15,15)] {
                    let source=(id*256+py*16+px)*4
                    let x=(id%120*16+px)*Int(scale), y=(id/120*16+py)*Int(scale)
                    let offset=(y*image.width+x)*4
                    for c in 0..<3 {
                        try require(abs(Int(actual[offset+c])-Int(atlas.rgba[source+c]))<=2,"Canvas source orientation and colour for tile \(id)")
                    }
                    if scale==2 {
                        for dy in 0..<2 { for dx in 0..<2 {
                            let other=((y+dy)*image.width+x+dx)*4
                            try require(actual[offset..<(offset+4)].elementsEqual(actual[other..<(other+4)]),"Retina pixel blocks have no interpolation")
                        } }
                    }
                }
            }
            try write(image,to:output.appendingPathComponent("all-tiles-\(Int(scale))x.png"))
        }
        var moving=copy(base,tiles:[UInt16](repeating:0,count:12000))
        var samples: [(Int,Int,[UInt8])]=[]
        var transparentSamples: [(Int,Int)]=[]
        var n=0
        for (kind,count) in SpriteAtlas.frameCounts.sorted(by:{ $0.key<$1.key }) { for frame in 1...count {
            let image=sprites.image(kind:Int32(kind),frame:Int32(frame))!
            let x=96+(n%8)*96, y=64+(n/8)*96
            moving.civic.sprites.append(CitySprite(kind:Int32(kind),frame:Int32(frame),x:Int32(x),y:Int32(y),width:Int32(image.width),height:Int32(image.height),offsetX:32,offsetY:-16))
            let pixels=rgba(image)
            if let opaque=(0..<(image.width*image.height)).first(where:{ pixels[$0*4+3]==255 }) {
                samples.append((x+32+opaque%image.width,y-16+opaque/image.width,Array(pixels[opaque*4..<(opaque*4+4)])))
            } else {
                try require(stride(from:3,to:pixels.count,by:4).allSatisfy { pixels[$0]==0 },"invisible frame is fully transparent")
                transparentSamples.append((x+32+image.width/2,y-16+image.height/2))
            }
            n += 1
        } }
        let spriteRenderer=ImageRenderer(content:TileMapCanvas(frame:moving,geometry:geometry,power:false,chunks:[],spriteAtlas:sprites,asynchronous:false).frame(width:1920,height:1600))
        guard let spriteImage=spriteRenderer.cgImage else { throw GraphicsTestError.failed("sprite Canvas") }
        let spritePixels=rgba(spriteImage)
        for (x,y,pixel) in samples { for channel in 0..<3 {
            try require(abs(Int(spritePixels[(y*spriteImage.width+x)*4+channel])-Int(pixel[channel]))<=3,"sprite frame and native offset are rendered accurately")
        } }
        for (x,y) in transparentSamples {
            try require(spritePixels[(y*spriteImage.width+x)*4..<(y*spriteImage.width+x)*4+4].elementsEqual(spritePixels[0..<4]),"invisible train frame leaves city background unchanged")
        }
        try write(spriteImage,to:output.appendingPathComponent("all-sprites.png"))
        print("PASS all 57 sprite frames through actual Canvas with core pixel offsets and no interpolation")
        let fallbackRenderer=ImageRenderer(content:TileMapCanvas(frame:frame,geometry:geometry,power:false,chunks:[],asynchronous:false).frame(width:1920,height:1600))
        try require(fallbackRenderer.cgImage != nil,"actual Canvas fallback rasterizes")
        for viewport in [zoomed,MapGeometry(size:CGSize(width:900,height:700),zoom:2.3,pan:CGSize(width:-123,height:99))] {
            let images=await renderer.render(plain,region:TileRegion(viewport))
            let view=TileMapCanvas(frame:frame,geometry:viewport,power:false,chunks:images,asynchronous:false)
                .frame(width:viewport.viewport.width,height:viewport.viewport.height)
            let image=ImageRenderer(content:view).cgImage!
            let pixels=rgba(image)
            for y in viewport.rows { for x in viewport.columns {
                let rect=viewport.tileRect(x:x,y:y)
                let sx=Int(floor(rect.midX)), sy=Int(floor(rect.midY))
                guard sx>=0,sy>=0,sx<image.width,sy<image.height else { continue }
                let px=min(15,max(0,Int(floor((CGFloat(sx)+0.5-rect.minX)/viewport.tileSize*16))))
                let py=min(15,max(0,Int(floor((CGFloat(sy)+0.5-rect.minY)/viewport.tileSize*16))))
                let source=(Int(plain[y*120+x])*256+py*16+px)*4
                let target=(sy*image.width+sx)*4
                for c in 0..<3 {
                    try require(abs(Int(pixels[target+c])-Int(atlas.rgba[source+c]))<=2,"pan/zoom/resize uses the same tile coordinates for pixels")
                }
            } }
        }
        let grown=try await session.execute(.load(root.appendingPathComponent("build/native/gameplay-grown.cty")))
        let grownChunks=await renderer.render(grown.tiles,region:TileRegion(geometry))
        let grownRenderer=ImageRenderer(content:TileMapCanvas(frame:grown,geometry:geometry,power:false,chunks:grownChunks,asynchronous:false).frame(width:1920,height:1600))
        try write(grownRenderer.cgImage!,to:output.appendingPathComponent("grown-city.png"))
        _ = try await session.execute(.paused(false))
        for _ in 0..<200 {
            let next=try await session.execute(.step(8))
            _ = await renderer.render(next.tiles,region:TileRegion(zoomed))
        }
        try require(await renderer.statistics().images<=56,"cache stays bounded through simulation and city replacement")
        let haight=try await session.execute(.load(root.appendingPathComponent("content/micropolis/cities/haight.cty")))
        let haightChunks=await renderer.render(haight.tiles,region:TileRegion(geometry))
        let haightRenderer=ImageRenderer(content:TileMapCanvas(frame:haight,geometry:geometry,power:false,chunks:haightChunks,asynchronous:false).frame(width:1920,height:1600))
        try write(haightRenderer.cgImage!,to:output.appendingPathComponent("haight.png"))
        print("PASS actual Canvas at 1x/2x, orientation, nearest pixels, pan/zoom/resize, fallback, saved city/haight rendering and 200 simulation/render updates")
    }
    @MainActor static func statusBarLayout(_ base: CityFrame) throws {
        let small=CityFrame(tiles:base.tiles,funds:1,population:1,populationPending:false,time:base.time,year:base.year,month:base.month,speed:base.speed,paused:true,details:base.details,revision:base.revision)
        let large=CityFrame(tiles:base.tiles,funds:2_000_000_000,population:9_999_999,populationPending:false,time:base.time,year:base.year,month:base.month,speed:base.speed,paused:true,details:base.details,revision:base.revision)
        var previousHeight=Int.max
        for width in [320,640,1000] {
            let first=ImageRenderer(content:CityStatusBar(frame:small).frame(width:CGFloat(width)))
            let second=ImageRenderer(content:CityStatusBar(frame:large).frame(width:CGFloat(width)))
            guard let a=first.cgImage,let b=second.cgImage else { throw GraphicsTestError.failed("status grid snapshot") }
            try require(a.width==b.width && a.height==b.height,"number of digits never changes status layout dimensions")
            let pa=rgba(a),pb=rgba(b)
            // The headings precede values in every fixed-height row. Their
            // rendered positions must remain identical when values grow.
            for rowTop in stride(from:12,to:a.height-12,by:78) {
                for y in rowTop..<min(rowTop+38,a.height) {
                    let start=y*a.width*4,end=(y+1)*a.width*4
                    try require(pa[start..<end].elementsEqual(pb[start..<end]),"funds/population updates never move status headings")
                }
            }
            try require(a.height<=previousHeight,"wider detail uses fewer status rows")
            previousHeight=a.height
        }
        print("PASS status grid at 320/640/1000pt: digit-independent headings and width-dependent wrapping")
    }
    static func copy(_ f: CityFrame,tiles: [UInt16]) -> CityFrame {
        CityFrame(tiles:tiles,funds:f.funds,population:f.population,populationPending:f.populationPending,time:f.time,year:f.year,month:f.month,speed:f.speed,paused:f.paused,details:f.details,revision:f.revision)
    }
    static func write(_ image: CGImage,to url: URL) throws {
        guard let destination=CGImageDestinationCreateWithURL(url as CFURL,"public.png" as CFString,1,nil) else { throw GraphicsTestError.failed("PNG destination") }
        CGImageDestinationAddImage(destination,image,nil)
        try require(CGImageDestinationFinalize(destination),"PNG export")
    }
    static func rgba(_ image: CGImage) -> [UInt8] {
        var bytes=[UInt8](repeating:0,count:image.width*image.height*4)
        bytes.withUnsafeMutableBytes { buffer in
            let context=CGContext(data:buffer.baseAddress,width:image.width,height:image.height,bitsPerComponent:8,
                                  bytesPerRow:image.width*4,space:CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
        }
        return bytes
    }
}
