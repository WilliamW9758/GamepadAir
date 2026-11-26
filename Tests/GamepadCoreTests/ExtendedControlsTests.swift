import XCTest
@testable import GamepadCore

final class ExtendedControlsTests: XCTestCase {
    func testRectangleFittingAndMovementPreserveDimensionsAndBindings() throws {
        var doc = LayoutDocument(name: "Pad", inputType: "keyboardMouse", templateStyle: "xbox", actions: [:], controls: [DocumentControl(id: "pad", role: "trackpad", placement: DocumentPlacement(x: 1, y: 1, width: 0.4, height: 0.6))], modes: [DocumentMode(id: "play", name: "Play")], initialMode: "play")
        try doc.validate()
        for (w, h) in [(667.0, 375.0), (932.0, 430.0)] {
            let item = try XCTUnwrap(LayoutGeometry.resolve(doc, modeID: "play", width: w, height: h).first)
            XCTAssertTrue(item.rectangular)
            XCTAssertEqual(item.width, w * 0.4, accuracy: 0.001)
            XCTAssertLessThanOrEqual(item.placement.x * w + item.width / 2, w - 3.99)
            XCTAssertLessThanOrEqual(item.placement.y * h + item.height / 2, h - 3.99)
        }
        try doc.placeControl("pad", at: DocumentPlacement(x: 0.3, y: 0.4), modeID: "play")
        XCTAssertEqual(doc.resolvedControl("pad", modeID: "play")?.placement?.width, 0.4)
        XCTAssertEqual(try LayoutDocument.decode(doc.validatedData()), doc)
        XCTAssertTrue(doc.compileInput().keyboard[.south].outputs.isEmpty)
    }
    func testGeometryOverlapAndSyncCarryExtendedFields() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let doc = try LayoutDocument.decode(Data(contentsOf: root.appendingPathComponent("docs/layout-format/fixtures/trackpad-motion.layout.json")))
        let layout = LocalLayout(document: doc)
        let snapshot = DocumentLayoutSnapshot(layout: layout, activeModeID: doc.initialMode)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try DocumentLayoutTransport.decodeSnapshot(data)
        XCTAssertEqual(decoded.layout.document, doc)
        XCTAssertEqual(decoded.protocolVersion, 6)
        var changed = doc
        try changed.placeControl("trackpad", at: DocumentPlacement(x: 0.2, y: 0.65), modeID: doc.initialMode)
        let items = LayoutGeometry.resolve(changed, modeID: doc.initialMode, width: 800, height: 360)
        XCTAssertTrue(LayoutGeometry.overlappingIDs(items, width: 800, height: 360).contains("trackpad"))
        let fitted = LayoutGeometry.fitted(ControlPlacement(x: 1, y: -1), canvasWidth: 800, canvasHeight: 360, controlWidth: 240, controlHeight: 144)
        XCTAssertEqual(fitted.x, 0.845, accuracy: 0.001)
        XCTAssertEqual(fitted.y, 76.0 / 360, accuracy: 0.001)
    }
    func testMotionDeadZoneSensitivityAndBounds() {
        XCTAssertEqual(MotionInput.axis(angle: 0.01, sensitivity: 1, deadZone: 0.03), 0)
        XCTAssertEqual(MotionInput.axis(angle: 10, sensitivity: 4, deadZone: 0.03), 1)
        XCTAssertEqual(MotionInput.axis(angle: -10, sensitivity: 4, deadZone: 0.03), -1)
        XCTAssertEqual(MotionInput.axis(angle: .nan, sensitivity: 1, deadZone: 0), 0)
        XCTAssertGreaterThan(MotionInput.axis(angle: 0.1, sensitivity: 2, deadZone: 0.03), MotionInput.axis(angle: 0.1, sensitivity: 1, deadZone: 0.03))
    }
    func testMotionAxesRespectSwappedDestinationsWithoutVisibleSticks() throws {
        let doc = LayoutDocument(name: "Steering", inputType: "gamepad", templateStyle: "xbox", controllerStyle: "xbox", actions: [:], controls: [DocumentControl(id: "hold", role: "rightTrigger")], modes: [DocumentMode(id: "play", name: "Play")], initialMode: "play", gamepad: DocumentGamepadSettings(swapSticks: true), motion: DocumentMotionSettings(mode: "steering"))
        try doc.validate()
        XCTAssertEqual(doc.compileInput().gamepad.disableLeftStick, true)
        XCTAssertEqual(doc.compileInput().gamepad.disableRightStick, false)
    }
    func testScrollFramesAreBoundedAndRoundTrip() throws {
        let frame = PointerFrame(sequence: 7, action: .scroll, dx: -321, dy: 240)
        XCTAssertEqual(try PointerFrame(data: frame.encode()), frame)
        XCTAssertThrowsError(try PointerFrame(data: PointerFrame(sequence: 7, action: .scroll, dy: 4097).encode()))
    }
    func testOverlapUsesVisibleCirclesRatherThanBoundingSquares() throws {
        var doc = LayoutDocument(name: "Shapes", inputType: "keyboardMouse", templateStyle: "xbox", actions: [:], controls: [
            DocumentControl(id: "left", role: "leftStick", placement: DocumentPlacement(x: 0.3, y: 0.4)),
            DocumentControl(id: "pad", role: "dpad", placement: DocumentPlacement(x: 0.42, y: 0.65))
        ], modes: [DocumentMode(id: "play", name: "Play")], initialMode: "play")
        func overlaps() -> Set<String> { LayoutGeometry.overlappingIDs(LayoutGeometry.resolve(doc, modeID: "play", width: 800, height: 320), width: 800, height: 320) }
        // 96 × 80 displacement: squares overlap, but the 62 + 50 radii do not.
        XCTAssertTrue(overlaps().isEmpty)
        doc.controls[1].placement = DocumentPlacement(x: 0.4, y: 0.55)
        XCTAssertEqual(overlaps(), ["left", "pad"])
        doc.controls[1].hidden = true
        XCTAssertTrue(overlaps().isEmpty)
    }
    func testFourWayDPadEmptyCornersDoNotOverlap() {
        var doc = LayoutDocument(name: "Shapes", inputType: "keyboardMouse", templateStyle: "xbox", actions: [:], controls: [
            DocumentControl(id: "button", role: "customButton", customSlot: 0, placement: DocumentPlacement(x: 0.55, y: 0.625, scale: 0.65)),
            DocumentControl(id: "pad", role: "dpad", placement: DocumentPlacement(x: 0.5, y: 0.5))
        ], modes: [DocumentMode(id: "play", name: "Play", dpadStyle: "fourWay")], initialMode: "play")
        func overlaps() -> Set<String> { LayoutGeometry.overlappingIDs(LayoutGeometry.resolve(doc, modeID: "play", width: 800, height: 320), width: 800, height: 320) }
        XCTAssertTrue(overlaps().isEmpty)
        doc.controls[0].placement = DocumentPlacement(x: 0.55, y: 0.5, scale: 0.65)
        XCTAssertEqual(overlaps(), ["button", "pad"])
    }
    func testPointSizedControlsStayConstantAcrossPhoneCanvases() throws {
        let doc = LayoutDocument.starter(name: "Points", style: .xbox, input: .keyboardMouse)
        let compact = LayoutGeometry.resolve(doc, modeID: doc.initialMode, width: 667, height: 375)
        let wide = LayoutGeometry.resolve(doc, modeID: doc.initialMode, width: 932, height: 430)
        for a in compact {
            let b = try XCTUnwrap(wide.first { $0.id == a.id })
            XCTAssertEqual(a.width, b.width, accuracy: 0.001)
            XCTAssertEqual(a.height, b.height, accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(a.width, 44)
            XCTAssertGreaterThan(a.width / 667, b.width / 932)
        }
        XCTAssertEqual(compact.first { $0.role == "south" }?.width, 46)
        XCTAssertEqual(compact.first { $0.role == "leftStick" }?.width, 124)
    }
    func testMinimumTargetsSurviveSmallSizeSettings() {
        var doc = LayoutDocument.starter(name: "Minimum", style: .xbox, input: .gamepad)
        doc.modes[0].sizeFactor = 0.05
        doc.modes[0].dpadStyle = "fourWay"
        for index in doc.controls.indices { doc.controls[index].placement = DocumentPlacement(x: 0, y: 1, scale: 0.65) }
        for item in LayoutGeometry.resolve(doc, modeID: doc.initialMode, width: 667, height: 375) {
            XCTAssertGreaterThanOrEqual(item.width, 44)
            XCTAssertGreaterThanOrEqual(item.height, 44)
            if item.outline == "cross" { XCTAssertGreaterThanOrEqual(item.radius * 2 * 0.92, 44) }
            XCTAssertGreaterThanOrEqual(item.placement.x * 667 - item.width / 2, 3.999)
            XCTAssertLessThanOrEqual(item.placement.y * 375 + item.height / 2, 371.001)
        }
    }
    func testRectangularButtonsUsePointsAndTrackpadsUseCanvas() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let doc = try LayoutDocument.decode(Data(contentsOf: root.appendingPathComponent("docs/layout-format/fixtures/point-sizing.layout.json")))
        for width in [667.0, 932.0] {
            let items = LayoutGeometry.resolve(doc, modeID: doc.initialMode, width: width, height: 430)
            XCTAssertEqual(items.first { $0.id == "fixed-button" }?.width, 80)
            XCTAssertEqual(items.first { $0.id == "fixed-button" }?.height, 48)
            XCTAssertEqual(try XCTUnwrap(items.first { $0.role == "trackpad" }).width, width * 0.3, accuracy: 0.001)
        }
    }
    func testSnappingUsesCenters() {
        let p = LayoutGeometry.snapped(ControlPlacement(x: 0.506, y: 0.299), others: [ControlPlacement(x: 0.2, y: 0.3)])
        XCTAssertEqual(p.x, 0.5); XCTAssertEqual(p.y, 0.3)
    }
}
