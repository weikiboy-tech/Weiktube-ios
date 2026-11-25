#!/usr/bin/env python3
"""Create the app's derived Info.plist without registering an empty OAuth URL scheme."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import plistlib
import re
import sys


def configured_plist(template: dict, environment: dict[str, str]) -> dict:
    result = dict(template)
    client = environment.get("GOOGLE_OAUTH_CLIENT_ID", "").strip()
    redirect = environment.get("GOOGLE_OAUTH_REDIRECT_URI", "").strip()
    scheme = environment.get("GOOGLE_REVERSED_CLIENT_ID", "").strip()
    result["GoogleOAuthClientID"] = client
    result["GoogleOAuthRedirectURI"] = redirect
    result["CFBundleURLTypes"] = [dict(item) for item in template["CFBundleURLTypes"]]
    if any((client, redirect, scheme)):
        if not re.fullmatch(r"[A-Za-z0-9_-]+\.apps\.googleusercontent\.com", client):
            raise ValueError("GOOGLE_OAUTH_CLIENT_ID must be the real registered iOS OAuth client ID.")
        expected_scheme = ".".join(reversed(client.split(".")))
        if scheme != expected_scheme or redirect not in (scheme + ":/oauthredirect", scheme + ":/oauth2redirect"):
            raise ValueError("Configure all three Google OAuth settings with the same registered iOS client and redirect scheme.")
        result["CFBundleURLTypes"].append({
            "CFBundleURLName": "Google OAuth callback",
            "CFBundleTypeRole": "Editor",
            "CFBundleURLSchemes": [scheme],
        })
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    arguments = parser.parse_args()
    try:
        with arguments.input.open("rb") as stream:
            template = plistlib.load(stream)
        output = plistlib.dumps(configured_plist(template, dict(os.environ)), sort_keys=False)
        arguments.output.parent.mkdir(parents=True, exist_ok=True)
        # Xcode tracks this declared output, then expands its ordinary build setting placeholders.
        arguments.output.write_bytes(output)
    except (OSError, ValueError, KeyError, plistlib.InvalidFileException) as error:
        print(f"error: Cannot prepare Weiktube Info.plist: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
