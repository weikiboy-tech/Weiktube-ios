#!/usr/bin/env python3
"""Deterministically generate the dependency-free Xcode project from repository source files."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
PROJECT = Path("Weiktube.xcodeproj/project.pbxproj")
SCHEME = Path("Weiktube.xcodeproj/xcshareddata/xcschemes/Weiktube.xcscheme")
TARGETS = ("Weiktube", "ShareExtension", "WeiktubeTests", "WeiktubeUITests")
SHARED_EXTENSION_SOURCES = (
    "Weiktube/Navigation/YouTubeLinkRouter.swift",
    "Weiktube/Persistence/AtomicJSONFile.swift",
    "Weiktube/Persistence/SharedLinkInbox.swift",
)


def stable_id(kind: str, name: str) -> str:
    return hashlib.sha256(f"Weiktube-iOS:{kind}:{name}".encode()).hexdigest()[:24].upper()


def paths_below(directory: str, pattern: str) -> list[str]:
    return sorted(path.relative_to(ROOT).as_posix() for path in (ROOT / directory).rglob(pattern)
                  if "VendorSource" not in path.parts and path.is_file())


def source_inventory() -> dict[str, list[str]]:
    return {
        "Weiktube": paths_below("Weiktube", "*.swift"),
        "ShareExtension": sorted(set(paths_below("ShareExtension", "*.swift") + list(SHARED_EXTENSION_SOURCES))),
        "WeiktubeTests": paths_below("WeiktubeTests", "*.swift"),
        "WeiktubeUITests": paths_below("WeiktubeUITests", "*.swift"),
    }


def resource_inventory() -> list[str]:
    resources: set[str] = set()
    for name in ("LICENSE", "THIRD-PARTY-NOTICES.md", "Weiktube/Resources/Filters"):
        if (ROOT / name).exists():
            resources.add(name)
    for path in (ROOT / "Weiktube").rglob("*"):
        if "VendorSource" in path.parts:
            continue
        relative = path.relative_to(ROOT).as_posix()
        if path.suffix == ".xcassets" or path.suffix == ".xcprivacy":
            resources.add(relative)
        elif path.is_file() and relative.startswith("Weiktube/Resources/"):
            if "/Filters/" not in relative and not any(part.endswith(".xcassets") for part in path.parts):
                if path.suffix.lower() not in (".swift", ".plist", ".entitlements", ".cjs"):
                    resources.add(relative)
    return sorted(resources)


def file_type(path: str) -> str:
    if (ROOT / path).is_dir():
        return "folder.assetcatalog" if path.endswith(".xcassets") else "folder"
    return {
        ".swift": "sourcecode.swift", ".js": "sourcecode.javascript", ".cjs": "sourcecode.javascript",
        ".py": "text.script.python", ".plist": "text.plist.xml", ".entitlements": "text.plist.entitlements",
        ".xcprivacy": "text.xml", ".xcconfig": "text.xcconfig", ".md": "net.daringfireball.markdown",
        ".yml": "text.yaml", ".json": "text.json", ".png": "image.png",
    }.get(Path(path).suffix.lower(), "text")


def make_project() -> dict:
    objects: dict[str, dict] = {}
    project_id = stable_id("project", "Weiktube")
    inventories = source_inventory()
    resources = resource_inventory()
    displayed = set(resources)
    for values in inventories.values():
        displayed.update(values)
    for directory in ("Config", "scripts", "ShareExtension"):
        for path in (ROOT / directory).glob("*"):
            if path.is_file() and path.name != "Local.xcconfig" and path.suffix != ".pyc":
                displayed.add(path.relative_to(ROOT).as_posix())
    for path in (ROOT / "Weiktube").glob("*"):
        if path.suffix in (".plist", ".entitlements"):
            displayed.add(path.relative_to(ROOT).as_posix())
    for path in ROOT.glob("*.md"):
        displayed.add(path.name)
    displayed.update(paths_below(".github/workflows", "*.yml"))
    displayed.update(paths_below("WeiktubeTests", "*.cjs"))
    displayed.add("Package.swift")
    file_ids = {}
    for path in sorted(displayed):
        file_id = stable_id("file", path)
        file_ids[path] = file_id
        objects[file_id] = {"isa": "PBXFileReference", "lastKnownFileType": file_type(path),
                            "path": path, "sourceTree": "SOURCE_ROOT"}

    tree: dict = {}
    for path in sorted(displayed):
        cursor = tree
        parts = Path(path).parts
        for part in parts[:-1]:
            cursor = cursor.setdefault(part, {})
        cursor[parts[-1]] = file_ids[path]

    def group(node: dict, location: str) -> str:
        identifier = stable_id("group", location)
        children = []
        for name, value in sorted(node.items(), key=lambda pair: (not isinstance(pair[1], dict), pair[0].lower())):
            children.append(group(value, location + "/" + name) if isinstance(value, dict) else value)
        objects[identifier] = {"isa": "PBXGroup", "children": children, "sourceTree": "<group>"}
        if location:
            objects[identifier]["name"] = location.rsplit("/", 1)[-1]
        return identifier

    main_group = group(tree, "")
    product_group = stable_id("group", "Products")
    product_refs = {}
    product_types = {
        "Weiktube": ("app", "wrapper.application", "com.apple.product-type.application"),
        "ShareExtension": ("appex", "wrapper.app-extension", "com.apple.product-type.app-extension"),
        "WeiktubeTests": ("xctest", "wrapper.cfbundle", "com.apple.product-type.bundle.unit-test"),
        "WeiktubeUITests": ("xctest", "wrapper.cfbundle", "com.apple.product-type.bundle.ui-testing"),
    }
    for name, (extension, kind, _) in product_types.items():
        identifier = stable_id("product", name)
        product_refs[name] = identifier
        objects[identifier] = {"isa": "PBXFileReference", "explicitFileType": kind,
                               "includeInIndex": 0, "path": name + "." + extension, "sourceTree": "BUILT_PRODUCTS_DIR"}
    objects[product_group] = {"isa": "PBXGroup", "children": list(product_refs.values()), "name": "Products", "sourceTree": "<group>"}
    objects[main_group]["children"].append(product_group)

    def config_list(owner: str, settings: dict, base: bool = False) -> str:
        configurations = []
        for configuration in ("Debug", "Release"):
            identifier = stable_id("configuration", owner + ":" + configuration)
            value = {"isa": "XCBuildConfiguration", "buildSettings": dict(settings), "name": configuration}
            if base:
                value["baseConfigurationReference"] = file_ids[f"Config/{configuration}.xcconfig"]
            objects[identifier] = value
            configurations.append(identifier)
        identifier = stable_id("configuration-list", owner)
        objects[identifier] = {"isa": "XCConfigurationList", "buildConfigurations": configurations,
                               "defaultConfigurationIsVisible": 0, "defaultConfigurationName": "Release"}
        return identifier

    project_config = config_list("project", {
        "ALWAYS_SEARCH_USER_PATHS": "NO", "SDKROOT": "iphoneos", "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
        "CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER": "YES", "GCC_C_LANGUAGE_STANDARD": "gnu17",
    }, base=True)

    def build_phase(target: str, kind: str, files: list[str]) -> str:
        phase_id = stable_id("phase", target + ":" + kind)
        builds = []
        for path in files:
            build_id = stable_id("build-file", target + ":" + kind + ":" + path)
            objects[build_id] = {"isa": "PBXBuildFile", "fileRef": file_ids[path]}
            builds.append(build_id)
        objects[phase_id] = {"isa": "PBX" + kind + "BuildPhase", "buildActionMask": 2147483647,
                             "files": builds, "runOnlyForDeploymentPostprocessing": 0}
        return phase_id

    def dependency(owner: str, destination: str) -> str:
        proxy = stable_id("proxy", owner + ":" + destination)
        objects[proxy] = {"isa": "PBXContainerItemProxy", "containerPortal": project_id, "proxyType": 1,
                          "remoteGlobalIDString": stable_id("target", destination), "remoteInfo": destination}
        identifier = stable_id("dependency", owner + ":" + destination)
        objects[identifier] = {"isa": "PBXTargetDependency", "target": stable_id("target", destination), "targetProxy": proxy}
        return identifier

    target_attributes = {}
    for target in TARGETS:
        phases = [build_phase(target, "Sources", inventories[target]), build_phase(target, "Frameworks", []),
                  build_phase(target, "Resources", resources if target == "Weiktube" else [])]
        settings = {
            "PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_MODULE_NAME": target,
            "TARGETED_DEVICE_FAMILY": "1,2", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
            "SUPPORTS_MACCATALYST": "NO", "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD": "NO",
            "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
        }
        dependencies = []
        attributes = {"CreatedOnToolsVersion": "16.0", "ProvisioningStyle": "Automatic"}
        if target == "Weiktube":
            settings.update({
                "PRODUCT_BUNDLE_IDENTIFIER": "$(WEIKTUBE_BUNDLE_ID)",
                "GENERATE_INFOPLIST_FILE": "NO", "INFOPLIST_FILE": "$(DERIVED_FILE_DIR)/Weiktube-Info.plist",
                "INFOPLIST_EXPAND_BUILD_SETTINGS": "YES", "CODE_SIGN_ENTITLEMENTS": "Weiktube/Weiktube.entitlements",
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
                "SKIP_INSTALL": "NO",
            })
            script_id = stable_id("phase", "Prepare app Info.plist")
            objects[script_id] = {
                "isa": "PBXShellScriptBuildPhase", "buildActionMask": 2147483647, "files": [],
                "name": "Prepare configured app Info.plist", "alwaysOutOfDate": 1,
                "inputPaths": ["$(SRCROOT)/Weiktube/Info.plist", "$(SRCROOT)/scripts/prepare-info.py"],
                "outputPaths": ["$(DERIVED_FILE_DIR)/Weiktube-Info.plist"],
                "runOnlyForDeploymentPostprocessing": 0, "shellPath": "/bin/sh",
                "shellScript": 'set -eu\n/usr/bin/env python3 "$SRCROOT/scripts/prepare-info.py" --input "$SRCROOT/Weiktube/Info.plist" --output "$DERIVED_FILE_DIR/Weiktube-Info.plist"\n',
                "showEnvVarsInLog": 0,
            }
            phases.insert(0, script_id)
            embed_id = stable_id("phase", "Embed app extensions")
            embed_file = stable_id("build-file", "Embed ShareExtension")
            objects[embed_file] = {"isa": "PBXBuildFile", "fileRef": product_refs["ShareExtension"],
                                   "settings": {"ATTRIBUTES": ["RemoveHeadersOnCopy"]}}
            objects[embed_id] = {"isa": "PBXCopyFilesBuildPhase", "buildActionMask": 2147483647, "dstPath": "",
                                 "dstSubfolderSpec": 13, "files": [embed_file], "name": "Embed App Extensions",
                                 "runOnlyForDeploymentPostprocessing": 0}
            phases.append(embed_id)
            dependencies.append(dependency(target, "ShareExtension"))
            attributes["SystemCapabilities"] = {"com.apple.ApplicationGroups.iOS": {"enabled": 1}}
        elif target == "ShareExtension":
            settings.update({
                "PRODUCT_BUNDLE_IDENTIFIER": "$(WEIKTUBE_BUNDLE_ID).share", "GENERATE_INFOPLIST_FILE": "NO",
                "INFOPLIST_FILE": "ShareExtension/Info.plist", "INFOPLIST_EXPAND_BUILD_SETTINGS": "YES",
                "CODE_SIGN_ENTITLEMENTS": "ShareExtension/ShareExtension.entitlements",
                "APPLICATION_EXTENSION_API_ONLY": "YES", "SKIP_INSTALL": "YES",
                "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"],
            })
            attributes["SystemCapabilities"] = {"com.apple.ApplicationGroups.iOS": {"enabled": 1}}
        else:
            suffix = ".tests" if target == "WeiktubeTests" else ".uitests"
            settings.update({"PRODUCT_BUNDLE_IDENTIFIER": "$(WEIKTUBE_BUNDLE_ID)" + suffix,
                             "GENERATE_INFOPLIST_FILE": "YES", "TEST_TARGET_NAME": "Weiktube",
                             "SKIP_INSTALL": "YES"})
            if target == "WeiktubeTests":
                settings.update({"BUNDLE_LOADER": "$(TEST_HOST)", "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/Weiktube.app/Weiktube"})
            dependencies.append(dependency(target, "Weiktube"))
            attributes["TestTargetID"] = stable_id("target", "Weiktube")
        identifier = stable_id("target", target)
        target_attributes[identifier] = attributes
        objects[identifier] = {
            "isa": "PBXNativeTarget", "buildConfigurationList": config_list(target, settings),
            "buildPhases": phases, "buildRules": [], "dependencies": dependencies, "name": target,
            "productName": target, "productReference": product_refs[target], "productType": product_types[target][2],
        }

    objects[project_id] = {
        "isa": "PBXProject", "attributes": {"BuildIndependentTargetsInParallel": "YES", "LastUpgradeCheck": "1600",
                                               "LastSwiftUpdateCheck": "1600", "TargetAttributes": target_attributes},
        "buildConfigurationList": project_config, "compatibilityVersion": "Xcode 14.0", "developmentRegion": "de",
        "hasScannedForEncodings": 0, "knownRegions": ["de", "en", "Base"], "mainGroup": main_group,
        "productRefGroup": product_group, "projectDirPath": "", "projectRoot": "",
        "targets": [stable_id("target", target) for target in TARGETS],
    }
    return {"archiveVersion": 1, "classes": {}, "objectVersion": 56, "objects": dict(sorted(objects.items())), "rootObject": project_id}


def quote(value: str) -> str:
    return value if re.fullmatch(r"[A-Za-z0-9_./]+", value) else json.dumps(value, ensure_ascii=False)


def openstep(value: object, indentation: int = 0) -> str:
    prefix = "\t" * indentation
    if isinstance(value, dict):
        lines = ["{"]
        for key, item in value.items():
            lines.append(prefix + "\t" + quote(str(key)) + " = " + openstep(item, indentation + 1) + ";")
        return "\n".join(lines + [prefix + "}"])
    if isinstance(value, list):
        return "(\n" + "".join(prefix + "\t" + openstep(item, indentation + 1) + ",\n" for item in value) + prefix + ")"
    if isinstance(value, int):
        return str(value)
    return quote(str(value))


def scheme_text() -> str:
    scheme = ET.Element("Scheme", LastUpgradeVersion="1600", version="1.3")

    def reference(parent: ET.Element, target: str) -> None:
        extension = "app" if target == "Weiktube" else "xctest"
        ET.SubElement(parent, "BuildableReference", BuildableIdentifier="primary", BlueprintIdentifier=stable_id("target", target),
                      BuildableName=target + "." + extension, BlueprintName=target, ReferencedContainer="container:Weiktube.xcodeproj")

    build = ET.SubElement(scheme, "BuildAction", parallelizeBuildables="YES", buildImplicitDependencies="YES")
    entries = ET.SubElement(build, "BuildActionEntries")
    for target in ("Weiktube", "WeiktubeTests", "WeiktubeUITests"):
        production = "YES" if target == "Weiktube" else "NO"
        entry = ET.SubElement(entries, "BuildActionEntry", buildForTesting="YES", buildForRunning=production,
                              buildForProfiling=production, buildForArchiving=production, buildForAnalyzing=production)
        reference(entry, target)
    test = ET.SubElement(scheme, "TestAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB",
                         selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", shouldUseLaunchSchemeArgsEnv="NO", codeCoverageEnabled="YES")
    arguments = ET.SubElement(test, "CommandLineArguments")
    ET.SubElement(arguments, "CommandLineArgument", argument="--ui-testing", isEnabled="YES")
    testables = ET.SubElement(test, "Testables")
    for target in ("WeiktubeTests", "WeiktubeUITests"):
        reference(ET.SubElement(testables, "TestableReference", skipped="NO", parallelizable="NO"), target)
    launch = ET.SubElement(scheme, "LaunchAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB",
                           selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", launchStyle="0", useCustomWorkingDirectory="NO",
                           ignoresPersistentStateOnLaunch="NO", debugDocumentVersioning="YES", allowLocationSimulation="YES")
    reference(ET.SubElement(launch, "BuildableProductRunnable", runnableDebuggingMode="0"), "Weiktube")
    profile = ET.SubElement(scheme, "ProfileAction", buildConfiguration="Release", shouldUseLaunchSchemeArgsEnv="YES",
                            savedToolIdentifier="", useCustomWorkingDirectory="NO", debugDocumentVersioning="YES")
    reference(ET.SubElement(profile, "BuildableProductRunnable", runnableDebuggingMode="0"), "Weiktube")
    ET.SubElement(scheme, "AnalyzeAction", buildConfiguration="Debug")
    ET.SubElement(scheme, "ArchiveAction", buildConfiguration="Release", revealArchiveInOrganizer="YES")
    ET.indent(scheme, space="  ")
    return '<?xml version="1.0" encoding="UTF-8"?>\n' + ET.tostring(scheme, encoding="unicode") + "\n"


def generated_files() -> dict[Path, str]:
    return {PROJECT: "// !$*UTF8*$!\n" + openstep(make_project()) + "\n", SCHEME: scheme_text()}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Fail if checked-in project files do not match current source inventory.")
    arguments = parser.parse_args()
    stale = []
    for relative, text in generated_files().items():
        destination = ROOT / relative
        if arguments.check:
            if not destination.is_file() or destination.read_text() != text:
                stale.append(relative.as_posix())
        else:
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_text(text)
    if stale:
        print("Project is stale; run python3 scripts/generate-project.py:", *stale, sep="\n  ", file=sys.stderr)
        return 1
    counts = {name: len(paths) for name, paths in source_inventory().items()}
    print(("Checked" if arguments.check else "Generated") + " deterministic Xcode project: " + json.dumps(counts, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
