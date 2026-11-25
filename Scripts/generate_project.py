#!/usr/bin/env python3
"""Generate the checked-in Xcode project with only Python's standard library."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
objects = {}

def ident(key):
    return hashlib.sha256(key.encode()).hexdigest()[:24].upper()

def add(key, **values):
    ref = ident(key)
    objects[ref] = values
    return ref

def serialize(value, indent=0):
    tab = "\t" * indent
    if isinstance(value, dict):
        return "{\n" + "".join(f'{tab}\t{json.dumps(k)} = {serialize(v, indent + 1)};\n' for k, v in value.items()) + tab + "}"
    if isinstance(value, list):
        return "(\n" + "".join(f"{tab}\t{serialize(v, indent + 1)},\n" for v in value) + tab + ")"
    return json.dumps(value)

base = add("base", isa="PBXFileReference", lastKnownFileType="text.xcconfig", path="Config/Base.xcconfig", sourceTree="SOURCE_ROOT")
files = {}
for path in sorted(ROOT.glob("Sources/**/*.swift")) + sorted(ROOT.glob("Apps/**/*.swift")):
    relative = str(path.relative_to(ROOT))
    if "GamepadHost" not in relative:
        files[relative] = add(relative, isa="PBXFileReference", lastKnownFileType="sourcecode.swift", path=relative, sourceTree="SOURCE_ROOT")

products = []
targets = []
for name, folder, platform in [("PhoneGamepad", "iPhone", "iphoneos"), ("MacGamepad", "Mac", "macosx")]:
    sources = [ref for path, ref in files.items() if path.startswith("Sources/GamepadCore/") or path.startswith(f"Apps/{folder}/") or (folder == "Mac" and path.startswith("Sources/MacSupport/"))]
    builds = [add(f"{name}-{ref}", isa="PBXBuildFile", fileRef=ref) for ref in sources]
    phase = add(f"{name}-sources", isa="PBXSourcesBuildPhase", buildActionMask=2147483647, files=builds, runOnlyForDeploymentPostprocessing=0)
    product = add(f"{name}-app", isa="PBXFileReference", explicitFileType="wrapper.application", path="Gamepad Air.app", sourceTree="BUILT_PRODUCTS_DIR")
    products.append(product)
    configs = []
    for config in ["Debug", "Release", "Gamepad"]:
        settings = dict(PRODUCT_NAME="Gamepad Air", EXECUTABLE_NAME=name, PRODUCT_BUNDLE_IDENTIFIER=f"$(BUNDLE_PREFIX).{folder.lower()}", SDKROOT=platform,
                        GENERATE_INFOPLIST_FILE="YES", CODE_SIGN_STYLE="Automatic", SWIFT_OPTIMIZATION_LEVEL="-Onone" if config == "Debug" else "-O",
                        INFOPLIST_KEY_CFBundleDisplayName="Gamepad Air", INFOPLIST_KEY_CFBundleName="Gamepad Air", CURRENT_PROJECT_VERSION="1", MARKETING_VERSION="0.1.0")
        if folder == "iPhone":
            settings.update(IPHONEOS_DEPLOYMENT_TARGET="17.0", TARGETED_DEVICE_FAMILY="1", SUPPORTED_PLATFORMS="iphoneos iphonesimulator",
                            INFOPLIST_KEY_UILaunchScreen_Generation="YES", INFOPLIST_KEY_UISupportedInterfaceOrientations="UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight",
                            INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents="YES")
        else:
            settings.update(MACOSX_DEPLOYMENT_TARGET="15.0", ENABLE_APP_SANDBOX="NO", COMBINE_HIDPI_IMAGES="YES")
            if config == "Gamepad":
                settings.update(CODE_SIGN_ENTITLEMENTS="Config/Gamepad.entitlements", CODE_SIGN_IDENTITY="Apple Development")
            else:
                settings.update(CODE_SIGN_IDENTITY="-", CODE_SIGNING_REQUIRED="NO")
        configs.append(add(f"{name}-{config}", isa="XCBuildConfiguration", name=config, baseConfigurationReference=base, buildSettings=settings))
    config_list = add(f"{name}-configs", isa="XCConfigurationList", buildConfigurations=configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Debug")
    target = add(name, isa="PBXNativeTarget", name=name, productName=name, productReference=product, productType="com.apple.product-type.application", buildConfigurationList=config_list, buildPhases=[phase], buildRules=[], dependencies=[])
    targets.append(target)
    scheme_dir = ROOT / "iPhoneGamepad.xcodeproj/xcshareddata/xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)
    ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{name}.app" BlueprintName="{name}" ReferencedContainer="container:iPhoneGamepad.xcodeproj"/>'
    (scheme_dir / f"{name}.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')

products_group = add("products", isa="PBXGroup", children=products, name="Products", sourceTree="<group>")
group = add("main-group", isa="PBXGroup", children=list(files.values()) + [base, products_group], sourceTree="<group>")
configs = [add(f"project-{name}", isa="XCBuildConfiguration", name=name, buildSettings={"CLANG_ENABLE_MODULES": "YES", "SWIFT_VERSION": "5.0"}) for name in ["Debug", "Release", "Gamepad"]]
config_list = add("project-configs", isa="XCConfigurationList", buildConfigurations=configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Debug")
project = add("project", isa="PBXProject", attributes={"LastUpgradeCheck": "1600"}, buildConfigurationList=config_list, compatibilityVersion="Xcode 14.0", developmentRegion="en", hasScannedForEncodings=0, knownRegions=["en", "Base"], mainGroup=group, productRefGroup=products_group, projectDirPath="", projectRoot="", targets=targets)
(ROOT / "iPhoneGamepad.xcodeproj/project.pbxproj").write_text("// !$*UTF8*$!\n" + serialize(dict(archiveVersion=1, classes={}, objectVersion=56, objects=objects, rootObject=project)) + "\n")
print("Generated iPhoneGamepad.xcodeproj")
