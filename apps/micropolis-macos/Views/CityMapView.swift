// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct CityMapView: View {
    let frame: CityFrame
    let enabled: Bool
    let build: (Int32, Int32) -> Void

    var body: some View {
        GeometryReader { proxy in
            Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                let geometry = MapGeometry(size: size)
                // Batch the 12,000 rectangles by raw tile ID into Canvas paths.
                var paths: [UInt16: Path] = [:]
                for y in 0..<CityFrame.height {
                    for x in 0..<CityFrame.width {
                        let tile = frame.tiles[y * CityFrame.width + x] & 0x03ff
                        paths[tile, default: Path()].addRect(geometry.tileRect(x: x, y: y))
                    }
                }
                for (tile, path) in paths {
                    context.fill(path, with: .color(TilePalette.color(tile)),
                                 style: FillStyle(antialiased: false))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { point in
                guard enabled, let tile = MapGeometry(size: proxy.size).tile(at: point) else { return }
                build(tile.x, tile.y)
            }
            .accessibilityLabel("都市マップ、120列100行")
            .accessibilityHint("選択中のツールで建設するにはマップをクリックします。")
        }
    }
}
