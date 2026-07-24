#!/bin/zsh

set -euo pipefail

repo_root=${0:A:h:h}
version=${1:-}
version_pattern='^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$'

if [[ ! $version =~ $version_pattern ]]; then
    print -u2 "Usage: scripts/release.sh <version>"
    exit 64
fi

team_id=${DEVELOPMENT_TEAM:-KF4GF4J4K9}
signing_identity=${DEVELOPER_ID_APPLICATION:-Developer ID Application: Takayuki Hoffman (KF4GF4J4K9)}
notary_profile=${NOTARYTOOL_PROFILE:-SSDWatcherNotary}
build_number=${BUILD_NUMBER:-${version%%[-+]*}}
derived_data=${SSD_WATCHER_DERIVED_DATA:-/tmp/SSDWatcherReleaseDerivedData}
archive_path="$derived_data/SSDWatcher.xcarchive"
export_path="$derived_data/Export"
dist_path="$repo_root/dist"
temporary_path=$(mktemp -d "${TMPDIR:-/tmp}/ssd-watcher-release.XXXXXX")

cleanup() {
    rm -rf "$temporary_path"
}
trap cleanup EXIT

cd "$repo_root"
xcodegen generate

xcodebuild archive \
    -project SSDWatcher.xcodeproj \
    -scheme SSDWatcher \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$derived_data" \
    -archivePath "$archive_path" \
    MARKETING_VERSION="$version" \
    CURRENT_PROJECT_VERSION="$build_number" \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="$team_id" \
    CODE_SIGN_IDENTITY="$signing_identity" \
    OTHER_CODE_SIGN_FLAGS="--timestamp"

xcodebuild -exportArchive \
    -archivePath "$archive_path" \
    -exportPath "$export_path" \
    -exportOptionsPlist "$repo_root/Config/ExportOptions.plist"

app_path="$export_path/SSDWatcher.app"
if [[ ! -d $app_path ]]; then
    print -u2 "Export did not produce SSDWatcher.app"
    exit 1
fi

codesign --verify --deep --strict --verbose=2 "$app_path"

mkdir -p "$dist_path"
find "$dist_path" -mindepth 1 -maxdepth 1 -exec rm -rf {} +

notarization_zip="$temporary_path/SSD-Watcher-notarization.zip"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$notarization_zip"
xcrun notarytool submit "$notarization_zip" \
    --keychain-profile "$notary_profile" \
    --wait
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"

zip_name="SSD-Watcher-$version.zip"
zip_path="$dist_path/$zip_name"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"

dmg_source="$temporary_path/dmg"
mkdir -p "$dmg_source"
ditto "$app_path" "$dmg_source/SSDWatcher.app"
ln -s /Applications "$dmg_source/Applications"

dmg_name="SSD-Watcher-$version.dmg"
dmg_path="$dist_path/$dmg_name"
hdiutil create \
    -volname "SSD Watcher" \
    -srcfolder "$dmg_source" \
    -format UDZO \
    -ov \
    "$dmg_path"
xcrun notarytool submit "$dmg_path" \
    --keychain-profile "$notary_profile" \
    --wait
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"

sparkle_tools="$derived_data/SourcePackages/artifacts/sparkle/Sparkle/bin"
update_source="$temporary_path/updates"
mkdir -p "$update_source"
cp "$zip_path" "$update_source/$zip_name"

release_notes="$repo_root/release-notes/$version.md"
if [[ -f $release_notes ]]; then
    cp "$release_notes" "$update_source/SSD-Watcher-$version.md"
fi

appcast_arguments=(
    --download-url-prefix "https://github.com/Takhoffman/ssd-watcher/releases/download/v$version/"
    --link "https://github.com/Takhoffman/ssd-watcher"
    --embed-release-notes
    -o appcast.xml
)
if [[ -n ${SPARKLE_PRIVATE_KEY_FILE:-} ]]; then
    appcast_arguments+=(--ed-key-file "$SPARKLE_PRIVATE_KEY_FILE")
fi

"$sparkle_tools/generate_appcast" "${appcast_arguments[@]}" "$update_source"
cp "$update_source/appcast.xml" "$dist_path/appcast.xml"

mkdir -p "$dist_path/Casks"
"$repo_root/scripts/render-cask.sh" "$version" "$dmg_path" "$dist_path/Casks/ssd-watcher.rb"

(
    cd "$dist_path"
    shasum -a 256 "$dmg_name" "$zip_name" appcast.xml > SHA256SUMS
)

spctl --assess --type execute --verbose=2 "$app_path"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg_path"

print "Release artifacts are ready in $dist_path"
