#!/bin/zsh

set -euo pipefail

repo_root=${0:A:h:h}
temporary_path=$(mktemp -d "${TMPDIR:-/tmp}/ssd-watcher-validate.XXXXXX")

cleanup() {
    rm -rf "$temporary_path"
}
trap cleanup EXIT

cd "$repo_root"

zsh -n scripts/*.sh
plutil -lint \
    Config/ExportOptions.plist \
    SSDWatcher/Resources/Info.plist
ruby -rjson -e \
    'JSON.parse(File.read(ARGV.fetch(0)))' \
    SSDWatcher.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
ruby -c packaging/ssd-watcher.rb.template >/dev/null

cp SSDWatcher.xcodeproj/project.pbxproj "$temporary_path/project.pbxproj"
cp SSDWatcher.xcodeproj/xcshareddata/xcschemes/SSDWatcher.xcscheme \
    "$temporary_path/SSDWatcher.xcscheme"

xcodegen generate

if ! cmp -s "$temporary_path/project.pbxproj" SSDWatcher.xcodeproj/project.pbxproj \
    || ! cmp -s \
        "$temporary_path/SSDWatcher.xcscheme" \
        SSDWatcher.xcodeproj/xcshareddata/xcschemes/SSDWatcher.xcscheme; then
    print -u2 "Generated Xcode project was stale. Review and commit the regenerated files."
    exit 1
fi

if git grep -I -n -E \
    -e '-----BEGIN (EC |OPENSSH |RSA )?PRIVATE KEY-----' \
    -- ':!scripts/validate.sh'; then
    print -u2 "A private key marker is present in a tracked file."
    exit 1
fi

print "Repository validation passed."
