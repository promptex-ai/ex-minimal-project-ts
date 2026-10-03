#!/usr/bin/env bash
# Shared helpers for release / scenario scripts. Source it; do not execute.
#   DRY_RUN=1     print every mutating command instead of running it
#   ASSUME_YES=1  skip the interactive confirmation for external writes (CI / scenario --yes)
#   TASK_DIR      where external-ops.log lives (default tmp/<today>-git-flow-sim)
set -euo pipefail

# mapfile and associative arrays are bash 4; macOS still ships 3.2 as /bin/bash, so say so plainly
# rather than failing later with a confusing parse error.
if (( BASH_VERSINFO[0] < 4 )); then
  printf '%s\n' "✗ 需要 bash 4 以上（目前 ${BASH_VERSION}）；macOS 內建的 /bin/bash 是 3.2，請以 brew install bash 安裝後再跑" >&2
  exit 1
fi

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel)}"
DRY_RUN="${DRY_RUN:-0}"
ASSUME_YES="${ASSUME_YES:-0}"
TASK_DIR="${TASK_DIR:-$REPO_ROOT/tmp/$(date +%Y-%m-%d)-git-flow-sim}"
AUDIT_LOG="$TASK_DIR/external-ops.log"
CONFIG="release-please-config.json"
MANIFEST=".release-please-manifest.json"
# Folders that hold package units, one unit per subfolder: plugins/<name> and adapters/<name>.
UNIT_DIRS=(plugins adapters)
# Both units share one version through linked-versions, so the product version is the group version,
# read from this unit's manifest entry.
PRODUCT_UNIT="plugins/ex-minimal-plugin-ts"
# Where publish.yml ships the units at <stage>, for the next-step hints.
publish_target() { if [[ "$1" == ga ]]; then printf '%s\n' "npm（dist-tag latest）"; else printf '%s\n' "npm（dist-tag $1）"; fi; }

log()  { printf '%s\n' "→ $*"; }
info() { printf '%s\n' "  $*"; }
warn() { printf '%s\n' "! $*" >&2; }
die()  { printf '%s\n' "✗ $*" >&2; exit 1; }

# bash has no array-membership operator, and open-coding the loop at each call site is where
# unquoted-expansion bugs creep in, so every membership test goes through this one helper.
in_array() { # in_array <needle> <haystack>...
  local needle="$1"; shift
  local item
  for item in "$@"; do [[ "$item" == "$needle" ]] && return 0; done
  return 1
}

# run a local (reversible) command; printed only under DRY_RUN
run() {
  if (( DRY_RUN )); then printf '%s\n' "  [dry-run] $*"; else printf '%s\n' "  \$ $*"; "$@"; fi
}

# external write gate (execute-external per external-operation-guard): returns 0 to proceed
confirm_external() {
  local target="$1" op="$2"
  printf '%s\n' "外部寫入（execute-external）：$op → $target"
  if (( DRY_RUN )); then printf '%s\n' "  [dry-run] 不執行"; return 1; fi
  if (( ASSUME_YES )); then printf '%s\n' "  ASSUME_YES=1，視為已確認"; return 0; fi
  local reply
  read -r -n1 -p "  確認執行？[y/N] " reply || true
  printf '\n'
  [[ "$reply" == "y" ]]
}

# audit <target> <op> <result> — one line, four pipe-delimited fields.
# The operation text is flattened and truncated: PR bodies carry newlines and "|" (markdown tables),
# which would otherwise break the one-record-per-line format and make the log unparsable.
audit() {
  local op="${2//$'\n'/ ⏎ }"
  op="${op//|/／}"
  (( ${#op} > 300 )) && op="${op:0:300}…"
  mkdir -p "$TASK_DIR"
  printf '%s\n' "$(date '+%Y-%m-%d %H:%M') | $1 | $op | $3" >> "$AUDIT_LOG"
}

# external command wrapped with confirmation + audit: external <target> <cmd...>
external() {
  local target="$1"; shift
  if confirm_external "$target" "$*"; then
    if "$@"; then audit "$target" "$*" success; else audit "$target" "$*" failure; return 1; fi
  else
    log "跳過：$*"
    return 0
  fi
}

# Same gate as external(), but retries the command a few times. GitHub rejects a merge with
# "Base branch was modified" when the base moved between the PR being opened and merged, which
# happens routinely here: a staging deploy writes the ops declaration back to main while a feature
# PR is in flight. The merge itself is safe to repeat, so retry rather than abort the run.
external_retry() { # external_retry <target> <cmd>...
  local target="$1"; shift
  local i
  if ! confirm_external "$target" "$*"; then log "跳過：$*"; return 0; fi
  for i in 1 2 3 4 5; do
    if "$@"; then audit "$target" "$*" success; return 0; fi
    (( i < 5 )) && { warn "第 $i 次失敗，5 秒後重試（基底分支可能剛被回寫）"; sleep 5; }
  done
  audit "$target" "$*" failure
  return 1
}

remote_target() { git remote get-url origin 2>/dev/null | sed -E 's#(git@|https://)([^/:]+)[:/]#\2/#; s#\.git$##; s#^[^@]+@##'; }

require_clean_tree() {
  [[ -z "$(git status --porcelain)" ]] && return 0
  if (( DRY_RUN )); then warn "工作區不乾淨（dry-run 下僅警告）"; return 0; fi
  die "工作區不乾淨，先 commit 或 stash"
}

current_branch() { git branch --show-current; }

release_branches() { git branch -r --list 'origin/release/*' | sed 's#.*origin/##'; }

unit_path() { # unit_path ex-minimal-plugin-ts -> plugins/ex-minimal-plugin-ts（單元目錄見 UNIT_DIRS）
  local u="$1" d
  # An empty name or one with a slash would resolve to the unit folder itself or outside it.
  [[ -n "$u" && "$u" != */* ]] || return 1
  for d in "${UNIT_DIRS[@]}"; do
    [[ -d "$d/$u" ]] && { printf '%s\n' "$d/$u"; return 0; }
  done
  return 1
}

# whether the unit has shipped before: release-please only applies its versioning strategy on top of a
# previous release; without one it takes initial-version verbatim (1.0.0 when unset)
unit_released() { [[ -n "$(git tag --list "$1/v*" | head -1)" ]]; }

manifest_version() { jq -r --arg p "$1" '.[$p] // empty' "$MANIFEST"; }

# strip a prerelease suffix: 1.2.0-rc.3 → 1.2.0
stable_version() { printf '%s\n' "${1%%-*}"; }

# units listed in the config on <ref> (default: working tree)
config_units() {
  if [[ -n "${1:-}" ]]; then git show "$1:$CONFIG" | jq -r '.packages | keys[] | split("/")[1]'
  else jq -r '.packages | keys[] | split("/")[1]' "$CONFIG"; fi
}

# linked-versions binds a group of components to a single version, so a train shipping any member
# must carry the whole group: the plugin cannot bump components that are absent from the scoped
# config. Returns every component of every group containing one of the given units.
linked_group_members() { # linked_group_members <unit>... → component names (may be empty)
  local u
  for u in "$@"; do
    jq -r --arg u "$u" '
      (.plugins // [])[]
      | select(.type == "linked-versions")
      | select((.components // []) | index($u))
      | .components[]
    ' "$CONFIG" 2>/dev/null
  done | sort -u
  return 0
}

# Units this train actually shipped: the manifest entries that differ from main's. Derived rather
# than read from the config, because merge-back restores the config from main and would otherwise
# lose the train scope, making the phase impossible to re-run.
train_units_by_manifest() {
  jq -s -r '.[0] as $main | .[1] | to_entries[] | select(.value != $main[.key]) | .key | split("/")[1]' \
    <(git show origin/main:"$MANIFEST") "$MANIFEST"
}

# release stages (alpha → beta → rc → ga) and the steps that move a train between them
source "$(dirname "${BASH_SOURCE[0]}")/release-stages.sh"
