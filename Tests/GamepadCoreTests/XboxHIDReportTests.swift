import XCTest
@testable import GamepadCore

final class XboxHIDReportTests: XCTestCase {
    func testNeutralAndExtremes() {
        let bytes = Array(XboxHIDReport.encode(.neutral))
        XCTAssertEqual(bytes, [1,255,127,255,127,255,127,255,127,0,0,0,0,0,0,0,0,0])
        var state = GamepadState()
        state.leftX = -32767; state.leftY = -32767
        state.rightX = 32767; state.rightY = 32767
        state.leftTrigger = 255; state.rightTrigger = 128
        XCTAssertEqual(Array(XboxHIDReport.encode(state).prefix(13)), [1,0,0,0,0,254,255,254,255,255,3,2,2])
    }
    func testButtonsIndividuallyMatchUnityWirelessLayout() {
        for (button, bit) in [(PadButton.south,0),(.east,1),(.west,3),(.north,4),
                             (.leftShoulder,6),(.rightShoulder,7),(.back,10),(.start,11),
                             (.leftClick,13),(.rightClick,14),(.guide,12)] {
            var state = GamepadState(); state.set(button, pressed: true)
            var expected = Array(XboxHIDReport.encode(.neutral))
            expected[14 + bit / 8] |= 1 << (bit % 8)
            XCTAssertEqual(Array(XboxHIDReport.encode(state)), expected)
        }
    }
    func testAllHatDirectionsAndRelease() {
        for hat in UInt8(0)...8 {
            var state = GamepadState(); state.hat = hat
            XCTAssertEqual(XboxHIDReport.encode(state)[13], hat == 8 ? 0 : hat + 1)
        }
    }
    func testDescriptorLength() {
        let bytes = Array(XboxHIDReport.descriptor)
        var i = 0, size = 0, count = 0, bits = 0
        while i < bytes.count {
            let prefix = bytes[i]; i += 1
            let length = [0,1,2,4][Int(prefix & 3)]
            let value = (0..<length).reduce(0) { $0 | Int(bytes[i + $1]) << ($1 * 8) }
            switch prefix & 0xfc {
            case 0x74: size = value
            case 0x94: count = value
            case 0x80: bits += size * count
            default: break
            }
            i += length
        }
        XCTAssertEqual(bits / 8 + 1, XboxHIDReport.byteCount)
    }
}
