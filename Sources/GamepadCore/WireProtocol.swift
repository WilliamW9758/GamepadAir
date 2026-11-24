import Foundation

/// Fixed-size, little-endian full-state frames over a reliable byte stream.
public struct StateFrame: Equatable, Sendable {
    public static let byteCount = 28
    public static let port: UInt16 = 27183
    public static let hello = Data("IPGP/1\n".utf8)
    public let sequence: UInt32
    public let state: GamepadState
    public init(sequence: UInt32, state: GamepadState) { self.sequence = sequence; self.state = state }

    public func encode() -> Data {
        var b: [UInt8] = [0x49, 0x50, 0x47, 0x50, 1, 1, state.isPaused ? 1 : 0, state.pointerMode.rawValue]
        b += (0..<4).map { UInt8(truncatingIfNeeded: sequence >> ($0 * 8)) }
        func word(_ value: UInt16) { b += [UInt8(truncatingIfNeeded: value), UInt8(value >> 8)] }
        word(state.buttons)
        b += [state.hat, state.radialPreview]
        for value in [state.leftX, state.leftY, state.rightX, state.rightY] { word(UInt16(bitPattern: value)) }
        b += [state.leftTrigger, state.rightTrigger]
        word(state.customButtons)
        return Data(b)
    }

    public init(data: Data) throws {
        let b = Array(data)
        guard b.count == Self.byteCount else { throw ProtocolError.invalidLength }
        guard Array(b[0..<6]) == [0x49, 0x50, 0x47, 0x50, 1, 1], b[6] <= 1, PointerMode(rawValue: b[7]) != nil,
              b[15] <= 9 else { throw ProtocolError.invalidHeader }
        func word(_ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i + 1]) << 8 }
        let buttons = word(12)
        guard buttons & ~UInt16(0x07ff) == 0, b[14] <= 8,
              [16, 18, 20, 22].allSatisfy({ word($0) != 0x8000 }),
              [b[24], b[25]].allSatisfy({ $0 == 0 || $0 == 255 }) else { throw ProtocolError.invalidState }
        sequence = (0..<4).reduce(UInt32(0)) { $0 | UInt32(b[8 + $1]) << ($1 * 8) }
        var s = GamepadState()
        s.buttons = buttons; s.hat = b[14]; s.radialPreview = b[15]
        s.leftX = Int16(bitPattern: word(16)); s.leftY = Int16(bitPattern: word(18))
        s.rightX = Int16(bitPattern: word(20)); s.rightY = Int16(bitPattern: word(22))
        s.leftTrigger = b[24]; s.rightTrigger = b[25]; s.customButtons = word(26)
        // Paused frames may carry practice telemetry; receivers must suppress output.
        s.isPaused = b[6] == 1
        s.pointerMode = PointerMode(rawValue: b[7])!
        state = s
    }
}

public enum ProtocolError: Error, Equatable { case invalidLength, invalidHeader, invalidState, outOfOrder }

public struct SequenceGuard {
    private var previous: UInt32?
    public init() {}
    public mutating func accept(_ sequence: UInt32) throws {
        if let previous, sequence != previous &+ 1 { throw ProtocolError.outOfOrder }
        previous = sequence
    }
}

public enum PointerAction: UInt8, Sendable { case move = 0, leftClick = 1, rightClick = 2 }

/// One-shot pointer commands share the state stream's sequence but never repeat
/// on heartbeat: displacement must be applied exactly once.
public struct PointerFrame: Equatable, Sendable {
    public let sequence: UInt32
    public let action: PointerAction
    public let dx: Int16
    public let dy: Int16
    public init(sequence: UInt32, action: PointerAction, dx: Int16 = 0, dy: Int16 = 0) {
        self.sequence = sequence; self.action = action; self.dx = dx; self.dy = dy
    }
    public func encode() -> Data {
        var bytes = [UInt8](repeating: 0, count: StateFrame.byteCount)
        bytes.replaceSubrange(0..<7, with: [0x49, 0x50, 0x47, 0x50, 1, 2, action.rawValue])
        for i in 0..<4 { bytes[8 + i] = UInt8(truncatingIfNeeded: sequence >> (8 * i)) }
        for (offset, value) in [(16, dx), (18, dy)] {
            let word = UInt16(bitPattern: value)
            bytes[offset] = UInt8(truncatingIfNeeded: word); bytes[offset + 1] = UInt8(word >> 8)
        }
        return Data(bytes)
    }
    public init(data: Data) throws {
        let b = Array(data)
        guard b.count == StateFrame.byteCount else { throw ProtocolError.invalidLength }
        guard Array(b[0..<6]) == [0x49, 0x50, 0x47, 0x50, 1, 2], let action = PointerAction(rawValue: b[6]),
              ([7] + Array(12..<16) + Array(20..<28)).allSatisfy({ b[$0] == 0 }) else { throw ProtocolError.invalidHeader }
        sequence = (0..<4).reduce(UInt32(0)) { $0 | UInt32(b[8 + $1]) << ($1 * 8) }
        self.action = action
        dx = Int16(bitPattern: UInt16(b[16]) | UInt16(b[17]) << 8)
        dy = Int16(bitPattern: UInt16(b[18]) | UInt16(b[19]) << 8)
        guard abs(Int(dx)) <= 4096, abs(Int(dy)) <= 4096,
              action == .move || (dx == 0 && dy == 0) else { throw ProtocolError.invalidState }
    }
}

/// Mac-led onboarding commands on the authenticated return channel.
public enum SetupStage: UInt8, Sendable {
    case pairing = 0, practice = 1, controls = 2, play = 3
    public static let byteCount = 4
    public func encode() -> Data { Data([0x49, 0x50, 1, rawValue]) }
    public init(data: Data) throws {
        let bytes = Array(data)
        guard bytes.count == Self.byteCount else { throw ProtocolError.invalidLength }
        guard Array(bytes.prefix(3)) == [0x49, 0x50, 1], let stage = Self(rawValue: bytes[3]) else {
            throw ProtocolError.invalidHeader
        }
        self = stage
    }
}

/// Read-only phone layout metadata, interleaved with controller heartbeats.
public struct ControllerSnapshot: Codable, Equatable {
    public var layout: SavedLayout
    public var modeIndex: Int
    public var screen: PhoneScreen?
    public var layouts: [LayoutSummary]?
    public var commandID: String?
    public var commandError: String?
    public var supportsLayoutDeletion: Bool?
    public init(layout: SavedLayout, modeIndex: Int) {
        self.layout = layout; self.modeIndex = modeIndex
    }
}
public enum LayoutTelemetry {
    public static func chunks(_ snapshot: ControllerSnapshot) throws -> [Data] {
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= 262144 else { throw ProtocolError.invalidLength }
        return stride(from: 0, to: data.count, by: 16).map { offset in
            let payload = data.subdata(in: offset..<min(offset + 16, data.count))
            var frame = Data(repeating: 0, count: 28)
            frame.replaceSubrange(0..<8, with: [0x49, 0x50, 0x47, 0x50, 1, 3,
                UInt8((offset == 0 ? 1 : 0) | (offset + 16 >= data.count ? 2 : 0)), UInt8(payload.count)])
            frame.replaceSubrange(12..<(12 + payload.count), with: payload)
            return frame
        }
    }
}
public struct LayoutTelemetryReceiver {
    private var buffer = Data()
    private var receiving = false
    public init() {}
    public mutating func accept(_ data: Data) throws -> ControllerSnapshot? {
        let b = Array(data)
        guard b.count == 28, Array(b[0..<6]) == [0x49,0x50,0x47,0x50,1,3],
              b[6] <= 3, b[7] > 0, b[7] <= 16 else { throw ProtocolError.invalidHeader }
        if b[6] & 1 != 0 { buffer.removeAll(keepingCapacity: true); receiving = true }
        guard receiving, buffer.count + Int(b[7]) <= 262144 else { throw ProtocolError.invalidLength }
        buffer.append(contentsOf: b[12..<(12 + Int(b[7]))])
        guard b[6] & 2 != 0 else { return nil }
        receiving = false
        let snapshot = try JSONDecoder().decode(ControllerSnapshot.self, from: buffer)
        // Reuse profile validation before exposing untrusted geometry to the UI.
        _ = try PortableProfile.decode(JSONEncoder().encode(PortableProfile(layout: snapshot.layout)))
        guard snapshot.layout.modes.indices.contains(snapshot.modeIndex) else { throw ProtocolError.invalidState }
        if let screen = snapshot.screen {
            guard screen.width.isFinite, screen.height.isFinite,
                  (200...3000).contains(screen.width), (200...3000).contains(screen.height) else { throw ProtocolError.invalidState }
        }
        return snapshot
    }
}

public struct PhoneScreen: Codable, Equatable {
    public var model: String
    public var width: Double
    public var height: Double
    public init(model: String, width: Double, height: Double) {
        self.model = model; self.width = width; self.height = height
    }
}
public struct LayoutSummary: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var isPreset: Bool
    public init(_ layout: SavedLayout) { id = layout.id; name = layout.name; isPreset = layout.isPreset }
}
public struct LayoutCommand: Codable, Equatable {
    public enum Action: String, Codable { case select, create, save, bindLegacy, delete, clear }
    public var id = UUID().uuidString
    public var action: Action
    public var layoutID: String?
    public var layout: SavedLayout?
    public var base: SavedLayout?
    public init(action: Action, layoutID: String? = nil, layout: SavedLayout? = nil, base: SavedLayout? = nil) {
        self.action = action; self.layoutID = layoutID; self.layout = layout; self.base = base
    }
    public func encode() throws -> Data {
        let payload = try JSONEncoder().encode(self)
        guard payload.count <= 262144 else { throw ProtocolError.invalidLength }
        var result = Data([0x49, 0x50, 3, 0])
        for byte in payload { result.append(contentsOf: [0x49, 0x50, 2, byte]) }
        result.append(contentsOf: [0x49, 0x50, 3, 1])
        return result
    }
}
public struct LayoutCommandReceiver {
    private var buffer = Data()
    private var receiving = false
    public init() {}
    public mutating func accept(_ frame: Data) throws -> LayoutCommand? {
        let b = Array(frame)
        guard b.count == 4, b[0] == 0x49, b[1] == 0x50 else { throw ProtocolError.invalidHeader }
        if b[2] == 3 && b[3] == 0 { buffer.removeAll(keepingCapacity: true); receiving = true; return nil }
        guard receiving else { throw ProtocolError.invalidState }
        if b[2] == 2 {
            guard buffer.count < 262144 else { throw ProtocolError.invalidLength }
            buffer.append(b[3]); return nil
        }
        guard b[2] == 3 && b[3] == 1 else { throw ProtocolError.invalidHeader }
        receiving = false
        return try JSONDecoder().decode(LayoutCommand.self, from: buffer)
    }
}
