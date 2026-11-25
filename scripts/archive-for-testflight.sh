#!/bin/bash
# Produce a locally signed Release archive using the user's Xcode account and profiles.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -f Config/Local.xcconfig ]]; then
    echo "Config/Local.xcconfig mit Apple-Team, Bundle-ID und App Group anlegen (siehe INSTALLATION.md)." >&2
    exit 1
fi
archive="build/Weiktube-$(date +%Y%m%d-%H%M%S).xcarchive"
xcodebuild archive -project Weiktube.xcodeproj -scheme Weiktube -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$archive" -allowProvisioningUpdates
app="$archive/Products/Applications/Weiktube.app"
for bundle in "$app/PlugIns/ShareExtension.appex" "$app"; do
    codesign --verify --strict "$bundle"
    test -f "$bundle/embedded.mobileprovision"
done
echo "Signiertes Archiv: $archive"
echo "Im Xcode Organizer über Distribute App an App Store Connect übermitteln."
open -a Xcode "$archive"
