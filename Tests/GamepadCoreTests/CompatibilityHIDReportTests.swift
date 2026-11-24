import XCTest
@testable import GamepadCore

final class CompatibilityHIDReportTests: XCTestCase {
    func testGuideDoesNotChangeSequenceOrMenu() {
        var state = GamepadState(); state.set(.guide, pressed: true)
        for sequence in UInt8(0)...63 {
            let report = CompatibilityHIDReport.encode(state, sequence: sequence)
            XCTAssertEqual(report[7], sequence << 2 | 1)
            XCTAssertEqual(report[6], 0)
        }
        state.set(.guide, pressed: false)
        XCTAssertEqual(CompatibilityHIDReport.encode(state)[7], 0)
    }

    func testNeutralReportAndAxisExtremes() {
        let neutral = Array(CompatibilityHIDReport.encode(.neutral))
        XCTAssertEqual(neutral.count, 64)
        XCTAssertEqual(Array(neutral.prefix(10)), [1,128,128,128,128,8,0,0,0,0])
        var state = GamepadState()
        state.leftX = -32767; state.leftY = -32767
        state.rightX = 32767; state.rightY = 32767
        let report = Array(CompatibilityHIDReport.encode(state))
        // Screen up is negative in PocketPad and must reach the decoder as 0.
        XCTAssertEqual(Array(report[1...4]), [0,0,255,255])
    }

    func testEveryButtonUsesItsDS4Bit() {
        let locations: [(PadButton, Int, UInt8)] = [
            (.south,5,0x20),(.east,5,0x40),(.west,5,0x10),(.north,5,0x80),
            (.leftShoulder,6,1),(.rightShoulder,6,2),(.back,6,0x10),
            (.start,6,0x20),(.leftClick,6,0x40),(.rightClick,6,0x80)
        ]
        for (button, offset, bit) in locations {
            var state = GamepadState(); state.set(button, pressed: true)
            var expected = Array(CompatibilityHIDReport.encode(.neutral)); expected[offset] |= bit
            XCTAssertEqual(Array(CompatibilityHIDReport.encode(state)), expected, "\(button)")
        }
    }

    func testHatTriggersAndCounter() {
        for hat in UInt8(0)...8 {
            var state = GamepadState(); state.hat = hat
            state.leftTrigger = 128; state.rightTrigger = 255
            let report = Array(CompatibilityHIDReport.encode(state, sequence: 255))
            XCTAssertEqual(report[5], hat)
            XCTAssertEqual(report[6], 12)
            XCTAssertEqual(report[7], 252)
            XCTAssertEqual(Array(report[8...9]), [128,255])
        }
    }

    func testDescriptorReportLengths() {
        let bytes = Array(CompatibilityHIDReport.descriptor)
        var i = 0, size = 0, count = 0, id = 0
        var input: [Int:Int] = [:], output: [Int:Int] = [:]
        while i < bytes.count {
            let prefix = bytes[i]; i += 1
            let length = [0,1,2,4][Int(prefix & 3)]
            let value = (0..<length).reduce(0) { $0 | Int(bytes[i + $1]) << ($1 * 8) }
            switch prefix & 0xfc {
            case 0x74: size = value
            case 0x94: count = value
            case 0x84: id = value
            case 0x80: input[id, default: 0] += size * count
            case 0x90: output[id, default: 0] += size * count
            default: break
            }
            i += length
        }
        XCTAssertEqual(input, [1: 63 * 8])
        XCTAssertEqual(output, [5: 31 * 8])
    }
}
