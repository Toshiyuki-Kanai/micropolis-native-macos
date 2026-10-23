// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import AppKit

// Exercises real AppKit split views hosted by the production ContentView.
// Runs in its own window and never attaches to an existing game window.
@main struct SidebarLayout {
    enum Failure: Error { case failed(String) }
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        Task {
            do { try await verify(); exit(0) }
            catch { fputs("FAIL sidebar layout: \(error)\n",stderr); exit(1) }
        }
        NSApplication.shared.run()
    }
    @MainActor static func verify() async throws {
        func expect(_ condition: Bool,_ message: String) throws {
            if !condition { throw Failure.failed(message) }
        }
        func descendants<T:NSView>(_ view:NSView,as type:T.Type)->[T] {
            ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { descendants($0,as:type) }
        }
        let model=CityModel()
        await model.newCity()
        let host=NSHostingController(rootView:ContentView(model:model))
        let window=NSWindow(contentViewController:host)
        window.setContentSize(NSSize(width:1200,height:820))
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for:.seconds(1))
        guard let content=window.contentView,
              let horizontal=descendants(content,as:NSSplitView.self).first(where:{ $0.isVertical && $0.arrangedSubviews.count==2 }),
              let vertical=descendants(content,as:NSSplitView.self).first(where:{ !$0.isVertical && $0.arrangedSubviews.count==2 }) else {
            throw Failure.failed("production split views missing")
        }
        // Also shrink the window while the sidebar is wide, without first moving its divider.
        for windowWidth in [1200.0,1600,950,1200] {
            window.setContentSize(NSSize(width:windowWidth,height:820))
            try await Task.sleep(for:.milliseconds(300))
            for requested in [nil,260.0,700,2400,260,2400] as [Double?] {
                if let requested { horizontal.setPosition(requested,ofDividerAt:0) }
                try await Task.sleep(for:.milliseconds(200))
                let pane=vertical.arrangedSubviews[0]
                let global=pane.convert(pane.bounds,to:content)
                let limit=min(content.bounds.width*0.75,content.bounds.width-320)
                try expect(global.minX >= -1,"sidebar must not shift outside left edge")
                try expect(global.maxX <= limit+1,"sidebar divider must remain inside width limit")
                if requested == 2400 {
                    try expect(abs(global.width-limit)<2,"sidebar may expand up to its limit")
                }
                guard let table=descendants(pane,as:NSTableView.self).first else {
                    throw Failure.failed("construction list missing")
                }
                for row in 0..<table.numberOfRows {
                    guard let cell=table.view(atColumn:0,row:row,makeIfNecessary:true) else { continue }
                    let rect=cell.convert(cell.bounds,to:content)
                    try expect(rect.minX >= global.minX-1 && rect.maxX <= global.maxX+1,
                               "construction row \(row) overflow at window width \(windowWidth)")
                }
            }
        }
        let before=vertical.arrangedSubviews[0].frame.height
        vertical.setPosition(max(120,before-100),ofDividerAt:0)
        try await Task.sleep(for:.milliseconds(250))
        try expect(abs(vertical.arrangedSubviews[0].frame.height-before)>50,"overview divider still resizes")
        try expect(!model.dirty && !model.engineFailed,"layout must not edit the city")
        print("PASS sidebar layout: width cap, window shrink, global row bounds, overview divider; city unchanged")
    }
}
