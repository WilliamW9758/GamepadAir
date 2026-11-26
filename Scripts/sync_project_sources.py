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

# Remove registrations only for deleted project-owned Swift sources. This supports
# source renames without regenerating signing settings or unrelated project objects.
removed = {
    key for key, item in objects.items()
    if item.get("isa") == "PBXFileReference"
    and item.get("lastKnownFileType") == "sourcecode.swift"
    and item.get("sourceTree") == "SOURCE_ROOT"
    and item.get("path", "").startswith(("Sources/", "Apps/"))
    and not (root / item["path"]).exists()
}
removed.update(key for key, item in objects.items()
               if item.get("isa") == "PBXBuildFile" and item.get("fileRef") in removed)
for item in objects.values():
    for field in ("children", "files"):
        if field in item:
            item[field] = [key for key in item[field] if key not in removed]
for key in removed:
    del objects[key]

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
        include = relative.startswith(("Sources/GamepadCore/", "Apps/Shared/")) or (name == "MacGamepad" and relative.startswith(("Sources/MacSupport/", "Apps/Mac/"))) or (name == "PhoneGamepad" and relative.startswith("Apps/iPhone/"))
        if not include:
            continue
        phase = next(objects[key] for key in target["buildPhases"] if objects[key]["isa"] == "PBXSourcesBuildPhase")
        if any(objects[key]["fileRef"] == ref for key in phase["files"]):
            continue
        build = identifier(name + "-" + ref)
        objects[build] = dict(isa="PBXBuildFile", fileRef=ref)
        phase["files"].append(build)

# Layered iPhone icons are compiled by actool; the Mac keeps its existing catalog icon.
phone = next(item for item in objects.values() if item.get("isa") == "PBXNativeTarget" and item["name"] == "PhoneGamepad")
resources = next(objects[key] for key in phone["buildPhases"] if objects[key]["isa"] == "PBXResourcesBuildPhase")
for path in sorted((root / "Assets/LayeredIcons").glob("*.icon")):
    relative = str(path.relative_to(root))
    ref = identifier(relative)
    objects[ref] = dict(isa="PBXFileReference", lastKnownFileType="folder.icon", path=relative, sourceTree="SOURCE_ROOT")
    if ref not in main_group["children"]:
        main_group["children"].append(ref)
    build = identifier("PhoneGamepad-" + ref)
    objects[build] = dict(isa="PBXBuildFile", fileRef=ref)
    if build not in resources["files"]:
        resources["files"].append(build)
for config in objects[phone["buildConfigurationList"]]["buildConfigurations"]:
    settings = objects[config]["buildSettings"]
    settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = "PocketPad"
    settings["ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES"] = "AppIconWhite AppIconGraphite"

# Sparkle is Mac-only; keep the core Swift package and iPhone dependency-free.
mac = next(item for item in objects.values() if item.get("isa") == "PBXNativeTarget" and item["name"] == "MacGamepad")
package = identifier("Sparkle-package")
product = identifier("Sparkle-product")
link = identifier("Sparkle-link")
embed = identifier("Sparkle-embed")
objects[package] = dict(isa="XCRemoteSwiftPackageReference", repositoryURL="https://github.com/sparkle-project/Sparkle", requirement=dict(kind="exactVersion", version="2.10.1"))
objects[product] = dict(isa="XCSwiftPackageProductDependency", package=package, productName="Sparkle")
project_object = objects[data["rootObject"]]
project_object.setdefault("packageReferences", [])
if package not in project_object["packageReferences"]:
    project_object["packageReferences"].append(package)
mac.setdefault("packageProductDependencies", [])
if product not in mac["packageProductDependencies"]:
    mac["packageProductDependencies"].append(product)
objects[link] = dict(isa="PBXBuildFile", productRef=product)
# Xcode automatically embeds/re-signs the linked binary package product.
mac["buildPhases"] = [key for key in mac["buildPhases"] if key != identifier("Sparkle-embed-phase")]
objects.pop(identifier("Sparkle-embed-phase"), None)
objects.pop(embed, None)
for kind, key, build in [("PBXFrameworksBuildPhase", "Sparkle-frameworks", link)]:
    phase_id = identifier(key)
    objects[phase_id] = dict(isa=kind, buildActionMask=2147483647, files=[build], runOnlyForDeploymentPostprocessing=0)
    if kind == "PBXCopyFilesBuildPhase":
        objects[phase_id].update(dstPath="", dstSubfolderSpec=10, name="Embed Sparkle")
    if phase_id not in mac["buildPhases"]:
        mac["buildPhases"].append(phase_id)
for config in objects[mac["buildConfigurationList"]]["buildConfigurations"]:
    objects[config]["buildSettings"]["LD_RUNPATH_SEARCH_PATHS"] = "$(inherited) @executable_path/../Frameworks"

def serialize(value):
    if isinstance(value, dict):
        return "{\n" + "".join(f"{json.dumps(key)} = {serialize(item)};\n" for key, item in value.items()) + "}"
    if isinstance(value, list):
        return "(" + ",\n".join(serialize(item) for item in value) + ")"
    return json.dumps(value)

project.write_text("// !$*UTF8*$!\n" + serialize(data) + "\n")
print("Swift source references synchronized; existing project settings preserved.")
