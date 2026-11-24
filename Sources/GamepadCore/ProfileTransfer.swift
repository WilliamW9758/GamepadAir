import Foundation

/// A portable profile has no device address, pairing secret or permission state.
public struct PortableProfile: Codable, Equatable {
    public var format = "pocketpad-profile"
    public var version = 1
    public var layout: SavedLayout
    public var keyboard: KeyboardProfile?
    public init(layout: SavedLayout, keyboard: KeyboardProfile? = nil) {
        self.layout = layout; self.keyboard = keyboard
    }
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 4_000_000 else { throw ProtocolError.invalidState }
        var value = try JSONDecoder().decode(Self.self, from: data)
        guard value.format == "pocketpad-profile", value.version == 1,
              value.keyboard == nil || value.keyboard?.version == 1 else { throw ProtocolError.invalidState }
        var catalog = LayoutCatalog(legacy: LayoutLibrary(), style: .xbox, showDPad: true, holdAimEnabled: true, holdAimDelay: 0.3, trackpadHoldDelay: 0.5)
        catalog.layouts = [value.layout]; catalog.selectedID = value.layout.id
        _ = try LayoutCatalog.decode(JSONEncoder().encode(catalog))
        guard value.layout.modes.allSatisfy({ mode in
            mode.sizeFactor.isFinite && (0.05...3).contains(mode.sizeFactor) &&
            mode.controls.presets.values.allSatisfy { placements in
                placements.count <= 128 && placements.values.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.scale.isFinite }
            } && (mode.controls.customSlots ?? [:]).values.allSatisfy { slots in
                slots.count <= 16 && Set(slots).count == slots.count && slots.allSatisfy { (0..<16).contains($0) }
            }
        }) else { throw ProtocolError.invalidState }
        guard value.layout.gamepadProfile == nil || value.layout.gamepadProfile?.version == 1 else { throw ProtocolError.invalidState }
        value.keyboard = value.keyboard ?? value.layout.keyboardProfile
        guard value.keyboard == nil || value.keyboard?.version == 1 else { throw ProtocolError.invalidState }
        value.keyboard = value.keyboard?.sanitized
        return value
    }
}

public struct LayoutHistory {
    private var past: [LayoutCatalog] = []
    private var future: [LayoutCatalog] = []
    public init() {}
    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }
    public mutating func record(_ value: LayoutCatalog) {
        if past.last != value { past.append(value) }
        if past.count > 50 { past.removeFirst() }
        future.removeAll()
    }
    public mutating func undo(_ current: LayoutCatalog) -> LayoutCatalog? {
        guard let previous = past.popLast() else { return nil }
        future.append(current); return previous
    }
    public mutating func redo(_ current: LayoutCatalog) -> LayoutCatalog? {
        guard let next = future.popLast() else { return nil }
        past.append(current); return next
    }
}

extension SavedLayout {
    /// Enabling cursor switching starts with the current arrangement, avoiding a
    /// surprise jump to the untouched second canvas in newly created layouts.
    public mutating func setCursorSwitching(_ enabled: Bool) {
        if enabled && cursorSwitching == false {
            let alternateID = modes[1].id
            modes[1] = modes[0]
            modes[1].id = alternateID; modes[1].name = "Cursor"; modes[1].cursor = true
            linkedControls = Set(MappedControl.allCases.map(\.canvasID)).union(["radial"])
        }
        cursorSwitching = enabled
    }
    /// Linking is explicit; old layouts remain independent until the user opts in.
    public mutating func place(_ placement: ControlPlacement, control: String, mode index: Int) {
        modes[index].controls.set(placement, control: control, style: style)
        guard linkedControls?.contains(control) == true else { return }
        let other = 1 - index
        var copy = placement
        copy.scale *= modes[index].sizeFactor / max(0.01, modes[other].sizeFactor)
        modes[other].controls.set(copy, control: control, style: style)
    }
}
