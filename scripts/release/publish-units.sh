#!/usr/bin/env bash
# Publish released package units to npm, at every stage of a train. publish.yml calls it;
# release-please.yml dispatches publish.yml with the released paths and the train's stage.
#
# The registry follows from the file the unit carries (unit_registry). Every unit of this repo is an
# npm package (package.json), and publish.yml installs only Node, so a unit with any other file stops
# the run. The dist-tag is the stage (alpha | beta | rc), latest at ga: latest must only ever point at
# a GA. Each unit installs its own devDependencies and packs itself (prepack runs tsc), then the npm
# CLI publishes the tarball: npm is the client that does the Trusted Publishing token exchange
# (npm 11.5.1 or later), and --provenance makes provenance a hard requirement, so the upload fails
# instead of silently shipping without it should the repository stop being public.
#
# Every unit's version must belong to <stage> (version_stage in scripts/lib/release-stages.sh), so a
# dispatch with the wrong stage stops instead of publishing a prerelease under latest. A path must be
# an entry of the manifest, which lists exactly this repo's two packages, so nothing else is
# published. A version that is already on the registry is skipped, so a re-run is safe.
#
# usage: publish-units.sh <alpha|beta|rc|ga> <path>...
#   PUBLISH_OUT  where tarballs are packed (default tmp/publish)
#   DRY_RUN=1    pack, then run npm publish --dry-run: nothing is uploaded
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
cd "$REPO_ROOT"
usage() { die "usage: publish-units.sh <alpha|beta|rc|ga> <path>..."; }

npm_dist_tag() { if [[ "$1" == ga ]]; then printf '%s\n' latest; else printf '%s\n' "$1"; fi; }

summary() { [[ -z "${GITHUB_STEP_SUMMARY:-}" ]] || printf '%s\n' "- $*" >> "$GITHUB_STEP_SUMMARY"; }

# The unit's own file must carry the manifest version: release-please writes both in one commit, and
# a broken updater would otherwise publish a version the manifest never released.
check_file_version() { # check_file_version <path> <file> <version in file> <manifest version>
  [[ "$3" == "$4" ]] || die "$1：manifest 是 $4，但 $2 是 ${3:-（空）}；release-please 沒有更新到這個檔"
}

publish_npm() { # publish_npm <path> <version> <stage>
  local p="$1" ver="$2" name tag tgz
  name="$(jq -r .name "$p/package.json")"
  check_file_version "$p" "$p/package.json" "$(jq -r .version "$p/package.json")" "$ver"
  tag="$(npm_dist_tag "$3")"
  if npm view "$name@$ver" version 2>/dev/null | grep -qx "$ver"; then
    info "npm：$name@$ver 已發布，略過"
    summary "npm \`$name@$ver\` 已在註冊中心，略過"
    return 0
  fi
  log "npm：${name}@${ver} → dist-tag ${tag}"
  # No lockfile is tracked, so the install resolves the declared ranges and writes no lockfile back.
  npm install --prefix "$p" --no-package-lock --ignore-scripts --no-audit --no-fund
  mkdir -p "$PUBLISH_OUT/npm"
  tgz="$PUBLISH_OUT/npm/$(cd "$p" && npm pack --pack-destination "$PUBLISH_OUT/npm" --json | jq -r '.[0].filename')"
  if (( DRY_RUN )); then
    npm publish "$tgz" --dry-run --access public --tag "$tag"
    summary "npm \`$name@$ver\` → dist-tag \`$tag\`（dry-run）"
  else
    npm publish "$tgz" --access public --tag "$tag" --provenance
    summary "npm \`$name@$ver\` → dist-tag \`$tag\`"
  fi
}

# publish.yml runs at the tag release-please.yml dispatched it with: the tag of the first path, which is
# <component>/v<version> (include-component-in-tag, tag-separator "/"). Any other ref, such as a branch
# or an older tag, would publish a version the ref does not carry, so stop. A local run is not checked.
check_dispatch_ref() { # check_dispatch_ref <first path>
  [[ "${GITHUB_ACTIONS:-}" == true ]] || return 0
  local p="${1%/}" comp ver want
  comp="$(jq -r --arg p "$p" '.packages[$p].component // empty' "$CONFIG")"
  ver="$(manifest_version "$p")"
  [[ -n "$comp" && -n "$ver" ]] || die "$p 在 ${CONFIG} 沒有 component，或在 ${MANIFEST} 沒有版號，無法核對發布的 tag"
  want="refs/tags/$comp/v$ver"
  [[ "${GITHUB_REF:-}" == "$want" ]] || die "發布必須從 tag ${want#refs/tags/} 執行，但 GITHUB_REF 是「${GITHUB_REF:-（空）}」"
}

[[ $# -ge 2 ]] || usage
stage="$1"; shift
check_dispatch_ref "$1"
is_stage "$stage" || die "階段「${stage}」不是 ${RELEASE_STAGES[*]} 之一"
PUBLISH_OUT="${PUBLISH_OUT:-$REPO_ROOT/tmp/publish}"
rm -rf "$PUBLISH_OUT/npm"
for p in "$@"; do
  p="${p%/}"
  ver="$(manifest_version "$p")"
  [[ -n "$ver" ]] || die "$p 不在 ${MANIFEST}，不是本倉庫發布的套件"
  vs="$(version_stage "$ver")" || die "$p 的版號 $ver 不是 X.Y.Z 或 X.Y.Z-<alpha|beta|rc>.N，無法決定發布階段"
  [[ "$vs" == "$stage" ]] || die "$p 的版號 $ver 屬於 ${vs}，但這次發布的階段是 ${stage}"
  reg="$(unit_registry "$p")" || die "$p 沒有 package.json，不知道要發布到哪個註冊中心"
  [[ "$reg" == npm ]] || die "$p 的單元檔對應 ${reg}，本倉庫的 publish.yml 只發布到 npm"
  publish_npm "$p" "$ver" "$stage"
done
