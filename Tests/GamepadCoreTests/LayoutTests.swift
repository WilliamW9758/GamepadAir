import XCTest
@testable import GamepadCore

final class LayoutTests: XCTestCase {
    func testLayoutsPersistIndependently() throws {
        var library = LayoutLibrary()
        let moved = ControlPlacement(x: 0.3, y: 0.7, scale: 1.4)
        library.set(moved, control: "button-0", style: .xbox)
        library.set(ControlPlacement(x: 0.8, y: 0.4), control: "button-0", style: .playStation)
        let restored = LayoutLibrary.restore(try JSONEncoder().encode(library))
        XCTAssertEqual(restored.controls(for: .xbox)["button-0"], moved)
        XCTAssertEqual(restored.controls(for: .playStation)["button-0"]?.scale, 1)
    }
    func testResetDoesNotAffectOtherControlsOrPreset() {
        var library = LayoutLibrary()
        for style in PadStyle.allCases {
            library.set(ControlPlacement(x: 0.2, y: 0.3), control: "button-0", style: style)
            library.set(ControlPlacement(x: 0.7, y: 0.6), control: "left-stick", style: style)
        }
        library.reset(style: .xbox, control: "button-0")
        XCTAssertNil(library.controls(for: .xbox)["button-0"])
        XCTAssertNotNil(library.controls(for: .xbox)["left-stick"])
        library.reset(style: .xbox)
        XCTAssertTrue(library.controls(for: .xbox).isEmpty)
        XCTAssertEqual(library.controls(for: .playStation).count, 2)
    }
    func testResizeAndDragStayOnSurface() {
        let p = ControlPlacement(x: -1, y: 3, scale: 1.8).fitting(width: 800, height: 280, baseRadius: 62)
        XCTAssertGreaterThanOrEqual(p.x * 800, 62 * 1.8)
        XCTAssertLessThanOrEqual(p.y * 280 + 62 * 1.8, 280)
        let rotated = p.fitting(width: 280, height: 800, baseRadius: 62)
        XCTAssertGreaterThanOrEqual(rotated.x * 280, 62 * 1.8)
    }
    func testCorruptOrFutureStorageFallsBack() {
        XCTAssertTrue(LayoutLibrary.restore(Data("invalid".utf8)).presets.isEmpty)
        XCTAssertTrue(LayoutLibrary.restore(Data(#"{"version":2,"presets":{}}"#.utf8)).presets.isEmpty)
        XCTAssertEqual(ControlPlacement(x: .nan, y: .infinity, scale: -.infinity).sanitized, ControlPlacement(x: 0.5, y: 0.5))
        XCTAssertEqual(ControlPlacement(x: 0, y: 0, scale: 50).sanitized.scale, 1.8)
        XCTAssertEqual(ControlPlacement(x: 0, y: 0, scale: 0).sanitized.scale, 0.65)
    }
}
