#!/usr/bin/env python3
"""Select an installed, available iOS 17+ iPhone simulator without assuming a device name."""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys


def main() -> int:
    result = subprocess.run(["xcrun", "simctl", "list", "devices", "available", "--json"], check=True, capture_output=True, text=True)
    inventory = json.loads(result.stdout)
    candidates = []
    for runtime, devices in inventory.get("devices", {}).items():
        match = re.search(r"\.iOS-(\d+)-(\d+)(?:-(\d+))?$", runtime)
        if not match:
            continue
        version = tuple(int(part or 0) for part in match.groups())
        if version[0] < 17:
            continue
        for device in devices:
            if device.get("isAvailable") and device.get("name", "").startswith("iPhone"):
                candidates.append((version, device.get("state") == "Booted", device["name"], device["udid"]))
    if not candidates:
        print("No available iPhone simulator with iOS 17 or later is installed. Install an iOS runtime in Xcode Settings > Components.", file=sys.stderr)
        return 1
    version, _, name, identifier = sorted(candidates)[-1]
    destination = f"platform=iOS Simulator,id={identifier}"
    print(f"Selected {name}, iOS {'.'.join(map(str, version))}: {identifier}")
    output_file = os.environ.get("GITHUB_OUTPUT")
    if output_file:
        with open(output_file, "a", encoding="utf-8") as stream:
            stream.write(f"simulator_id={identifier}\ndestination={destination}\n")
    else:
        print(destination)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
