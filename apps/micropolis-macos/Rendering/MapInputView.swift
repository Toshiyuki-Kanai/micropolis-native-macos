// SPDX-License-Identifier: GPL-3.0-or-later
// AppKit only collects pointer/trackpad events; SwiftUI owns the viewport.
import SwiftUI
import AppKit

struct MapInputView: NSViewRepresentable {
    let down, drag: (CGPoint) -> Void
    let up: () -> Void
    let hover: (CGPoint?) -> Void
    let pan: (CGSize) -> Void
    let zoom: (CGFloat, CGPoint) -> Void
    func makeNSView(context: Context) -> Input { Input() }
    func updateNSView(_ view: Input, context: Context) {
        view.down=down; view.drag=drag; view.up=up; view.hover=hover; view.pan=pan; view.zoom=zoom
    }
    final class Input: NSView {
        var down: (CGPoint)->Void = { _ in }, drag: (CGPoint)->Void = { _ in }
        var up: ()->Void = {}, hover: (CGPoint?)->Void = { _ in }
        var pan: (CGSize)->Void = { _ in }, zoom: (CGFloat,CGPoint)->Void = { _,_ in }
        private var area: NSTrackingArea?
        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            let next=NSTrackingArea(rect:.zero,options:[.activeInKeyWindow,.inVisibleRect,.mouseMoved,.mouseEnteredAndExited],owner:self,userInfo:nil)
            addTrackingArea(next); area=next
        }
        private func point(_ e: NSEvent)->CGPoint { convert(e.locationInWindow,from:nil) }
        override func mouseDown(with e: NSEvent) { window?.makeFirstResponder(self); down(point(e)); hover(point(e)) }
        override func mouseDragged(with e: NSEvent) { drag(point(e)); hover(point(e)) }
        override func mouseUp(with e: NSEvent) { up() }
        override func mouseMoved(with e: NSEvent) { hover(point(e)) }
        override func mouseExited(with e: NSEvent) { hover(nil) }
        override func rightMouseDragged(with e: NSEvent) { pan(CGSize(width:e.deltaX,height:e.deltaY)) }
        override func otherMouseDragged(with e: NSEvent) { pan(CGSize(width:e.deltaX,height:e.deltaY)) }
        override func scrollWheel(with e: NSEvent) {
            if !e.hasPreciseScrollingDeltas || e.modifierFlags.contains(.command) || e.modifierFlags.contains(.option) {
                zoom(exp(e.scrollingDeltaY*0.025),point(e))
            } else { pan(CGSize(width:e.scrollingDeltaX,height:e.scrollingDeltaY)) }
        }
        override func magnify(with e: NSEvent) { zoom(exp(e.magnification),point(e)) }
    }
}
