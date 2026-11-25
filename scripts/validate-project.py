#!/usr/bin/env python3
"""Check the generated Xcode graph, source coverage, resources, plist configuration and scheme."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import plistlib
import re
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def load_script(name: str):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), ROOT / "scripts" / (name + ".py"))
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def parse_openstep(text: str) -> dict:
    text = "\n".join(line for line in text.splitlines() if not line.startswith("//"))
    tokens = re.findall(r'"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,]+', text)
    position = 0

    def take(expected: str | None = None) -> str:
        nonlocal position
        if position >= len(tokens):
            raise ValueError("Unexpected end of project file")
        result = tokens[position]
        position += 1
        if expected is not None and result != expected:
            raise ValueError(f"Expected {expected!r}, found {result!r}")
        return result

    def value():
        token = take()
        if token == "{":
            result = {}
            while tokens[position] != "}":
                key = value()
                take("=")
                result[key] = value()
                take(";")
            take("}")
            return result
        if token == "(":
            result = []
            while tokens[position] != ")":
                result.append(value())
                if tokens[position] == ",":
                    take(",")
            take(")")
            return result
        return json.loads(token) if token.startswith('"') else token

    result = value()
    if position != len(tokens) or not isinstance(result, dict):
        raise ValueError("Project contains trailing tokens or a non-dictionary root")
    return result


def main() -> int:
    generator = load_script("generate-project")
    failures: list[str] = []

    def check(condition: bool, message: str) -> None:
        if not condition:
            failures.append(message)

    try:
        expected = generator.generated_files()
        for relative, text in expected.items():
            path = ROOT / relative
            check(path.is_file() and path.read_text() == text, f"Generated file is stale: {relative}; run scripts/generate-project.py")
        document = parse_openstep((ROOT / generator.PROJECT).read_text())
        objects = document["objects"]
        project = objects[document["rootObject"]]
        check(project["isa"] == "PBXProject", "Root object is not PBXProject")
        target_objects = {objects[reference]["name"]: objects[reference] for reference in project["targets"]}
        check(set(target_objects) == set(generator.TARGETS), "Expected app, extension, unit-test and UI-test targets")

        for identifier, item in objects.items():
            check(bool(re.fullmatch(r"[A-F0-9]{24}", identifier)), "Invalid deterministic project identifier")
            if item["isa"] == "PBXFileReference" and item.get("sourceTree") == "SOURCE_ROOT":
                check((ROOT / item["path"]).exists(), f"Missing referenced file: {item['path']}")
                check("VendorSource" not in Path(item["path"]).parts, "VendorSource must not be packaged or compiled")
            for key in ("fileRef", "mainGroup", "productRefGroup", "buildConfigurationList", "productReference", "target", "targetProxy", "containerPortal", "baseConfigurationReference"):
                if key in item:
                    check(item[key] in objects, f"Dangling {key} in {item['isa']}")
            for key in ("children", "files", "buildPhases", "buildConfigurations", "dependencies", "targets"):
                if key in item:
                    check(all(reference in objects for reference in item[key]), f"Dangling {key} in {item['isa']}")

        def phase_paths(target: dict, kind: str) -> list[str]:
            phases = [objects[reference] for reference in target["buildPhases"] if objects[reference]["isa"] == kind]
            return [objects[objects[build]["fileRef"]]["path"] for phase in phases for build in phase["files"]]

        inventories = generator.source_inventory()
        for name, target in target_objects.items():
            actual = phase_paths(target, "PBXSourcesBuildPhase")
            check(sorted(actual) == inventories[name], f"Incomplete or duplicate source membership: {name}")
            check(bool(actual), f"Target has no Swift source: {name}")
            configurations = objects[target["buildConfigurationList"]]["buildConfigurations"]
            check({objects[reference]["name"] for reference in configurations} == {"Debug", "Release"}, f"Missing configurations: {name}")
            settings = [objects[reference]["buildSettings"] for reference in configurations]
            check(all(value.get("TARGETED_DEVICE_FAMILY") == "1,2" for value in settings), f"iPhone/iPad family missing: {name}")
            check(all("DEVELOPMENT_TEAM" not in value for value in settings), f"Do not invent or pin a signing team: {name}")

        share_sources = set(inventories["ShareExtension"])
        check(set(generator.SHARED_EXTENSION_SOURCES).issubset(share_sources), "Share extension lacks secure router or atomic queue")
        check(any(path.startswith("ShareExtension/") for path in share_sources), "Share controller source is missing")
        app_resources = phase_paths(target_objects["Weiktube"], "PBXResourcesBuildPhase")
        check(sorted(app_resources) == generator.resource_inventory(), "App resource membership differs from inventory")
        check(not any(Path(path).suffix.lower() == ".cjs" for path in app_resources), "Node fixture tests must not be bundled in the app")
        required_resources = {"Weiktube/Resources/MediaBridge.js", "Weiktube/Resources/Filters", "LICENSE", "THIRD-PARTY-NOTICES.md"}
        check(required_resources.issubset(app_resources), "Missing media bridge, filter folder, license or third-party notices")
        check(sum(path.endswith(".xcassets") for path in app_resources) == 1, "Exactly one app asset catalog is required")
        privacy = [path for path in app_resources if path.endswith(".xcprivacy")]
        check(len(privacy) == 1, "Exactly one app privacy manifest is required")
        for path in privacy:
            with (ROOT / path).open("rb") as stream:
                plistlib.load(stream)
        for filename in ("rules.json", "rules.sig", "update-public-key.txt", "filter-runtime-ios.js", "vendor-scriptlets.js", "ADGUARD-LICENSE.txt", "PROVENANCE.md"):
            check((ROOT / "Weiktube/Resources/Filters" / filename).is_file(), f"Filter bundle resource missing: {filename}")
        copied = phase_paths(target_objects["Weiktube"], "PBXCopyFilesBuildPhase")
        check(copied == ["ShareExtension.appex"], "Share extension must be embedded once")
        check(any(objects[reference].get("target") == generator.stable_id("target", "ShareExtension")
                  for reference in target_objects["Weiktube"]["dependencies"]), "App lacks extension target dependency")

        with (ROOT / "Weiktube/Info.plist").open("rb") as stream:
            app_info = plistlib.load(stream)
        check(app_info.get("UIBackgroundModes") == ["audio"], "Audio/PiP background mode is missing or includes unsupported values")
        check("UIInterfaceOrientationPortraitUpsideDown" not in app_info["UISupportedInterfaceOrientations"], "iPhone should ignore upside-down orientation")
        check(len(app_info["UISupportedInterfaceOrientations~ipad"]) == 4, "iPad multitasking requires all interface orientations")
        check(not app_info.get("UIRequiresFullScreen", False), "iPad multitasking must remain enabled")
        check(app_info.get("WeiktubeAppGroup") == "$(WEIKTUBE_APP_GROUP)", "App group plist key does not match build setting")
        prepare = load_script("prepare-info")
        empty_oauth = prepare.configured_plist(app_info, {})
        check([entry["CFBundleURLSchemes"] for entry in empty_oauth["CFBundleURLTypes"]] == [["weiktube"]], "Empty OAuth defaults must not register an empty scheme")
        configured = prepare.configured_plist(app_info, {
            "GOOGLE_OAUTH_CLIENT_ID": "123-example.apps.googleusercontent.com",
            "GOOGLE_REVERSED_CLIENT_ID": "com.googleusercontent.apps.123-example",
            "GOOGLE_OAUTH_REDIRECT_URI": "com.googleusercontent.apps.123-example:/oauthredirect",
        })
        check(configured["CFBundleURLTypes"][-1]["CFBundleURLSchemes"] == ["com.googleusercontent.apps.123-example"], "Configured OAuth callback is not registered")
        try:
            prepare.configured_plist(app_info, {"GOOGLE_REVERSED_CLIENT_ID": "wrong"})
            check(False, "Partial OAuth configuration must fail preparation")
        except ValueError:
            pass
        for relative in ("Weiktube/Weiktube.entitlements", "ShareExtension/ShareExtension.entitlements"):
            with (ROOT / relative).open("rb") as stream:
                entitlement = plistlib.load(stream)
            check(entitlement.get("com.apple.security.application-groups") == ["$(WEIKTUBE_APP_GROUP)"], f"App group entitlement mismatch: {relative}")
        with (ROOT / "ShareExtension/Info.plist").open("rb") as stream:
            share_info = plistlib.load(stream)
        check(share_info.get("WeiktubeAppGroup") == "$(WEIKTUBE_APP_GROUP)", "Extension group key must match app")
        check(share_info.get("NSExtension", {}).get("NSExtensionPointIdentifier") == "com.apple.share-services", "Extension point is not Share Services")

        scheme = ET.parse(ROOT / generator.SCHEME).getroot()
        tests = {item.attrib["BlueprintName"] for item in scheme.findall("./TestAction/Testables/TestableReference/BuildableReference")}
        check(tests == {"WeiktubeTests", "WeiktubeUITests"}, "Shared scheme must execute both test targets")
        for reference in scheme.findall(".//BuildableReference"):
            check(reference.attrib["BlueprintIdentifier"] in objects, "Scheme refers to a missing target")
        check(scheme.find("ArchiveAction").attrib["buildConfiguration"] == "Release", "Archive action must use Release")
        base = (ROOT / "Config/Base.xcconfig").read_text()
        check("IPHONEOS_DEPLOYMENT_TARGET = 17.0" in base, "iOS deployment target changed unexpectedly")
        check('#include? "Local.xcconfig"' in base, "Optional untracked local configuration is missing")
        check("CODE_SIGNING_ALLOWED[sdk=iphonesimulator*] = NO" in base, "Simulator signing must be disabled")
    except (OSError, ValueError, KeyError, IndexError, plistlib.InvalidFileException, ET.ParseError) as error:
        failures.append(str(error))

    if failures:
        print("Project structural validation failed:", *failures, sep="\n- ", file=sys.stderr)
        return 1
    print("Project structural validation passed: 4 targets, complete source membership, resource folder, scheme, OAuth preparation and app groups.")
    print("This checks project structure only; it does not compile Swift, sign a build, run a simulator or validate device behavior.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
