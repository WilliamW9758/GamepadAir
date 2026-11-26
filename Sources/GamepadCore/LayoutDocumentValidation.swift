import Foundation
import CoreFoundation

public struct LayoutDocumentError: Error, LocalizedError, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

extension LayoutDocument {
    public static let maximumBytes = 256 * 1024
    /// All file, network and persistence boundaries use this entry point, not a bare JSONDecoder.
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumBytes else { throw LayoutDocumentError("Layout exceeds 256 KiB") }
        let json = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        try DocumentSchemaValidator.validate(json)
        let value = try JSONDecoder().decode(Self.self, from: data)
        try value.validateSemantics()
        return value
    }
    public func validatedData() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        _ = try Self.decode(data)
        return data
    }
    public func validate() throws { _ = try validatedData() }
    private func validateSemantics() throws {
        func require(_ condition: Bool, _ message: String) throws { if !condition { throw LayoutDocumentError(message) } }
        let isGamepad = inputType == "gamepad"
        try require(isGamepad ? (controllerStyle != nil && keyboard == nil) : (controllerStyle == nil && gamepad == nil), "Settings and controller identity must match the input type")
        for action in actions.values {
            try require(action.outputs.allSatisfy { $0.hasPrefix("gamepad.") == isGamepad }, "Output family does not match input type")
            try require(!isGamepad || (action.outputs.count <= 1 && (action.behavior ?? "hold") == "hold"), "Controller chords and tap behavior are unsupported")
        }
        var ids = Set<String>(), roles = Set<String>(), slots = Set<Int>()
        let cardinal = Set(["up", "right", "down", "left"])
        for control in controls {
            try require(ids.insert(control.id).inserted, "Duplicate control ID")
            if control.role == "customButton" {
                guard let slot = control.customSlot, slots.insert(slot).inserted else { throw LayoutDocumentError("Custom buttons require unique slots") }
            } else {
                try require(roles.insert(control.role).inserted && control.customSlot == nil, "Duplicate role or unexpected custom slot")
            }
            try require(control.role != "guide" || isGamepad, "Guide requires controller input")
            try require(control.role != "trackpad" || !isGamepad, "Trackpad requires keyboard/mouse input")
            func dimensions(_ p: DocumentPlacement?) throws {
                guard let p else { return }
                try require((p.referenceWidth == nil) == (p.referenceHeight == nil), "Anchor reference requires both dimensions")
                try require((p.width == nil) == (p.height == nil), "Rectangle requires both width and height")
                try require(p.width == nil || ["trackpad", "customButton"].contains(control.role), "Only trackpad and custom buttons support rectangular dimensions")
            }
            try dimensions(control.placement)
            for mode in modes { if case .value(let p) = mode.overrides?[control.id]?.placement { try dimensions(p) } }
            let stick = ["leftStick", "rightStick"].contains(control.role)
            var allowed = stick || control.role == "dpad" ? cardinal : Set(["press"])
            if ["radial", "modeSwitch", "trackpad"].contains(control.role) || (isGamepad && stick) { allowed = [] }
            let bindings = control.bindings ?? [:]
            try require(Set(bindings.keys).isSubset(of: allowed), "Unsupported binding role")
            try require(control.role != "rightStick" || isGamepad || keyboard?.rightStickMouse == false || bindings.isEmpty, "Mouse stick cannot also have directional bindings")
            try require(bindings.values.allSatisfy { actions[$0] != nil }, "Unknown action reference")
            try require(control.radialSlots == nil || control.role == "radial", "Only a radial can have radial slots")
            try require(control.role == "modeSwitch" ? control.command == "cycleModes" : control.command == nil, "Invalid mode switch command")
        }
        try require(motion?.mode != "steering" || isGamepad, "Analog steering requires gamepad input")
        if let id = motion?.activationControl {
            try require(motionActivationControls.contains { $0.id == id }, "Motion activation must reference a button or trigger")
        }
        let byID = Dictionary(uniqueKeysWithValues: controls.map { ($0.id, $0) })
        for control in controls {
            try require((control.radialSlots ?? [:]).values.allSatisfy { byID[$0]?.role == "customButton" }, "Radial target must be a custom button")
        }
        try require(Set(modes.map(\.id)).count == modes.count && initialMode == modes.first?.id, "Mode IDs must be unique and initialMode must be first")
        try require(Set(linkedControls ?? []).isSubset(of: ids), "Unknown linked control")
        let switches = controls.filter { $0.role == "modeSwitch" }
        try require((modes.count == 2) == !switches.isEmpty, "Two modes require a mode switch; one mode forbids it")
        for mode in modes {
            try require(Set((mode.overrides ?? [:]).keys).isSubset(of: ids), "Unknown override control")
            if let toggle = switches.first {
                try require(!(mode.overrides?[toggle.id]?.hidden ?? toggle.hidden ?? false), "Mode switch must be visible in every mode")
            }
        }
        try require(keyboard?.autoRunEnabled != true || keyboard?.autoRunAction != nil, "Auto-run requires an explicit action")
        if let id = keyboard?.autoRunAction {
            try require(actions[id] != nil && (actions[id]?.behavior ?? "hold") == "hold", "Auto-run requires a valid Hold action")
        }
    }
}

/// The contract uses this bounded subset of JSON Schema. Unknown schema keywords are not silently evaluated.
private enum DocumentSchemaValidator {
    static let root = try! JSONSerialization.jsonObject(with: Data(LayoutDocumentSchema.json.utf8)) as! [String: Any]
    static func validate(_ value: Any) throws { try check(value, schema: root, path: "layout") }
    static func check(_ value: Any, schema: [String: Any], path: String) throws {
        func fail(_ text: String) throws -> Never { throw LayoutDocumentError("\(path): \(text)") }
        if let ref = schema["$ref"] as? String {
            let name = String(ref.split(separator: "/").last!)
            try check(value, schema: (root["$defs"] as! [String: [String: Any]])[name]!, path: path); return
        }
        if let choices = schema["anyOf"] as? [[String: Any]] {
            for choice in choices { if (try? check(value, schema: choice, path: path)) != nil { return } }
            try fail("unsupported value")
        }
        func equal(_ a: Any, _ b: Any) -> Bool {
            // JSON booleans are not numeric 0/1.
            if let x = a as? NSNumber, let y = b as? NSNumber,
               (CFGetTypeID(x) == CFBooleanGetTypeID()) != (CFGetTypeID(y) == CFBooleanGetTypeID()) { return false }
            return (a as? NSObject)?.isEqual(b) == true
        }
        if let constant = schema["const"], !equal(value, constant) { try fail("unsupported format or version") }
        if let choices = schema["enum"] as? [Any], !choices.contains(where: { equal(value, $0) }) { try fail("unknown value") }
        switch schema["type"] as? String {
        case "null": if !(value is NSNull) { try fail("expected null") }
        case "object":
            guard let object = value as? [String: Any] else { try fail("expected object") }
            let props = schema["properties"] as? [String: [String: Any]] ?? [:]
            for key in schema["required"] as? [String] ?? [] where object[key] == nil { try fail("missing \(key)") }
            if let max = schema["maxProperties"] as? Int, object.count > max { try fail("too many fields") }
            for (key, child) in object {
                if let names = schema["propertyNames"] as? [String: Any] { try check(key, schema: names, path: path) }
                if let spec = props[key] { try check(child, schema: spec, path: path + "." + key) }
                else if let spec = schema["additionalProperties"] as? [String: Any] { try check(child, schema: spec, path: path + "." + key) }
                else if schema["additionalProperties"] as? Bool == false { try fail("unknown field \(key)") }
            }
        case "array":
            guard let list = value as? [Any] else { try fail("expected array") }
            if let min = schema["minItems"] as? Int, list.count < min { try fail("too few items") }
            if let max = schema["maxItems"] as? Int, list.count > max { try fail("too many items") }
            if schema["uniqueItems"] as? Bool == true {
                for i in list.indices where list.prefix(i).contains(where: { equal($0, list[i]) }) { try fail("duplicate item") }
            }
            if let item = schema["items"] as? [String: Any] { for (i, child) in list.enumerated() { try check(child, schema: item, path: "\(path)[\(i)]") } }
        case "string":
            guard let text = value as? String else { try fail("expected text") }
            if let min = schema["minLength"] as? Int, text.unicodeScalars.count < min { try fail("text too short") }
            if let max = schema["maxLength"] as? Int, text.unicodeScalars.count > max { try fail("text too long") }
            if let regex = schema["pattern"] as? String, text.range(of: regex, options: .regularExpression) == nil { try fail("invalid identifier") }
        case "boolean":
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { try fail("expected boolean") }
        case "number", "integer":
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { try fail("expected finite number") }
            let n = number.doubleValue
            if schema["type"] as? String == "integer", n.rounded() != n { try fail("expected integer") }
            if let min = schema["minimum"] as? Double, n < min { try fail("below minimum") }
            if let max = schema["maximum"] as? Double, n > max { try fail("above maximum") }
        default: break
        }
    }
}
