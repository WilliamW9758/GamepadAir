import json
from pathlib import Path

s = json.loads(Path("docs/layout-format/layout.schema.json").read_text())
names = {
    "placement": "DocumentPlacement",
    "motion": "DocumentMotionSettings",
    "feedback": "DocumentFeedback",
    "control": "DocumentControl",
    "mode": "DocumentMode",
    "keyboard": "DocumentKeyboardSettings",
    "gamepad": "DocumentGamepadSettings",
}
objects = {
    **{names[k]: v for k, v in s["$defs"].items()},
    "DocumentAction": s["properties"]["actions"]["additionalProperties"],
    "DocumentOverride": s["$defs"]["mode"]["properties"]["overrides"][
        "additionalProperties"
    ],
    "LayoutDocument": s,
}


def typ(v, field):
    if "$ref" in v:
        return names[v["$ref"].split("/")[-1]]
    if "anyOf" in v:
        return "DocumentNullable<" + typ(v["anyOf"][0], field) + ">"
    if "const" in v:
        return "Int" if isinstance(v["const"], int) else "String"
    if "enum" in v:
        return "Int" if isinstance(v["enum"][0], int) else "String"
    t = v.get("type")
    if t == "string":
        return "String"
    if t == "number":
        return "Double"
    if t == "integer":
        return "Int"
    if t == "boolean":
        return "Bool"
    if t == "array":
        return "[" + typ(v["items"], field) + "]"
    if field == "actions":
        return "[String: DocumentAction]"
    if field == "overrides":
        return "[String: DocumentOverride]"
    return "[String: String]"


out = [
    "import Foundation\n\n// JSON field types for docs/layout-format/layout.schema.json. Defaults are resolved, never inserted on decode.\n"
]
for name, obj in objects.items():
    out.append("public struct " + name + ": Codable, Equatable {")
    req = obj.get("required", [])
    for k, v in obj["properties"].items():
        out.append("    public var " + k + ": " + typ(v, k) + ("" if k in req else "?"))
    fields = []
    for k, v in obj["properties"].items():
        default = (
            " = nil"
            if k not in req
            else (" = " + json.dumps(v["const"]) if "const" in v else "")
        )
        fields.append(k + ": " + typ(v, k) + ("" if k in req else "?") + default)
    out.append("    public init(" + ", ".join(fields) + ") {")
    for k in obj["properties"]:
        out.append("        self." + k + " = " + k)
    out.append("    }\n}\n")
# Optional<T?> loses explicit null through synthesized decodeIfPresent; overrides need custom coding.
out.append("""public enum DocumentNullable<Value: Codable & Equatable>: Codable, Equatable {
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
""")
Path("Sources/GamepadCore/LayoutDocument.swift").write_text("\n".join(out))
# Embed the actual contract so validators are deterministic in app, CLI and SwiftPM builds.
Path("Sources/GamepadCore/LayoutDocumentSchema.swift").write_text(
    'import Foundation\n\n// Generated from docs/layout-format/layout.schema.json; fixture tests detect drift.\nenum LayoutDocumentSchema {\n    static let json = ##"'
    + json.dumps(s, separators=(",", ":"))
    + '"##\n}\n'
)
