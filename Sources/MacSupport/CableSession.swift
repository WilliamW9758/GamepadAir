import Foundation
#if SWIFT_PACKAGE
import GamepadCore
#endif

public struct HostUpdate {
    public let message: String
    public let connected: Bool
    public let state: GamepadState
    public let frames: UInt64
    public var interpretedInput = "No input"
    public var finished = false
}

/// One serial worker owns transport and HID writes. Stop interrupts blocking reads.
public final class CableSession {
    public static var gamepadAuthorized: Bool { VirtualGamepadOutput.hasEntitlement }
    private let lock = NSLock()
    private var stopped = false
    private var socket: InputLink?
    private let queue = DispatchQueue(label: "gamepad.cable", qos: .userInteractive)
    private let transport: LinkTransport
    private let wirelessHost: String
    private let pairingCode: String
    private let mode: OutputMode
    private let serial: String?
    private let keyboardProfile: KeyboardProfile
    private let globalInput: Bool
    private let targetPID: Int32?
    private let update: (HostUpdate) -> Void
    private var connectOverride: (() throws -> StreamSocket)?
    private var outputOverride: (() throws -> GamepadOutput)?

    public init(mode: OutputMode, transport: LinkTransport = .usb, wirelessHost: String = "", pairingCode: String = "", serial: String? = nil, keyboardProfile: KeyboardProfile = .starter, targetPID: Int32? = nil, globalInput: Bool = false, update: @escaping (HostUpdate) -> Void) {
        self.transport = transport; self.wirelessHost = wirelessHost; self.pairingCode = pairingCode
        self.mode = mode; self.serial = serial; self.keyboardProfile = keyboardProfile; self.targetPID = targetPID; self.globalInput = globalInput; self.update = update
    }
    convenience init(connect: @escaping () throws -> StreamSocket, output: @escaping () throws -> GamepadOutput, update: @escaping (HostUpdate) -> Void) {
        self.init(mode: .monitor, update: update)
        connectOverride = connect; outputOverride = output
    }
    public func start() { queue.async { self.run() } }
    public func stop() {
        lock.lock(); stopped = true; socket?.interrupt(); lock.unlock()
    }
    private var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    private func announce(_ message: String, state: GamepadState = .neutral, frames: UInt64 = 0, connected: Bool = false, finished: Bool = false) {
        update(HostUpdate(message: message, connected: connected, state: state, frames: frames, finished: finished))
    }
    private func run() {
        let output: GamepadOutput
        do {
            if let outputOverride { output = try outputOverride() }
            else if mode == .gamepad { output = try VirtualGamepadOutput() }
            else if mode == .keyboardMouse { output = try KeyboardMouseOutput(profile: keyboardProfile, targetPID: targetPID, global: globalInput) }
            else { output = MonitorOutput() }
        }
        catch { announce(error.localizedDescription, finished: true); return }
        var endMessage = "Stopped; controls released"
        defer { output.close(); announce(endMessage, finished: true) }
        while !isStopped {
            do {
                let stream: InputLink
                if let connectOverride { stream = try connectOverride() }
                else { stream = try connectTransport() }
                lock.lock(); socket = stream; let cancelled = stopped; lock.unlock()
                if cancelled { stream.interrupt(); break }
                defer { stream.interrupt(); lock.lock(); socket = nil; lock.unlock() }
                if let wifi = stream as? WiFiLink { try wifi.prepare() }
                if let bluetooth = stream as? BluetoothLink { try bluetooth.prepare() }
                try stream.write(StateFrame.hello)
                var sequence = SequenceGuard()
                var count: UInt64 = 0
                while !isStopped {
                    let data = try stream.readExactly(StateFrame.byteCount, timeout: count == 0 ? 3 : 0.25)
                    if data[5] == 2 {
                        let pointer = try PointerFrame(data: data)
                        try sequence.accept(pointer.sequence)
                        try output.pointer(pointer)
                        continue
                    }
                    let frame = try StateFrame(data: data)
                    try sequence.accept(frame.sequence)
                    if frame.state.isPaused { try output.reset() }
                    else { try output.submit(frame.state) }
                    count += 1
                    let status = frame.state.isPaused ? "Layout editing · output paused" :
                        (output as? KeyboardMouseOutput)?.statusDescription ?? (mode == .monitor ? "\(transport.rawValue) connected · monitor only" : "\(transport.rawValue) connected · HID output active")
                    var event = HostUpdate(message: status, connected: true, state: frame.state, frames: count)
                    event.interpretedInput = (output as? KeyboardMouseOutput)?.interpretedInput ?? "See controller indicators below"
                    update(event)
                }
            } catch {
                do { try output.reset() }
                catch { endMessage = "Output failed; restart required: \(error.localizedDescription)"; return }
                announce(error.localizedDescription)
            }
            // Interruptible retry backoff; never runs on the UI thread.
            for _ in 0..<10 { if isStopped { break }; Thread.sleep(forTimeInterval: 0.1) }
        }
    }
    private func connectTransport() throws -> InputLink {
        if transport == .usb { return try connectUSB() }
        guard WirelessSettings.validCode(pairingCode) else { throw LinkError.message("Enter the six-digit pairing code shown on the iPhone") }
        if transport == .bluetooth {
            guard wirelessHost.hasPrefix("ble:"), let id = UUID(uuidString: String(wirelessHost.dropFirst(4))) else { throw LinkError.message("Find and select your iPhone for Bluetooth") }
            return BluetoothLink(code: pairingCode, deviceID: id)
        }
        guard !wirelessHost.trimmingCharacters(in: .whitespaces).isEmpty else { throw LinkError.message("Enter the iPhone Wi-Fi address") }
        return WiFiLink(host: wirelessHost.trimmingCharacters(in: .whitespaces), code: pairingCode)
    }
    private func connectUSB() throws -> StreamSocket {
        let devices = try USBMux.devices().filter { serial == nil || $0.serial == serial }
        guard !devices.isEmpty else { throw LinkError.message("Waiting for USB iPhone. Connect a data cable and trust this Mac.") }
        guard devices.count == 1 else { throw LinkError.message("Multiple USB devices found. Disconnect the others or use --device UDID in the CLI.") }
        return try USBMux.connect(device: devices[0], port: StateFrame.port)
    }
}
