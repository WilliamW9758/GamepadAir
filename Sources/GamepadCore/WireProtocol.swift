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
        b += [state.hat, 0]
        for value in [state.leftX, state.leftY, state.rightX, state.rightY] { word(UInt16(bitPattern: value)) }
        b += [state.leftTrigger, state.rightTrigger]
        word(state.customButtons)
        return Data(b)
    }

    public init(data: Data) throws {
        let b = Array(data)
        guard b.count == Self.byteCount else { throw ProtocolError.invalidLength }
        guard Array(b[0..<6]) == [0x49, 0x50, 0x47, 0x50, 1, 1], b[6] <= 1, PointerMode(rawValue: b[7]) != nil,
              b[15] == 0 else { throw ProtocolError.invalidHeader }
        func word(_ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i + 1]) << 8 }
        let buttons = word(12)
        guard buttons & ~UInt16(0x03ff) == 0, b[14] <= 8,
              [16, 18, 20, 22].allSatisfy({ word($0) != 0x8000 }),
              [b[24], b[25]].allSatisfy({ $0 == 0 || $0 == 255 }) else { throw ProtocolError.invalidState }
        sequence = (0..<4).reduce(UInt32(0)) { $0 | UInt32(b[8 + $1]) << ($1 * 8) }
        var s = GamepadState()
        s.buttons = buttons; s.hat = b[14]
        s.leftX = Int16(bitPattern: word(16)); s.leftY = Int16(bitPattern: word(18))
        s.rightX = Int16(bitPattern: word(20)); s.rightY = Int16(bitPattern: word(22))
        s.leftTrigger = b[24]; s.rightTrigger = b[25]; s.customButtons = word(26)
        guard b[6] == 0 || s == .neutral else { throw ProtocolError.invalidState }
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
