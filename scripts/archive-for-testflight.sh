#!/bin/bash
# Produce a locally signed Release archive using the user's Xcode account and profiles.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -f Config/Local.xcconfig ]]; then
    echo "Config/Local.xcconfig mit Apple-Team, Bundle-ID und App Group anlegen (siehe INSTALLATION.md)." >&2
    exit 1
fi
mode="${1:-organizer}"
case "$mode" in
    organizer|--friends) ;;
    *) echo "Aufruf: bash scripts/archive-for-testflight.sh [--friends]" >&2; exit 2 ;;
esac
archive="build/Weiktube-$(date +%Y%m%d-%H%M%S).xcarchive"
xcodebuild archive -project Weiktube.xcodeproj -scheme Weiktube -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$archive" -allowProvisioningUpdates
app="$archive/Products/Applications/Weiktube.app"
for bundle in "$app/PlugIns/ShareExtension.appex" "$app"; do
    codesign --verify --strict "$bundle"
    test -f "$bundle/embedded.mobileprovision"
done
echo "Signiertes Archiv: $archive"
if [[ "$mode" == "--friends" ]]; then
    export_dir="${archive%.xcarchive}-private"
    options="${archive%.xcarchive}-export.plist"
    /usr/bin/plutil -create xml1 "$options"
    /usr/bin/plutil -insert method -string release-testing "$options"
    /usr/bin/plutil -insert destination -string export "$options"
    /usr/bin/plutil -insert signingStyle -string automatic "$options"
    xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$options" \
        -exportPath "$export_dir" -allowProvisioningUpdates
    test -s "$export_dir/Weiktube.ipa"
    echo "Private IPA für registrierte Geräte: $export_dir/Weiktube.ipa"
    exit 0
fi
echo "Im Xcode Organizer über Distribute App an App Store Connect übermitteln."
open -a Xcode "$archive"
