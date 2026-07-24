#!/bin/zsh

set -euo pipefail

version=${1:-}
dmg_path=${2:-}
output_path=${3:-}

if [[ -z $version || ! -f $dmg_path || -z $output_path ]]; then
    print -u2 "Usage: scripts/render-cask.sh <version> <dmg-path> <output-path>"
    exit 64
fi

sha256=$(shasum -a 256 "$dmg_path" | awk '{print $1}')
mkdir -p "${output_path:h}"

sed \
    -e "s/__VERSION__/$version/g" \
    -e "s/__SHA256__/$sha256/g" \
    "${0:A:h:h}/packaging/ssd-watcher.rb.template" > "$output_path"
