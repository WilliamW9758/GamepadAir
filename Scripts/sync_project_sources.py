#!/usr/bin/env python3
"""Add missing Swift sources while preserving Xcode signing settings and schemes."""
import hashlib
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
project = root / "iPhoneGamepad.xcodeproj/project.pbxproj"
data = json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(project)]))
objects = data["objects"]
main_group = objects[objects[data["rootObject"]]["mainGroup"]]

def identifier(value):
    return hashlib.sha256(value.encode()).hexdigest()[:24].upper()

for path in sorted(root.glob("Sources/**/*.swift")) + sorted(root.glob("Apps/**/*.swift")):
    relative = str(path.relative_to(root))
    if "GamepadHost/" in relative:
        continue
    ref = next((key for key, item in objects.items() if item.get("isa") == "PBXFileReference" and item.get("path") == relative), None)
    if ref is None:
        ref = identifier(relative)
        objects[ref] = dict(isa="PBXFileReference", lastKnownFileType="sourcecode.swift", path=relative, sourceTree="SOURCE_ROOT")
        main_group["children"].append(ref)
    for target in list(objects.values()):
        if target.get("isa") != "PBXNativeTarget":
            continue
        name = target["name"]
        include = relative.startswith("Sources/GamepadCore/") or (name == "MacGamepad" and relative.startswith(("Sources/MacSupport/", "Apps/Mac/"))) or (name == "PhoneGamepad" and relative.startswith("Apps/iPhone/"))
        if not include:
            continue
        phase = next(objects[key] for key in target["buildPhases"] if objects[key]["isa"] == "PBXSourcesBuildPhase")
        if any(objects[key]["fileRef"] == ref for key in phase["files"]):
            continue
        build = identifier(name + "-" + ref)
        objects[build] = dict(isa="PBXBuildFile", fileRef=ref)
        phase["files"].append(build)

def serialize(value):
    if isinstance(value, dict):
        return "{\n" + "".join(f"{json.dumps(key)} = {serialize(item)};\n" for key, item in value.items()) + "}"
    if isinstance(value, list):
        return "(" + ",\n".join(serialize(item) for item in value) + ")"
    return json.dumps(value)

project.write_text("// !$*UTF8*$!\n" + serialize(data) + "\n")
print("Swift source references synchronized; existing project settings preserved.")
