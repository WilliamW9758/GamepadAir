import Foundation

// JSON field types for docs/layout-format/layout.schema.json. Defaults are resolved, never inserted on decode.

public struct DocumentPlacement: Codable, Equatable {
    public var x: Double
    public var y: Double
    public var scale: Double?
    public var width: Double?
    public var height: Double?
    public init(x: Double, y: Double, scale: Double? = nil, width: Double? = nil, height: Double? = nil) {
        self.x = x
        self.y = y
        self.scale = scale
        self.width = width
        self.height = height
    }
}

public struct DocumentFeedback: Codable, Equatable {
    public var haptic: String
    public var tint: String
    public init(haptic: String, tint: String) {
        self.haptic = haptic
        self.tint = tint
    }
}

public struct DocumentControl: Codable, Equatable {
    public var id: String
    public var role: String
    public var customSlot: Int?
    public var bindings: [String: String]?
    public var radialSlots: [String: String]?
    public var command: String?
    public var placement: DocumentPlacement?
    public var label: String?
    public var hidden: Bool?
    public var feedback: DocumentFeedback?
    public init(id: String, role: String, customSlot: Int? = nil, bindings: [String: String]? = nil, radialSlots: [String: String]? = nil, command: String? = nil, placement: DocumentPlacement? = nil, label: String? = nil, hidden: Bool? = nil, feedback: DocumentFeedback? = nil) {
        self.id = id
        self.role = role
        self.customSlot = customSlot
        self.bindings = bindings
        self.radialSlots = radialSlots
        self.command = command
        self.placement = placement
        self.label = label
        self.hidden = hidden
        self.feedback = feedback
    }
}

public struct DocumentMode: Codable, Equatable {
    public var id: String
    public var name: String
    public var pointerMode: String?
    public var sizeFactor: Double?
    public var dpadStyle: String?
    public var holdAimEnabled: Bool?
    public var holdAimDelay: Double?
    public var trackpadHoldDelay: Double?
    public var floatingLeft: Bool?
    public var floatingRight: Bool?
    public var leftTap: String?
    public var rightTap: String?
    public var overrides: [String: DocumentOverride]?
    public var trackpadScroll: Bool?
    public init(id: String, name: String, pointerMode: String? = nil, sizeFactor: Double? = nil, dpadStyle: String? = nil, holdAimEnabled: Bool? = nil, holdAimDelay: Double? = nil, trackpadHoldDelay: Double? = nil, floatingLeft: Bool? = nil, floatingRight: Bool? = nil, leftTap: String? = nil, rightTap: String? = nil, overrides: [String: DocumentOverride]? = nil, trackpadScroll: Bool? = nil) {
        self.id = id
        self.name = name
        self.pointerMode = pointerMode
        self.sizeFactor = sizeFactor
        self.dpadStyle = dpadStyle
        self.holdAimEnabled = holdAimEnabled
        self.holdAimDelay = holdAimDelay
        self.trackpadHoldDelay = trackpadHoldDelay
        self.floatingLeft = floatingLeft
        self.floatingRight = floatingRight
        self.leftTap = leftTap
        self.rightTap = rightTap
        self.overrides = overrides
        self.trackpadScroll = trackpadScroll
    }
}

public struct DocumentKeyboardSettings: Codable, Equatable {
    public var mouseSpeed: Double?
    public var mouseSmoothing: Double?
    public var relativeGameAim: Bool?
    public var mouseUpdateRate: Int?
    public var rightStickMouse: Bool?
    public var autoRunEnabled: Bool?
    public var autoRunThreshold: Double?
    public var autoRunAction: String?
    public var invertMouseY: Bool?
    public var stickThreshold: Double?
    public var comboGap: Double?
    public var tapDuration: Double?
    public init(mouseSpeed: Double? = nil, mouseSmoothing: Double? = nil, relativeGameAim: Bool? = nil, mouseUpdateRate: Int? = nil, rightStickMouse: Bool? = nil, autoRunEnabled: Bool? = nil, autoRunThreshold: Double? = nil, autoRunAction: String? = nil, invertMouseY: Bool? = nil, stickThreshold: Double? = nil, comboGap: Double? = nil, tapDuration: Double? = nil) {
        self.mouseSpeed = mouseSpeed
        self.mouseSmoothing = mouseSmoothing
        self.relativeGameAim = relativeGameAim
        self.mouseUpdateRate = mouseUpdateRate
        self.rightStickMouse = rightStickMouse
        self.autoRunEnabled = autoRunEnabled
        self.autoRunThreshold = autoRunThreshold
        self.autoRunAction = autoRunAction
        self.invertMouseY = invertMouseY
        self.stickThreshold = stickThreshold
        self.comboGap = comboGap
        self.tapDuration = tapDuration
    }
}

public struct DocumentGamepadSettings: Codable, Equatable {
    public var swapSticks: Bool?
    public var disableLeftStick: Bool?
    public var disableRightStick: Bool?
    public var invertLeftY: Bool?
    public var invertRightY: Bool?
    public init(swapSticks: Bool? = nil, disableLeftStick: Bool? = nil, disableRightStick: Bool? = nil, invertLeftY: Bool? = nil, invertRightY: Bool? = nil) {
        self.swapSticks = swapSticks
        self.disableLeftStick = disableLeftStick
        self.disableRightStick = disableRightStick
        self.invertLeftY = invertLeftY
        self.invertRightY = invertRightY
    }
}

public struct DocumentMotionSettings: Codable, Equatable {
    public var mode: String?
    public var sensitivity: Double?
    public var deadZone: Double?
    public init(mode: String? = nil, sensitivity: Double? = nil, deadZone: Double? = nil) {
        self.mode = mode
        self.sensitivity = sensitivity
        self.deadZone = deadZone
    }
}

public struct DocumentAction: Codable, Equatable {
    public var label: String
    public var outputs: [String]
    public var behavior: String?
    public init(label: String, outputs: [String], behavior: String? = nil) {
        self.label = label
        self.outputs = outputs
        self.behavior = behavior
    }
}

public struct DocumentOverride: Codable, Equatable {
    public var placement: DocumentNullable<DocumentPlacement>?
    public var label: DocumentNullable<String>?
    public var hidden: Bool?
    public var feedback: DocumentNullable<DocumentFeedback>?
    public init(placement: DocumentNullable<DocumentPlacement>? = nil, label: DocumentNullable<String>? = nil, hidden: Bool? = nil, feedback: DocumentNullable<DocumentFeedback>? = nil) {
        self.placement = placement
        self.label = label
        self.hidden = hidden
        self.feedback = feedback
    }
}

public struct LayoutDocument: Codable, Equatable {
    public var format: String
    public var schemaVersion: Int
    public var runtimeProfile: String
    public var name: String
    public var inputType: String
    public var templateStyle: String
    public var controllerStyle: String?
    public var haptics: String?
    public var geometry: String
    public var actions: [String: DocumentAction]
    public var controls: [DocumentControl]
    public var modes: [DocumentMode]
    public var initialMode: String
    public var linkedControls: [String]?
    public var keyboard: DocumentKeyboardSettings?
    public var gamepad: DocumentGamepadSettings?
    public var motion: DocumentMotionSettings?
    public init(format: String = "pocketpad-layout", schemaVersion: Int = 2, runtimeProfile: String = "pocketpad-fixed-v1", name: String, inputType: String, templateStyle: String, controllerStyle: String? = nil, haptics: String? = nil, geometry: String = "runtimePresetV1", actions: [String: DocumentAction], controls: [DocumentControl], modes: [DocumentMode], initialMode: String, linkedControls: [String]? = nil, keyboard: DocumentKeyboardSettings? = nil, gamepad: DocumentGamepadSettings? = nil, motion: DocumentMotionSettings? = nil) {
        self.format = format
        self.schemaVersion = schemaVersion
        self.runtimeProfile = runtimeProfile
        self.name = name
        self.inputType = inputType
        self.templateStyle = templateStyle
        self.controllerStyle = controllerStyle
        self.haptics = haptics
        self.geometry = geometry
        self.actions = actions
        self.controls = controls
        self.modes = modes
        self.initialMode = initialMode
        self.linkedControls = linkedControls
        self.keyboard = keyboard
        self.gamepad = gamepad
        self.motion = motion
    }
}

public enum DocumentNullable<Value: Codable & Equatable>: Codable, Equatable {
    case null, value(Value)
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        self = c.decodeNil() ? .null : .value(try c.decode(Value.self))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .null: try c.encodeNil(); case .value(let v): try c.encode(v) }
    }
}
extension DocumentOverride {
    private enum CodingKeys: String, CodingKey { case placement, label, hidden, feedback }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        placement = c.contains(.placement) ? try c.decode(DocumentNullable<DocumentPlacement>.self, forKey: .placement) : nil
        label = c.contains(.label) ? try c.decode(DocumentNullable<String>.self, forKey: .label) : nil
        feedback = c.contains(.feedback) ? try c.decode(DocumentNullable<DocumentFeedback>.self, forKey: .feedback) : nil
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden)
    }
}
