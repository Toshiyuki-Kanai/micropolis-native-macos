// SPDX-License-Identifier: GPL-3.0-or-later
// Narrow SwiftUI window lifecycle adapter; never owns the engine.
import SwiftUI
import AppKit

@MainActor final class CityWindows {
    static let shared=CityWindows()
    struct Entry { weak var window: NSWindow?; weak var model: CityModel? }
    var entries: [ObjectIdentifier: Entry] = [:]
    var createWindow: (() -> Void)?
    private var pendingFiles: [URL] = []
    private var opening=false
    func openFiles(_ urls: [URL]) {
        pendingFiles.append(contentsOf:urls)
        if !entries.values.contains(where:{ $0.window != nil }) { createWindow?() }
        routeFiles()
    }
    func routeFiles() {
        guard !opening, !pendingFiles.isEmpty,
              let entry=entries.values.first(where:{ $0.window?.isKeyWindow == true }) ?? entries.values.first,
              let model=entry.model else { return }
        let url=pendingFiles.removeFirst(); opening=true
        Task {
            await CityFiles.open(model,window:entry.window,url:url)
            opening=false; routeFiles()
        }
    }
    func window(for model: CityModel?) -> NSWindow? {
        entries.values.first { $0.model === model }?.window
    }
}

@MainActor final class CityAppDelegate: NSObject, NSApplicationDelegate {
    private var terminating=false
    func application(_ application: NSApplication, open urls: [URL]) {
        CityWindows.shared.openFiles(urls)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateCancel }
        let entries=Array(CityWindows.shared.entries.values)
        guard entries.contains(where:{ $0.model?.dirty == true || $0.model?.busy == true || $0.model?.started == true || $0.model?.documentBusy == true }) else { return .terminateNow }
        terminating=true
        Task {
            var allow=true
            for entry in entries {
                if let model=entry.model, !(await CityFiles.allowClose(model,window:entry.window)) { allow=false; break }
            }
            terminating=false
            sender.reply(toApplicationShouldTerminate:allow)
        }
        return .terminateLater
    }
}

struct CityWindowBridge: NSViewRepresentable {
    let model: CityModel
    func makeCoordinator() -> Coordinator { Coordinator(model:model) }
    func makeNSView(context: Context) -> HostView {
        let view=HostView()
        view.attach={ [weak coordinator=context.coordinator] window in coordinator?.attach(window) }
        return view
    }
    func updateNSView(_ view: HostView, context: Context) {
        guard let window=view.window else { return }
        context.coordinator.attach(window)
        window.title="\(model.title) — Micropolis Native"
        window.isDocumentEdited=model.dirty
        window.representedURL=model.fileURL
    }
    final class HostView: NSView {
        var attach: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); if let window { attach?(window) } }
    }
    @MainActor final class Coordinator: NSObject, NSWindowDelegate {
        let model: CityModel
        weak var window: NSWindow?
        // NSObject forwarding hooks are nonisolated; AppKit invokes them on the main thread.
        nonisolated(unsafe) private weak var previous: (any NSWindowDelegate)?
        private var allow=false
        private var closing=false
        init(model: CityModel) { self.model=model }
        func attach(_ window: NSWindow) {
            if self.window !== window {
                self.window=window; previous=window.delegate; window.delegate=self
            }
            CityWindows.shared.entries[ObjectIdentifier(window)] = .init(window:window,model:model)
            CityWindows.shared.routeFiles()
        }
        func windowDidBecomeKey(_ notification: Notification) {
            // A singleton SwiftUI Window can reuse its NSWindow after closing.
            // Restore file routing and termination protection on reopening.
            if let window { attach(window) }
            previous?.windowDidBecomeKey?(notification)
        }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            if allow { return true }
            guard !closing else { return false }
            closing=true
            Task {
                let accepted=await CityFiles.allowClose(model,window:sender)
                closing=false
                if accepted { allow=true; sender.performClose(nil) }
            }
            return false
        }
        func windowWillClose(_ notification: Notification) {
            // Permission applies to this close only, never a later reopening.
            allow=false
            if let window { CityWindows.shared.entries.removeValue(forKey:ObjectIdentifier(window)) }
            previous?.windowWillClose?(notification)
        }
        // SwiftUI keeps its own delegate. Forward every other optional callback.
        nonisolated override func responds(to selector: Selector!) -> Bool {
            if super.responds(to:selector) { return true }
            return previous?.responds(to:selector) == true
        }
        nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
            previous?.responds(to:selector) == true ? previous : nil
        }
    }
}
