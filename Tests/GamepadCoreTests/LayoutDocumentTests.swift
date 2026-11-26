import XCTest
@testable import GamepadCore

final class LayoutDocumentTests: XCTestCase {
    private var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    private func fixture(_ name: String = "keyboard-simple") throws -> LayoutDocument {
        try LayoutDocument.decode(Data(contentsOf: root.appendingPathComponent("docs/layout-format/fixtures/\(name).layout.json")))
    }
    func testBottomCornerAnchorsPreservePointDistancesAndEditingRoundTrip() throws {
        var doc = LayoutDocument.starter(name: "Anchors", style: .xbox, input: .gamepad)
        let left = try XCTUnwrap(doc.controls.first { $0.role == "leftStick" })
        let right = try XCTUnwrap(doc.controls.first { $0.role == "south" })
        for (id, x) in [(left.id, 0.2), (right.id, 0.8)] {
            try doc.placeControl(id, at: DocumentPlacement(x: x, y: 0.7, referenceWidth: 912, referenceHeight: 420), modeID: doc.initialMode)
        }
        let data = try doc.validatedData()
        doc = try LayoutDocument.decode(data)
        for (w, h) in [(912.0, 420.0), (1200, 800), (800, 400)] {
            let items = LayoutGeometry.resolve(doc, modeID: doc.initialMode, width: w, height: h)
            let l = try XCTUnwrap(items.first { $0.id == left.id })
            let r = try XCTUnwrap(items.first { $0.id == right.id })
            XCTAssertEqual(l.placement.x * w, 182.4, accuracy: 0.001)
            XCTAssertEqual((1 - r.placement.x) * w, 182.4, accuracy: 0.001)
            XCTAssertEqual((1 - l.placement.y) * h, 126, accuracy: 0.001)
            XCTAssertEqual((1 - r.placement.y) * h, 126, accuracy: 0.001)
        }
        // Author on a large canvas; keep its side and corner distances after reload.
        try doc.placeControl(right.id, at: DocumentPlacement(x: 0.75, y: 0.8, referenceWidth: 1200, referenceHeight: 800), modeID: doc.initialMode)
        let item = try XCTUnwrap(LayoutGeometry.resolve(doc, modeID: doc.initialMode, width: 912, height: 420).first { $0.id == right.id })
        XCTAssertEqual((1 - item.placement.x) * 912, 300, accuracy: 0.001)
        XCTAssertEqual((1 - item.placement.y) * 420, 160, accuracy: 0.001)
        XCTAssertThrowsError(try doc.placeControl(right.id, at: DocumentPlacement(x: 0.7, y: 0.8, referenceWidth: 1200), modeID: doc.initialMode))
    }

    func testMotionActivationReferencesAndRemoval() throws {
        var document = try fixture("gamepad-remapped")
        let target = try XCTUnwrap(document.controls.first { $0.role == "south" })
        document.motion = DocumentMotionSettings(mode: "aim", activationControl: target.id)
        XCTAssertEqual(try LayoutDocument.decode(document.validatedData()).motionActivationControl?.id, target.id)
        document.motion?.activationControl = "missing"
        XCTAssertThrowsError(try document.validate())
        document.motion?.activationControl = document.controls.first { $0.role == "leftStick" }?.id
        XCTAssertThrowsError(try document.validate())
        document.motion?.activationControl = target.id
        try document.removeControl(target.id)
        XCTAssertEqual(document.motion?.mode, "off")
        XCTAssertNil(document.motion?.activationControl)
    }
    func testPresentationEditsDoNotReplaceOutput() throws {
        let original = LocalLayout(document: try fixture("gamepad-remapped"))
        var edited = original
        edited.document.name = "Renamed"
        edited.document.controls[0].label = "Caption"
        edited.editRevision += 1
        XCTAssertTrue(edited.hasSameOutputConfiguration(as: original))
        edited.document.controllerStyle = original.document.controllerStyle == "xbox" ? "playstation" : "xbox"
        XCTAssertFalse(edited.hasSameOutputConfiguration(as: original))
    }
    func testExplicitButtonSizesShareRangeAndSurviveDragging() throws {
        var doc = LayoutDocument.starter(name: "Sizing", style: .xbox, input: .gamepad)
        let roles = ["south", "east", "west", "north", "leftTrigger", "rightTrigger", "back", "start", "guide"]
        for diameter in [44.0, 73.0, 240.0] {
            for control in doc.controls where roles.contains(control.role) {
                try doc.placeControl(control.id, at: DocumentPlacement(x: 0.5, y: 0.5, diameter: diameter), modeID: doc.initialMode)
            }
            doc = try LayoutDocument.decode(doc.validatedData())
            let resolved = LayoutGeometry.resolve(doc, modeID: doc.initialMode, width: 912, height: 420)
            for item in resolved where roles.contains(item.role) { XCTAssertEqual(item.width, diameter) }
        }
        let id = try XCTUnwrap(doc.controls.first { $0.role == "south" }?.id)
        try doc.placeControl(id, at: DocumentPlacement(x: 0.3, y: 0.4, scale: 1), modeID: doc.initialMode)
        XCTAssertEqual(doc.resolvedControl(id, modeID: doc.initialMode)?.placement?.diameter, 240)
    }
    func testSharedFixturesAndSchemaStayAligned() throws {
        let schema = try Data(contentsOf: root.appendingPathComponent("docs/layout-format/layout.schema.json"))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: schema) as? NSDictionary,
                       try JSONSerialization.jsonObject(with: Data(LayoutDocumentSchema.json.utf8)) as? NSDictionary)
        for name in ["keyboard-simple", "two-mode", "gamepad-remapped", "radial-custom", "trackpad-motion", "point-sizing"] {
            let value = try fixture(name)
            XCTAssertEqual(try LayoutDocument.decode(value.validatedData()), value)
        }
    }
    func testUnknownFieldsAndLegacyAreRejected() throws {
        var object = try JSONSerialization.jsonObject(with: fixture().validatedData()) as! [String: Any]
        object["surprise"] = true
        XCTAssertThrowsError(try LayoutDocument.decode(JSONSerialization.data(withJSONObject: object)))
        object.removeValue(forKey: "surprise"); object["schemaVersion"] = 1
        XCTAssertThrowsError(try LayoutDocument.decode(JSONSerialization.data(withJSONObject: object)))
        object["schemaVersion"] = 2; object["keyboard"] = ["rightStickMouse": 1]
        XCTAssertThrowsError(try LayoutDocument.decode(JSONSerialization.data(withJSONObject: object)))
    }
    func testNullOverridesAreDifferentFromOmission() throws {
        var value = try fixture("two-mode")
        value.modes[1].overrides?["jump"]?.label = .null
        let decoded = try LayoutDocument.decode(value.validatedData())
        XCTAssertEqual(decoded.modes[1].overrides?["jump"]?.label, .null)
        XCTAssertNil(decoded.resolvedControl("jump", modeID: "building")?.label)
        value.modes[1].overrides?["jump"]?.label = nil
        XCTAssertEqual(value.resolvedControl("jump", modeID: "building")?.label, "Jump")
    }
    func testSharedActionRebindClonesOnlyEditedReference() throws {
        var value = try fixture()
        value.keyboard?.autoRunAction = "jump"
        let original = value.actions["jump"]
        try value.rebind(.control(id: "jump", direction: "press"), outputs: ["key.e"])
        let newID = try XCTUnwrap(value.actionID(for: .control(id: "jump", direction: "press")))
        XCTAssertNotEqual(newID, "jump")
        XCTAssertEqual(value.actions["jump"], original)
        XCTAssertEqual(value.actions[newID]?.label, original?.label)
        XCTAssertEqual(value.keyboard?.autoRunAction, "jump")
        try value.rebind(.control(id: "jump", direction: "press"), outputs: ["key.f"])
        XCTAssertEqual(value.actionID(for: .control(id: "jump", direction: "press")), newID)
    }
    func testEditingCaptionAndPlacementPreservesActions() throws {
        var value = try fixture("two-mode")
        let actions = value.actions
        try value.renameControl("jump", caption: "Hop")
        try value.placeControl("movement", at: DocumentPlacement(x: 0.3, y: 0.4), modeID: "combat")
        XCTAssertEqual(value.actions, actions)
        XCTAssertEqual(value.resolvedControl("movement", modeID: "building")?.placement?.x, 0.3)
        XCTAssertEqual(value.nextMode(after: "combat"), "building")
        XCTAssertEqual(value.nextMode(after: "building"), "combat")
    }
    func testLocalIdentityRevisionAndFailedTransaction() throws {
        var local = LocalLayout(document: try fixture())
        let copy = try local.duplicate(name: "Copy")
        XCTAssertNotEqual(copy.id, local.id)
        XCTAssertEqual(copy.document.controls.map(\.id), local.document.controls.map(\.id))
        XCTAssertEqual(copy.document.actions, local.document.actions)
        try local.edit(baseRevision: 0) { $0.name = "Edited" }
        XCTAssertEqual(local.editRevision, 1)
        let snapshot = local
        XCTAssertThrowsError(try local.edit(baseRevision: 0) { $0.name = "Stale" })
        XCTAssertThrowsError(try local.edit(baseRevision: 1) { $0.controls = [] })
        XCTAssertEqual(local, snapshot)
    }
    func testUnsupportedModesAndReferencesRejected() throws {
        var value = try fixture()
        value.controls[0].bindings?["up"] = "missing"
        XCTAssertThrowsError(try value.validate())
        value = try fixture("two-mode")
        value.modes.append(DocumentMode(id: "travel", name: "Travel"))
        XCTAssertThrowsError(try value.validate())
    }
    func testCompiledBindingsNeverInventFallbacks() throws {
        let value = try fixture()
        let compiled = value.compileInput()
        XCTAssertEqual(compiled.keyboard[.leftUp].outputs, [.w])
        XCTAssertEqual(compiled.keyboard[.south].outputs, [.space])
        XCTAssertEqual(compiled.keyboard[.custom1].outputs, [])
        XCTAssertEqual(compiled.keyboard[.autoRun].outputs, [])
        XCTAssertFalse(compiled.keyboard.autoRunEnabled ?? true)
        XCTAssertFalse(compiled.keyboard.rightStickMouse)
        let game = try fixture("gamepad-remapped").compileInput().gamepad
        XCTAssertEqual(game[.south], .west)
        XCTAssertNil(game[.east])
        XCTAssertTrue(game.swapSticks)
        XCTAssertTrue(game.invertRightY)
    }
    func testGeometryFitsDeviceAndPreservesRequestedCoordinates() throws {
        let value = try fixture("two-mode")
        for (width, height) in [(912.0,420.0), (800,360), (600,800)] {
            let resolved = LayoutGeometry.resolve(value, modeID: "building", width: width, height: height)
            XCTAssertEqual(resolved.count, value.controls.count)
            XCTAssertEqual(resolved.first { $0.id == "jump" }?.label, "Hop")
            for item in resolved {
                XCTAssertGreaterThanOrEqual(item.placement.x * width, min(width / 2, item.radius + 4) - 0.001)
                XCTAssertLessThanOrEqual(item.placement.y * height, height - min(height / 2, item.radius + 4) + 0.001)
            }
        }
        XCTAssertEqual(value.controls.first { $0.id == "movement" }?.placement?.x, 0.2)
    }
    func testRadialAliasRebindKeepsSharedSlotAndAction() throws {
        var value = try fixture("radial-custom")
        let slots = value.radialSlots()
        XCTAssertEqual(slots, [0,-1,-1,-1,1,-1,-1,-1])
        let button = try XCTUnwrap(value.controls.first { $0.customSlot == 0 })
        let originalID = button.bindings?["press"]
        try value.rebind(.control(id: button.id, direction: "press"), outputs: ["key.three"], behavior: "tap")
        XCTAssertEqual(value.actionID(for: .control(id: button.id, direction: "press")), originalID)
        XCTAssertEqual(value.radialSlots(), slots)
        XCTAssertEqual(value.compileInput().keyboard[.custom1].outputs, [.three])
    }
    func testPresetsAreValidDocuments() throws {
        for style in PadStyle.allCases {
            for input in LayoutInputType.allCases {
                let value = LayoutDocument.starter(name: "Starter", style: style, input: input)
                XCTAssertNoThrow(try value.validate())
                XCTAssertEqual(value.modes.count, 1)
            }
        }
    }

    func testSharedRejectedCorpus() throws {
        let data = try Data(contentsOf: root.appendingPathComponent("docs/layout-format/fixtures/rejected.json"))
        let cases = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        for item in cases {
            XCTAssertThrowsError(try LayoutDocument.decode(JSONSerialization.data(withJSONObject: item["document"]!)), item["name"] as! String)
        }
    }
    func testSyncIdempotencyAndConflictRejection() throws {
        var catalog = LocalLayoutCatalog.fresh()
        var processor = DocumentLayoutCommandProcessor()
        let command = DocumentLayoutCommand(action: .create, document: try fixture())
        let first = processor.apply(command, to: &catalog)
        XCTAssertNil(first.error)
        XCTAssertEqual(processor.apply(command, to: &catalog), first)
        XCTAssertEqual(catalog.layouts.count, 3)
        let id = try XCTUnwrap(first.layoutID)
        var changed = try fixture(); changed.name = "Changed"
        let save = DocumentLayoutCommand(action: .save, layoutID: id, baseEditRevision: 0, document: changed)
        XCTAssertNil(processor.apply(save, to: &catalog).error)
        let before = catalog
        let stale = DocumentLayoutCommand(action: .save, layoutID: id, baseEditRevision: 0, document: try fixture())
        XCTAssertNotNil(processor.apply(stale, to: &catalog).error)
        XCTAssertEqual(catalog, before)
    }
    func testCorruptCatalogDoesNotReplaceFile() throws {
        var catalog = LocalLayoutCatalog.fresh()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("layouts.json")
        try catalog.save(to: url)
        let before = try Data(contentsOf: url)
        catalog.layouts[0].document.controls = []
        XCTAssertThrowsError(try catalog.save(to: url))
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertEqual(try LocalLayoutCatalog.decode(before).layouts.count, 2)
    }

}
