// SPDX-License-Identifier: GPL-3.0-or-later
// Standard macOS panels and scoped bookmarks, modified 2026-10-17.
import AppKit
import UniformTypeIdentifiers
import Observation

@Observable @MainActor
final class RecentCities {
    static let shared=RecentCities()
    struct Entry: Codable, Identifiable {
        let id: UUID
        let name: String
        let bookmark: Data
    }
    private(set) var entries: [Entry] = []
    private init() {
        if let data=UserDefaults.standard.data(forKey:"recentCities"),
           let decoded=try? JSONDecoder().decode([Entry].self,from:data) { entries=decoded }
    }
    func remember(_ url: URL) {
        let scoped=url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data=try? url.bookmarkData(options:.withSecurityScope, includingResourceValuesForKeys:nil,relativeTo:nil) else { return }
        entries.removeAll { entry in (try? resolve(entry).standardizedFileURL) == url.standardizedFileURL }
        entries.insert(Entry(id:UUID(),name:url.lastPathComponent,bookmark:data),at:0)
        entries=Array(entries.prefix(10)); persist()
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }
    func resolve(_ entry: Entry) throws -> URL {
        var stale=false
        return try URL(resolvingBookmarkData:entry.bookmark,options:[.withSecurityScope,.withoutUI],relativeTo:nil,bookmarkDataIsStale:&stale)
    }
    func clear() { entries=[]; persist(); NSDocumentController.shared.clearRecentDocuments(nil) }
    private func persist() { UserDefaults.standard.set(try? JSONEncoder().encode(entries),forKey:"recentCities") }
}

@MainActor enum CityFiles {
    static let cityType=UTType(exportedAs:"org.micropolis.city",conformingTo:.data)
    static func openWithoutCity() async {
        let panel=NSOpenPanel()
        panel.allowedContentTypes=[cityType]; panel.allowsOtherFileTypes=true
        panel.canChooseDirectories=false; panel.allowsMultipleSelection=false
        if await present(panel,window:nil) == .OK, let url=panel.url { CityWindows.shared.openFiles([url]) }
    }
    static func newCity(_ model: CityModel, window: NSWindow?) async {
        guard await model.beginDocumentAction() else { return }
        defer { model.endDocumentAction() }
        guard await ready(window) else { return }
        model.panel = .newCity
    }
    static func createSelected(_ model: CityModel, window: NSWindow?, seed: Int32, level: Int32) async {
        guard await model.beginDocumentAction() else { return }
        defer { model.endDocumentAction() }
        guard await ready(window), await mayDiscard(model,window:window) else { return }
        await model.newCity(seed:seed,level:level)
    }
    static func open(_ model: CityModel, window: NSWindow?, url: URL? = nil) async {
        if let url, focusExisting(url,excluding:model) { return }
        guard await model.beginDocumentAction() else { return }
        defer { model.endDocumentAction() }
        guard await ready(window) else { return }
        guard await mayDiscard(model,window:window) else { return }
        var selected=url
        if selected == nil {
            let panel=NSOpenPanel()
            panel.allowedContentTypes=[cityType]; panel.allowsOtherFileTypes=true
            panel.canChooseDirectories=false; panel.allowsMultipleSelection=false
            guard await present(panel, window:window) == .OK else { return }
            selected=panel.url
        }
        if let selected {
            if focusExisting(selected,excluding:model) { return }
            if await model.load(selected) { RecentCities.shared.remember(selected) }
        }
    }
    static func save(_ model: CityModel, window: NSWindow?, saveAs: Bool = false) async -> Bool {
        guard await model.beginDocumentAction() else { return false }
        defer { model.endDocumentAction() }
        guard await ready(window) else { return false }
        return await saveLocked(model,window:window,saveAs:saveAs)
    }
    static func allowClose(_ model: CityModel, window: NSWindow?) async -> Bool {
        guard await model.beginDocumentAction() else { return false }
        defer { model.endDocumentAction() }
        guard await ready(window) else { return false }
        return await mayDiscard(model,window:window)
    }
    private static func focusExisting(_ url: URL, excluding model: CityModel) -> Bool {
        for entry in CityWindows.shared.entries.values {
            if let other=entry.model, other !== model,
               other.fileURL?.standardizedFileURL == url.standardizedFileURL,
               let window=entry.window { window.makeKeyAndOrderFront(nil); return true }
        }
        return false
    }
    private static func ready(_ window: NSWindow?) async -> Bool {
        // Let a dismissed SwiftUI inspector/alert detach before another sheet.
        for _ in 0..<40 {
            if window?.attachedSheet == nil { return true }
            try? await Task.sleep(for:.milliseconds(25))
        }
        return false // Never stack a save/confirmation sheet over an active one.
    }
    private static func mayDiscard(_ model: CityModel, window: NSWindow?) async -> Bool {
        guard model.dirty else { return true }
        let alert=NSAlert()
        alert.messageText="「\(model.title)」の変更を保存しますか？"
        alert.informativeText="保存しない変更は失われます。"
        alert.addButton(withTitle:"保存"); alert.addButton(withTitle:"キャンセル"); alert.addButton(withTitle:"保存しない")
        alert.buttons[2].hasDestructiveAction=true
        let response: NSApplication.ModalResponse
        if let window { response=await alert.beginSheetModal(for:window) }
        else { response=alert.runModal() }
        switch response {
        case .alertFirstButtonReturn: return await saveLocked(model,window:window,saveAs:false)
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }
    private static func saveLocked(_ model: CityModel, window: NSWindow?, saveAs: Bool) async -> Bool {
        guard !model.engineFailed else {
            model.errorMessage="エンジンに障害があるため保存できません。元のファイルは変更していません。"; return false
        }
        var target=saveAs ? nil : model.fileURL
        if target == nil {
            let panel=NSSavePanel()
            panel.allowedContentTypes=[cityType]; panel.canCreateDirectories=true
            panel.nameFieldStringValue=(model.fileURL?.lastPathComponent ?? "名称未設定.cty")
            guard await present(panel,window:window) == .OK else { return false }
            target=panel.url
        }
        guard let target else { return false }
        if focusExisting(target,excluding:model) {
            model.errorMessage="保存先は別のウインドウで開いています。別の名前で保存してください。"; return false
        }
        guard await model.save(to:target) else { return false }
        RecentCities.shared.remember(target)
        return true
    }
    private static func present(_ panel: NSSavePanel, window: NSWindow?) async -> NSApplication.ModalResponse {
        if let window { return await panel.beginSheetModal(for:window) }
        return await withCheckedContinuation { c in panel.begin { c.resume(returning:$0) } }
    }
}
