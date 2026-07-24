#!/bin/zsh

set -euo pipefail

repo_root=${0:A:h:h}
version=${1:-}
version_pattern='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z][0-9A-Za-z.-]*)?$'

fail() {
    print -u2 "Release preflight failed: $1"
    exit 1
}

if [[ ! $version =~ $version_pattern ]]; then
    print -u2 "Usage: scripts/check-release.sh <version>"
    exit 64
fi

cd "$repo_root"

project_version=$(
    awk '/^[[:space:]]*MARKETING_VERSION:/ { print $2; exit }' project.yml
)
[[ $project_version == "$version" ]] \
    || fail "project.yml is version $project_version, expected $version."

release_notes="release-notes/$version.md"
[[ -s $release_notes ]] || fail "$release_notes is missing or empty."
grep -Fq "# SSD Watcher $version" "$release_notes" \
    || fail "$release_notes does not have the expected title."

if [[ ${GITHUB_REF_TYPE:-} == tag && ${GITHUB_REF_NAME:-} != "v$version" ]]; then
    fail "tag ${GITHUB_REF_NAME:-unknown} does not match v$version."
fi

[[ -s SSDWatcher/Resources/ThirdPartyLicenses/Sparkle.txt ]] \
    || fail "the bundled Sparkle license is missing."

if [[ ${ALLOW_DIRTY_RELEASE:-0} != 1 ]] \
    && [[ -n $(git status --porcelain --untracked-files=normal) ]]; then
    fail "the Git worktree is not clean."
fi

scripts/validate.sh
print "Release $version passed repository preflight."
