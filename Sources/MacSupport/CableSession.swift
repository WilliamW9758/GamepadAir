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
    public var layout: ControllerSnapshot?
}

/// One serial worker owns transport and HID writes. Stop interrupts blocking reads.
public final class CableSession {
    public static var gamepadAuthorized: Bool { VirtualGamepadOutput.hasEntitlement }
    private let lock = NSLock()
    private var stopped = false
    private var setupStage: SetupStage?
    public func setSetupStage(_ stage: SetupStage) {
        lock.lock(); setupStage = stage; lock.unlock()
    }
    private var currentSetupStage: SetupStage? {
        lock.lock(); defer { lock.unlock() }; return setupStage
    }
    private var outputPaused = false
    private var pendingMappings: (KeyboardProfile, GamepadProfile)?
    public func setOutputPaused(_ paused: Bool) {
        lock.lock(); outputPaused = paused; lock.unlock()
    }
    public func updateMappings(keyboard: KeyboardProfile, gamepad: GamepadProfile) {
        lock.lock(); pendingMappings = (keyboard, gamepad); lock.unlock()
    }
    private var isOutputPaused: Bool {
        lock.lock(); defer { lock.unlock() }; return outputPaused
    }
    private func takeMappings() -> (KeyboardProfile, GamepadProfile)? {
        lock.lock(); defer { lock.unlock() }
        guard !outputPaused else { return nil }
        let value = pendingMappings; pendingMappings = nil; return value
    }
    private var commandBytes = Data()
    public func sendLayoutCommand(_ command: LayoutCommand) throws {
        let bytes = try command.encode()
        lock.lock(); defer { lock.unlock() }
        guard commandBytes.isEmpty else { throw LinkError.message("A layout change is already sending") }
        commandBytes = bytes
    }
    private func nextCommandBytes() -> Data {
        lock.lock(); defer { lock.unlock() }
        let part = Data(commandBytes.prefix(64)); commandBytes.removeFirst(part.count); return part
    }
    private var socket: InputLink?
    private let queue = DispatchQueue(label: "gamepad.cable", qos: .userInteractive)
    private let transport: LinkTransport
    private let wirelessHost: String
    private let pairingCode: String
    private let mode: OutputMode
    private let serial: String?
    private let keyboardProfile: KeyboardProfile
    private let gamepadProfile: GamepadProfile
    private let globalInput: Bool
    private let targetPID: Int32?
    private let update: (HostUpdate) -> Void
    private var connectOverride: (() throws -> StreamSocket)?
    private var outputOverride: (() throws -> GamepadOutput)?

    public init(mode: OutputMode, transport: LinkTransport = .usb, wirelessHost: String = "", pairingCode: String = "", serial: String? = nil, keyboardProfile: KeyboardProfile = .starter, gamepadProfile: GamepadProfile = GamepadProfile(), targetPID: Int32? = nil, globalInput: Bool = false, update: @escaping (HostUpdate) -> Void) {
        self.transport = transport; self.wirelessHost = wirelessHost; self.pairingCode = pairingCode
        self.mode = mode; self.serial = serial; self.keyboardProfile = keyboardProfile; self.gamepadProfile = gamepadProfile; self.targetPID = targetPID; self.globalInput = globalInput; self.update = update
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
        var output: GamepadOutput
        do {
            if let outputOverride { output = try outputOverride() }
            // Wait for the phone layout before publishing its controller identity.
            else if mode == .gamepad || isOutputPaused { output = MonitorOutput() }
            else if mode == .keyboardMouse { output = try KeyboardMouseOutput(profile: keyboardProfile, targetPID: targetPID, global: globalInput) }
            else { output = MonitorOutput() }
        }
        catch { announce(error.localizedDescription, finished: true); return }
        var activeMode = mode
        var activeGamepad = gamepadProfile
        var activeStyle: PadStyle = .xbox
        var appliedLayout: SavedLayout?
        var outputFailure: String?
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
                var sentSetupStage: SetupStage?
                var sequence = SequenceGuard()
                var count: UInt64 = 0
                var layoutReceiver = LayoutTelemetryReceiver()
                var phoneLayout: ControllerSnapshot?
                var stateDeadline = ProcessInfo.processInfo.systemUptime + 3
                var lastRumble = RumbleFrame()
                var lastRumbleSent: TimeInterval = 0
                while !isStopped {
                    let command = nextCommandBytes()
                    if !command.isEmpty { try stream.write(command) }
                    if let stage = currentSetupStage, stage != sentSetupStage, stage != .play || count > 0 {
                        try stream.write(stage.encode()); sentSetupStage = stage
                    }
                    let remaining = stateDeadline - ProcessInfo.processInfo.systemUptime
                    guard remaining > 0 else { throw LinkError.message("Controller heartbeat timed out; controls released") }
                    let data = try stream.readExactly(StateFrame.byteCount, timeout: remaining)
                    if data[5] == 3 {
                        let bytes = Array(data)
                        let number = (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[8 + $1]) << (8 * $1) }
                        try sequence.accept(number)
                        if let snapshot = try layoutReceiver.accept(data) {
                            phoneLayout = snapshot
                            var resolved = snapshot.layout
                            resolved.inputType = resolved.inputType ?? (mode == .gamepad ? .gamepad : .keyboardMouse)
                            resolved.keyboardProfile = resolved.keyboardProfile ?? keyboardProfile
                            resolved.gamepadProfile = resolved.gamepadProfile ?? gamepadProfile
                            if mode != .monitor,
                               (appliedLayout?.inputType != resolved.inputType || appliedLayout?.keyboardProfile != resolved.keyboardProfile || appliedLayout?.gamepadProfile != resolved.gamepadProfile || appliedLayout?.effectiveControllerStyle != resolved.effectiveControllerStyle) {
                                try output.reset(); output.close()
                                activeMode = resolved.effectiveInputType == .gamepad ? .gamepad : .keyboardMouse
                                activeGamepad = resolved.gamepadProfile ?? GamepadProfile()
                                activeStyle = resolved.effectiveControllerStyle
                                do {
                                    if activeMode == .gamepad { output = try VirtualGamepadOutput(profile: activeGamepad, style: activeStyle) }
                                    else { output = try KeyboardMouseOutput(profile: resolved.keyboardProfile ?? .starter, targetPID: targetPID, global: globalInput) }
                                    outputFailure = nil
                                } catch {
                                    output = MonitorOutput(); outputFailure = "Input unavailable: " + error.localizedDescription
                                }
                                appliedLayout = resolved
                            }
                        }
                        continue
                    }
                    if let mappings = takeMappings(), phoneLayout?.layout.inputType == nil {
                        try output.reset()
                        output.close()
                        if mode == .gamepad { output = try VirtualGamepadOutput(profile: mappings.1, style: activeStyle) }
                        else if mode == .keyboardMouse { output = try KeyboardMouseOutput(profile: mappings.0, targetPID: targetPID, global: globalInput) }
                    }
                    let paused = isOutputPaused
                    if data[5] == 2 {
                        let pointer = try PointerFrame(data: data)
                        try sequence.accept(pointer.sequence)
                        if paused { try output.reset() } else { try output.pointer(pointer) }
                        continue
                    }
                    let frame = try StateFrame(data: data)
                    try sequence.accept(frame.sequence)
                    stateDeadline = ProcessInfo.processInfo.systemUptime + 0.25
                    if paused || frame.state.isPaused { try output.reset() }
                    else { try output.submit(frame.state) }
                    let rumble = paused || frame.state.isPaused ? RumbleFrame() : (output as? VirtualGamepadOutput)?.currentRumble() ?? RumbleFrame()
                    let now = ProcessInfo.processInfo.systemUptime
                    if rumble != lastRumble || (rumble != RumbleFrame() && now - lastRumbleSent > 0.2) {
                        try stream.write(rumble.data); lastRumble = rumble; lastRumbleSent = now
                    }
                    count += 1
                    // Enter play only after authenticated controller traffic has arrived.
                    // Send the same transition to the phone before reporting success to the Mac UI.
                    if currentSetupStage == .play && sentSetupStage != .play {
                        try stream.write(SetupStage.play.encode())
                        sentSetupStage = .play
                    }
                    let status = outputFailure ?? (paused || frame.state.isPaused ? "Layout editing · output paused" :
                        (output as? KeyboardMouseOutput)?.statusDescription ?? (mode == .monitor ? "\(transport.rawValue) connected · monitor only" : "\(transport.rawValue) connected · HID output active"))
                    var event = HostUpdate(message: status, connected: true, state: frame.state, frames: count)
                    event.layout = phoneLayout
                    event.interpretedInput = paused ? "Editing · input paused" : (output as? KeyboardMouseOutput)?.interpretedInput ?? (activeMode == .gamepad ? activeGamepad.summary(frame.state) : "See controller indicators below")
                    update(event)
                }
            } catch {
                lock.lock(); commandBytes.removeAll(); lock.unlock()
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
