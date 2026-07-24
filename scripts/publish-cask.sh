#!/bin/zsh

set -euo pipefail

repo_root=${0:A:h:h}
cask_path=${1:-}
tap_name=${HOMEBREW_TAP_NAME:-Takhoffman/tap}
tap_git_url=${HOMEBREW_TAP_GIT_URL:-}

if [[ -z $cask_path || ! -f $cask_path ]]; then
    print -u2 "Usage: scripts/publish-cask.sh <cask-path>"
    exit 64
fi

HOMEBREW_NO_AUTO_UPDATE=1 brew tap "$tap_name"
tap_path=$(brew --repository "$tap_name")
cask_destination="$tap_path/Casks/ssd-watcher.rb"
mkdir -p "${cask_destination:h}"
cp "$cask_path" "$cask_destination"

brew style --cask "$tap_name/ssd-watcher"

if [[ -z $(git -C "$tap_path" status --porcelain) ]]; then
    print "Homebrew Cask is already current."
    exit 0
fi

version=$(
    awk '/^[[:space:]]*version / { gsub(/"/, "", $2); print $2; exit }' \
        "$cask_path"
)
git -C "$tap_path" config user.name "github-actions[bot]"
git -C "$tap_path" config \
    user.email "41898282+github-actions[bot]@users.noreply.github.com"
git -C "$tap_path" add Casks/ssd-watcher.rb
git -C "$tap_path" commit -m "Update SSD Watcher to $version"
if [[ -n $tap_git_url ]]; then
    git -C "$tap_path" remote set-url origin "$tap_git_url"
fi
git -C "$tap_path" push origin HEAD:main

print "Published SSD Watcher $version to $tap_name."
