import Foundation

/// Experimental DS4 USB-compatible input framing for PlayStation-style layouts;
/// this is not a claim to implement sensors, touchpad, audio, or force feedback.
public enum CompatibilityHIDReport {
    public static let byteCount = 64
    public static let descriptor = Data([
        0x05,0x01,0x09,0x05,0xA1,0x01,0x85,0x01,
        // Four unsigned 8-bit sticks.
        0x09,0x30,0x09,0x31,0x09,0x32,0x09,0x35,
        0x15,0x00,0x26,0xFF,0x00,0x75,0x08,0x95,0x04,0x81,0x02,
        // Hat, face buttons, shoulders, trigger buttons, menu, stick clicks.
        0x09,0x39,0x15,0x00,0x25,0x07,0x35,0x00,0x46,0x3B,0x01,
        0x65,0x14,0x75,0x04,0x95,0x01,0x81,0x42,
        0x65,0x00,0x05,0x09,0x19,0x01,0x29,0x0E,
        0x15,0x00,0x25,0x01,0x75,0x01,0x95,0x0E,0x81,0x02,
        // Six-bit sequence field.
        0x06,0x00,0xFF,0x09,0x20,0x75,0x06,0x95,0x01,0x81,0x02,
        0x05,0x01,0x09,0x33,0x09,0x34,0x15,0x00,0x26,0xFF,0x00,
        0x75,0x08,0x95,0x02,0x81,0x02,
        // Remaining USB report payload; neutral sensors and no touches.
        0x06,0x00,0xFF,0x09,0x21,0x95,0x36,0x81,0x02,
        // Accept light/rumble output without implementing it in the prototype.
        0x85,0x05,0x09,0x22,0x95,0x1F,0x91,0x02,0xC0
    ])

    public static func encode(_ state: GamepadState, sequence: UInt8 = 0) -> Data {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        func axis(_ value: Int16) -> UInt8 {
            UInt8(clamping: Int(((Double(value) / 32767 + 1) * 127.5).rounded()))
        }
        func pressed(_ button: PadButton) -> Bool { state.buttons & button.mask != 0 }
        bytes[0] = 1
        bytes[1] = axis(state.leftX); bytes[2] = axis(state.leftY)
        bytes[3] = axis(state.rightX); bytes[4] = axis(state.rightY)
        bytes[5] = min(state.hat, 8)
        for (button, bit) in [(PadButton.west,4),(.south,5),(.east,6),(.north,7)] {
            if pressed(button) { bytes[5] |= 1 << bit }
        }
        for (button, bit) in [(PadButton.leftShoulder,0),(.rightShoulder,1),(.back,4),(.start,5),(.leftClick,6),(.rightClick,7)] {
            if pressed(button) { bytes[6] |= 1 << bit }
        }
        if state.leftTrigger > 0 { bytes[6] |= 4 }
        if state.rightTrigger > 0 { bytes[6] |= 8 }
        bytes[7] = ((sequence & 63) << 2) | (pressed(.guide) ? 1 : 0)
        bytes[8] = state.leftTrigger; bytes[9] = state.rightTrigger
        bytes[30] = 0x1B // USB power and full battery.
        bytes[35] = 0x80; bytes[39] = 0x80 // Both touch contacts inactive.
        return Data(bytes)
    }
}
