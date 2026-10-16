// SPDX-License-Identifier: GPL-3.0-or-later
import CoreGraphics

/// Logical map coordinates are independent of points, Retina scale and padding.
struct MapGeometry {
    let tileSize: CGFloat
    let rect: CGRect

    init(size: CGSize) {
        tileSize = max(0, min(size.width / CGFloat(CityFrame.width),
                              size.height / CGFloat(CityFrame.height)))
        let width = tileSize * CGFloat(CityFrame.width)
        let height = tileSize * CGFloat(CityFrame.height)
        rect = CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2,
                      width: width, height: height)
    }

    func tile(at point: CGPoint) -> (x: Int32, y: Int32)? {
        guard tileSize > 0, point.x >= rect.minX, point.y >= rect.minY,
              point.x < rect.maxX, point.y < rect.maxY else { return nil }
        return (Int32((point.x - rect.minX) / tileSize),
                Int32((point.y - rect.minY) / tileSize))
    }

    func tileRect(x: Int, y: Int) -> CGRect {
        CGRect(x: rect.minX + CGFloat(x) * tileSize,
               y: rect.minY + CGFloat(y) * tileSize, width: tileSize, height: tileSize)
    }
}
