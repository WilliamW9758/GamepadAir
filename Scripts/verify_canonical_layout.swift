// Compile with Sources/GamepadCore/*.swift and Sources/MacSupport/USBMux.swift.
// Default: bounded local API/file check. --phone also creates then removes a test layout
// on the USB-connected iPhone Air and restores its original selection.
import Foundation

@main struct CanonicalIntegration {
    static func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw LayoutDocumentError(message) }
    }
    static func main() async throws {
        let endpoint = ProcessInfo.processInfo.environment["POCKETPAD_TEST_DOWNLOAD_URL"] ?? "http://127.0.0.1:18741/v1/layouts/a5b1594a-0269-4478-8e4c-5f436855be27/revisions/1/download"
        guard let url = URL(string: endpoint) else { throw LayoutDocumentError("Invalid test download URL") }
        let downloaded = try await LayoutDocumentDownload.load(url)
        let file = try LayoutDocumentFile.read(URL(fileURLWithPath: "docs/layout-format/fixtures/keyboard-simple.layout.json"))
        try check(downloaded.document == file.document, "API/file document mismatch")
        try check(downloaded.id != file.id, "Imports reused wrapper IDs")
        print("PASS: live PostgreSQL/API download and file import use identical canonical document and fresh local IDs")
        guard CommandLine.arguments.contains("--phone") else { return }
        let serial = ProcessInfo.processInfo.environment["POCKETPAD_TEST_DEVICE"]
        let devices = try USBMux.devices()
        let device = serial.flatMap { serial in devices.first { $0.serial == serial } } ?? (devices.count == 1 ? devices.first : nil)
        guard let device else { throw LayoutDocumentError("Connect one iPhone by USB, or set POCKETPAD_TEST_DEVICE to its UDID") }
        let socket = try USBMux.connect(device: device, port: StateFrame.port)
        defer { socket.interrupt() }
        try socket.write(StateFrame.hello)
        try socket.write(SetupStage.play.encode())
        var receiver = LayoutTelemetryReceiver()
        func snapshot(ack: String? = nil) throws -> ControllerSnapshot {
            let deadline = ProcessInfo.processInfo.systemUptime + 30
            while ProcessInfo.processInfo.systemUptime < deadline {
                let frame = try socket.readExactly(28, timeout: 5)
                if frame[5] == 3, let value = try receiver.accept(frame), ack == nil || value.acknowledgment?.commandID == ack { return value }
            }
            throw LayoutDocumentError("Timed out waiting for canonical snapshot")
        }
        func send(_ command: LayoutCommand) throws -> ControllerSnapshot {
            try socket.write(command.encode())
            return try snapshot(ack: command.id)
        }
        let initial = try snapshot()
        print("PASS: phone canonical snapshot; \(initial.catalog.count) layouts, canvas \(initial.screen?.width ?? 0) × \(initial.screen?.height ?? 0)")
        var doc = try LayoutDocument.decode(Data(contentsOf: URL(fileURLWithPath: "docs/layout-format/fixtures/two-mode.layout.json")))
        doc.name = "Canonical integration check"
        let create = LayoutCommand(action: .create, document: doc)
        let created = try send(create)
        try check(created.acknowledgment?.error == nil && created.layout.document == doc, "Phone did not persist document")
        let repeated = try send(create)
        try check(repeated.layout.id == created.layout.id && repeated.catalog.count == created.catalog.count, "Duplicate command replayed")
        let mode = LayoutCommand(action: .selectMode, layoutID: created.layout.id, baseEditRevision: created.layout.editRevision, activeModeID: doc.modes[1].id)
        let switched = try send(mode)
        try check(switched.activeModeID == doc.modes[1].id, "Mode ID selection failed")
        let control = doc.controls.first { $0.role == "south" }!
        let actions = doc.actions
        try doc.renameControl(control.id, caption: "Jump test", modeID: doc.modes[1].id)
        try doc.placeControl(control.id, at: DocumentPlacement(x: 0.8, y: 0.5), modeID: doc.modes[1].id)
        let save = LayoutCommand(action: .save, layoutID: created.layout.id, baseEditRevision: created.layout.editRevision, document: doc)
        let saved = try send(save)
        try check(saved.layout.document == doc && saved.layout.document.actions == actions, "Caption/position edit damaged actions")
        let stale = try send(LayoutCommand(action: .save, layoutID: created.layout.id, baseEditRevision: created.layout.editRevision, document: created.layout.document))
        try check(stale.acknowledgment?.error != nil && stale.layout.document == doc, "Stale edit overwrote document")
        let removed = try send(LayoutCommand(action: .delete, layoutID: saved.layout.id, baseEditRevision: saved.layout.editRevision))
        try check(!removed.catalog.contains { $0.id == saved.layout.id }, "Temporary test layout was not removed")
        let original = removed.catalog.first { $0.id == initial.layout.id }!
        let restored = try send(LayoutCommand(action: .select, layoutID: original.id, baseEditRevision: original.editRevision))
        try check(restored.layout.id == initial.layout.id, "Original selection was not restored")
        print("PASS: physical iPhone create/save/mode IDs/idempotent retry/stale conflict/delete; original selection restored")
    }
}
