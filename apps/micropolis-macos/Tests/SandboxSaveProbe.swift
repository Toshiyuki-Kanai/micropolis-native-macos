// SPDX-License-Identifier: GPL-3.0-or-later
// Separate sandboxed app: LaunchServices grants only the disposable input file.
import AppKit
import MicropolisNative

@MainActor final class SaveProbeDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url=urls.first else { return }
        Task {
            var report: String
            do {
                let before=try Data(contentsOf:url)
                var pointer: OpaquePointer?
                guard mp_create(&pointer) == MP_OK, let pointer else { throw ProbeError.failed("create") }
                defer { mp_destroy(pointer) }
                // Reproduce the old implementation under a real file grant.
                let direct=url.path.withCString { mp_save_city(pointer,$0) }
                guard direct == MP_IO_ERROR, try Data(contentsOf:url) == before else {
                    throw ProbeError.failed("expected sibling-temp denial without changing original: \(direct)")
                }
                let session=EngineSession()
                let initial=try await session.execute(.generate(seed:12345,speed:3))
                // The fixture is disposable. Keep its grant while testing a new
                // file at the selected path, then an atomic existing-file save.
                try FileManager.default.removeItem(at:url)
                _ = try await session.execute(.save(url))
                let first=try Data(contentsOf:url)
                _ = try await session.execute(.budget(tax:9,police:0.4,fire:0.6,road:0.8))
                _ = try await session.execute(.save(url))
                let second=try Data(contentsOf:url)
                guard first != second else { throw ProbeError.failed("overwrite did not update bytes") }
                let reopened=EngineSession()
                let restored=try await reopened.execute(.load(url))
                guard restored.funds == initial.funds, restored.time == initial.time,
                      restored.details.taxRate == 9 else { throw ProbeError.failed("restored state") }
                report="PASS sandbox: old sibling-temp denied; new save, overwrite, reopen and state restoration succeeded"
            } catch { report="FAIL \(error)" }
            let result=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/\(url.lastPathComponent).result")
            try? FileManager.default.createDirectory(at:result.deletingLastPathComponent(),withIntermediateDirectories:true)
            try? report.write(to:result,atomically:true,encoding:.utf8)
            application.terminate(nil)
        }
    }
}
enum ProbeError: Error { case failed(String) }
@main struct SandboxSaveProbe {
    @MainActor static func main() {
        let app=NSApplication.shared
        let delegate=SaveProbeDelegate()
        app.delegate=delegate
        app.setActivationPolicy(.prohibited)
        withExtendedLifetime(delegate) { app.run() }
    }
}
