// SPDX-License-Identifier: GPL-3.0-or-later
// Requires a macOS GUI session; touches only this test's window and city.
import AppKit

@MainActor final class PreviousWindowDelegate: NSObject, NSWindowDelegate {
    var closes=0
    var activations=0
    func windowWillClose(_ notification: Notification) { closes += 1 }
    func windowDidBecomeKey(_ notification: Notification) { activations += 1 }
}
enum WindowTestError: Error { case failed(String) }
@MainActor final class WindowTestAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { .terminateCancel }
}
@main struct WindowLifecycle {
    @MainActor static func main() {
        let application=NSApplication.shared
        let appDelegate=WindowTestAppDelegate()
        application.delegate=appDelegate
        application.setActivationPolicy(.accessory)
        Task {
            do { try await verify(); exit(0) }
            catch {
                FileHandle.standardError.write(Data("FAIL window lifecycle: \(error)\n".utf8))
                exit(1)
            }
        }
        withExtendedLifetime(appDelegate) { application.run() }
    }
    @MainActor static func verify() async throws {
        func expect(_ condition: Bool,_ message: String) throws {
            if !condition { throw WindowTestError.failed(message) }
        }
        let model=CityModel()
        await model.newCity()
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:320,height:160),
                            styleMask:[.titled,.closable],backing:.buffered,defer:false)
        window.title="Micropolis window lifecycle test"
        window.isReleasedWhenClosed=false
        let previous=PreviousWindowDelegate()
        window.delegate=previous
        let bridge=CityWindowBridge.Coordinator(model:model)
        bridge.attach(window)
        window.orderFront(nil)
        try expect(CityWindows.shared.window(for:model) === window,"register city")
        // The first close is deferred for the document gate, then allowed.
        window.performClose(nil)
        for _ in 0..<100 {
            if CityWindows.shared.window(for:model) == nil { break }
            try await Task.sleep(for:.milliseconds(10))
        }
        try expect(!window.isVisible && previous.closes == 1,"close and forward delegate")
        try expect(CityWindows.shared.window(for:model) == nil,"unregister closed city")
        // SwiftUI may reuse the same NSWindow when its singleton is reopened.
        bridge.windowDidBecomeKey(Notification(name:NSWindow.didBecomeKeyNotification,object:window))
        bridge.attach(window) // Repeated representable updates must not self-forward.
        try expect(CityWindows.shared.window(for:model) === window && previous.activations == 1,"reopen registration and delegate forwarding")
        try expect(await model.configureBudget(tax:9,police:1,fire:1,road:1),"edit reopened city")
        try expect(await model.beginDocumentAction(),"hold document gate without showing a sheet")
        // A stale `allow` from the first close would return true and lose edits.
        try expect(!bridge.windowShouldClose(window),"reopened dirty city never reuses close permission")
        try await Task.sleep(for:.milliseconds(50))
        model.endDocumentAction()
        try expect(model.dirty && !model.engineFailed,"cancelled close retains unsaved city")
        window.close()
        print("PASS window lifecycle: deferred close, reopen registration, delegate forwarding, fresh close permission and retained unsaved city")
    }
}
