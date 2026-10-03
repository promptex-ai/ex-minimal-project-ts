#!/usr/bin/env bash
# Release stages of a train and the steps that move a train between them. Sourced by common.sh;
# do not execute.
#
# A train walks alpha → beta → rc → ga, forward only. Each stage has one environment:
#   alpha → dev, beta → beta, rc → staging, ga → production
# This repo deploys nothing; its environment is the package registry. A stage exists when the repo
# has a package unit that publishes (has_publishable_units): alpha, beta and rc all publish
# (publish.yml, dispatched by release-please.yml with the train's stage), npm under the stage's
# dist-tag. ga always exists: every train ends there. A stage with no environment is skipped, so a
# repo whose units stop publishing goes straight to ga.
#
#   STAGE_ENV_ROOT  where the package units are read from (default REPO_ROOT)

RELEASE_STAGES=(alpha beta rc ga)

stage_env() { # stage_env <stage> → environment name
  case "$1" in
    alpha) printf '%s\n' dev ;;
    beta) printf '%s\n' beta ;;
    rc) printf '%s\n' staging ;;
    ga) printf '%s\n' production ;;
    *) return 1 ;;
  esac
}

stage_index() { # stage_index <stage> → 0-based position in RELEASE_STAGES
  local i
  for i in "${!RELEASE_STAGES[@]}"; do
    [[ "${RELEASE_STAGES[$i]}" == "$1" ]] && { printf '%s\n' "$i"; return 0; }
  done
  return 1
}

is_stage() { stage_index "$1" >/dev/null; }

# unit_registry <dir> → npm | pypi | crates, from the file the unit directory carries; fails when none.
unit_registry() {
  if [[ -f "$1/package.json" ]]; then printf '%s\n' npm
  elif [[ -f "$1/pyproject.toml" ]]; then printf '%s\n' pypi
  elif [[ -f "$1/Cargo.toml" ]]; then printf '%s\n' crates
  else return 1; fi
}

# has_publishable_units <root> → whether the repo at <root> has a package unit that publishes: an
# entry of its release-please-config.json with a registry file, except a unit the registry would
# refuse or that opts out: a private npm package, or a crate with publish = false. The project at the
# repo root is not an entry of the config, so it never counts.
has_publishable_units() {
  local root="$1" cfg="$1/$CONFIG" p
  [[ -f "$cfg" ]] || return 1
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    case "$(unit_registry "$root/$p")" in
      npm) [[ "$(jq -r '.private // false' "$root/$p/package.json")" == true ]] || return 0 ;;
      pypi) return 0 ;;
      crates) grep -Eq '^publish[[:space:]]*=[[:space:]]*false' "$root/$p/Cargo.toml" || return 0 ;;
    esac
  done < <(jq -r '.packages // {} | keys[]' "$cfg")
  return 1
}

stage_has_env() { # stage_has_env <stage>
  local stage="$1" root="${STAGE_ENV_ROOT:-$REPO_ROOT}"
  [[ "$stage" == ga ]] && return 0
  stage_env "$stage" >/dev/null || return 1
  has_publishable_units "$root"
}

stages_available() { # one stage per line, in order
  local s
  for s in "${RELEASE_STAGES[@]}"; do stage_has_env "$s" && printf '%s\n' "$s"; done
  return 0
}

# stage_first_available <stage> → <stage> itself when it has an environment, otherwise the next stage
# that has one (ga at the latest)
stage_first_available() {
  local i
  i="$(stage_index "$1")" || return 1
  for (( ; i < ${#RELEASE_STAGES[@]}; i++ )); do
    stage_has_env "${RELEASE_STAGES[$i]}" && { printf '%s\n' "${RELEASE_STAGES[$i]}"; return 0; }
  done
  return 1
}

# stage_version <version> <stage> → the version a unit enters <stage> with, the same result as semver's
# inc(<version>, 'prerelease', <stage>, '1'): 1.2.0-alpha.3 → 1.2.0-beta.1, 1.2.0-beta.1 → 1.2.0-beta.2,
# 1.2.0 → 1.2.1-beta.1. Computed in bash so the release scripts need only git, jq and gh, not a Node
# install that provides the semver CLI.
stage_version() {
  local v="$1" id="$2" core pre n patch
  [[ "$v" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-([0-9A-Za-z.-]+))?$ ]] || return 1
  core="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}" pre="${BASH_REMATCH[5]}"
  if [[ -z "$pre" ]]; then
    patch=$(( BASH_REMATCH[3] + 1 ))
    printf '%s\n' "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${patch}-${id}.1"
  elif [[ "$pre" =~ ^${id}\.([0-9]+)$ ]]; then
    n=$(( BASH_REMATCH[1] + 1 ))
    printf '%s\n' "${core}-${id}.${n}"
  else
    printf '%s\n' "${core}-${id}.1"
  fi
}

# version_stage <version> → the stage a released unit version belongs to: ga for X.Y.Z, <stage> for
# X.Y.Z-<stage>.N with <stage> one of alpha, beta, rc. Any other shape fails, because publishing and
# npm derives its dist-tag from the stage and must not guess one.
version_stage() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)\.[0-9]+)?$ ]] || return 1
  printf '%s\n' "${BASH_REMATCH[2]:-ga}"
}

# prerelease-type the config carries in <stage>. release-please appends it verbatim when a unit with a
# stable version takes its first change (1.3.1 + feat → 1.4.0-alpha.1) and afterwards only bumps the
# trailing number, so "<stage>.1" makes every stage start at .1 without pinning a version.
stage_prerelease_type() { printf '%s\n' "$1.1"; }

# train_stage [<config file>] → the stage the train's config declares: the prerelease-type without its
# number while in prerelease mode, ga otherwise
train_stage() {
  local cfg="${1:-$CONFIG}" type
  if [[ "$(jq -r '.prerelease // false' "$cfg")" != true ]]; then printf '%s\n' ga; return 0; fi
  type="$(jq -r '."prerelease-type" // empty' "$cfg")"
  type="${type%%.*}"
  if ! is_stage "$type" || [[ "$type" == ga ]]; then
    die "$cfg 的 prerelease-type 是「${type}」，不是 ${RELEASE_STAGES[*]:0:3} 之一，無法判斷發布分支所在階段"
  fi
  printf '%s\n' "$type"
}

# Bring the local train up to its remote. Fetch even under --dry-run; fetching only updates local refs.
train_sync() { # train_sync <branch>
  local branch="$1"
  git fetch --quiet --tags origin || die "無法從 origin 抓取 tag 與 main，起點閘需要遠端最新的產品 tag"
  # 明確用遠端追蹤 ref：release-please 的工作分支名尾端同樣是 "$branch"，
  # 以短 refname pull 會同時命中兩條而報 "Cannot fast-forward to multiple branches"
  run git merge --ff-only "origin/$branch"
}

# Gates a train passes before it moves to <stage>, run after train_sync. The ci gate is called the
# GA gate when the train goes to ga, which is how the docs know it.
train_gates() { # train_gates <branch> <line> <stage>
  local branch="$1" line="$2" stage="$3" shipped st gate_ok gate_sha rest src_tip i gate act
  if [[ "$stage" == ga ]]; then gate="GA 閘" act="跑 GA"; else gate="ci 閘" act="推進到 $stage"; fi
  # Scripts gate: the train must run main's release tooling. A train rebuilt by hand from an old tag
  # carries that tag's scripts, which may predate a gate. cut-release.sh syncs scripts/ from main
  # when it cuts, so only a hand-made or long-lived train trips this.
  git diff --quiet origin/main -- scripts \
    || die "發布腳本落後 main：${branch} 的 scripts/ 與 origin/main 不同。先同步再${act}：git checkout origin/main -- scripts，commit 後推上 ${branch}"
  # Base gate: a line that already shipped takes patches only, and a patch must continue from the
  # line's latest product tag. cut-release.sh refuses any other base. Here it catches a train opened
  # by hand from main (merge-back is a squash, so the tag is never main's ancestor) or from an older
  # tag. It cannot reach a train that runs a finalize-release.sh from before this gate existed.
  shipped="$(git tag --list "v${line}.*" | grep -E "^v${line//./\\.}\.[0-9]+$" | sort -t. -k3,3n | tail -1 || true)"
  if [[ -n "$shipped" ]]; then
    git merge-base --is-ancestor "${shipped}^{commit}" HEAD \
      || die "起點閘未通過：${branch} 不含產品線 v${line} 最後一個產品 tag ${shipped}。修補發布要從它重建：刪掉這條分支，用 cut-release.sh --line ${line} --from ${shipped} 重切，修正再 cherry-pick 進去"
    info "✓ 起點含 ${shipped}"
  fi
  # ci gate: the train's latest ci run on the current tip must be green. The last push to the branch is
  # usually a Release PR merge, so that run is often still in progress when the stage moves — wait for
  # it rather than just look. A repo without .github/workflows/ci.yml has no run to wait for, so the
  # gate is skipped there instead of timing out.
  if [[ ! -f "$REPO_ROOT/.github/workflows/ci.yml" ]]; then
    info "⊘ 本倉庫沒有 .github/workflows/ci.yml，略過${gate}的 ci 核對"
  elif (( DRY_RUN == 0 )) && [[ "${CI_GATE:-1}" == 1 ]]; then
    log "${gate}：等待 $branch 最近一次 ci 執行完成"
    gate_ok=0 gate_sha=""
    for ((i=1; i<=${CI_GATE_TRIES:-40}; i++)); do
      st="$(gh run list --workflow ci.yml --branch "$branch" --limit 1 --json status,conclusion,databaseId,headSha \
            --jq '.[0] | "\(.status)/\(.conclusion // "")/\(.databaseId)/\(.headSha)"' 2>/dev/null || true)"
      [[ -z "$st" ]] && { warn "$branch 尚無 ci 執行紀錄，等待中"; sleep "${CI_GATE_SLEEP:-15}"; continue; }
      gate_sha="${st##*/}"; st="${st%/*}"
      case "$st" in
        completed/success/*) info "✓ ci run ${st##*/} 通過"; gate_ok=1; break ;;
        completed/*) rest="${st#completed/}"; die "${gate}未通過：ci run ${st##*/} 結論為 ${rest%%/*}（查 gh run view ${st##*/}）；修正後重跑，或以 CI_GATE=0 略過" ;;
        *) sleep "${CI_GATE_SLEEP:-15}" ;;
      esac
    done
    (( gate_ok )) || die "${gate}逾時：$branch 的 ci 仍未完成"
    # ci.yml 的 paths-ignore 讓純版號與中繼資料的 push 不觸發 ci，因此「最近一次 ci」不再
    # 等於「最近一次 push」。那在邏輯上正確（原始碼沒變，舊結論仍成立），但如果日後有東西
    # 誤入 ignore 清單，閘會無聲失效。改為核對那次 ci 確實涵蓋了最後一個觸及原始碼的 commit。
    src_tip="$(git log "origin/$branch" --format=%H -1 -- . \
      ':!**/.release-marker' ':!release-please-config.json' ':!.release-please-manifest.json' \
      ':!**/CHANGELOG.md' 2>/dev/null || true)"
    if [[ -n "$src_tip" && -n "$gate_sha" ]]; then
      if git merge-base --is-ancestor "$src_tip" "$gate_sha" 2>/dev/null; then
        info "✓ 該次 ci 涵蓋最後一個原始碼變更 ${src_tip:0:7}"
      else
        die "${gate}未涵蓋最後一個原始碼變更 ${src_tip:0:7}（ci 跑在 ${gate_sha:0:7}）：ci.yml 的 paths-ignore 可能誤含了會影響建置的路徑"
      fi
    fi
  fi
}

# One commit per unit carrying "Release-As: <version>", for every unit of the train that shipped a
# prerelease: <stage> ga strips the suffix (1.2.0-rc.2 → 1.2.0), a prerelease stage restarts at .1
# (1.2.0-alpha.3 → 1.2.0-beta.1). A unit still on a stable version has not released in this train and
# is left alone. Under DRY_RUN it only lists the moves.
train_release_as() { # train_release_as <branch> <stage>
  local branch="$1" stage="$2" u p cur next id
  local -a units=()
  while IFS= read -r u; do [[ -n "$u" ]] && units+=("$u"); done < <(config_units)
  for u in "${units[@]}"; do
    p="$(unit_path "$u")" || die "unit 不存在：$u"
    cur="$(manifest_version "$p")"
    [[ "$cur" == *-* ]] || { info "⊘ ${u}（${cur}）本次發布未發過 prerelease，略過"; continue; }
    if [[ "$stage" == ga ]]; then next="$(stable_version "$cur")"; else
      id="${cur#*-}"; id="${id%%.*}"
      if is_stage "$id" && (( $(stage_index "$id") >= $(stage_index "$stage") )); then
        die "${u} 的版號 ${cur} 已在 ${id}，不能再進入 ${stage}"
      fi
      next="$(stage_version "$cur" "$stage")"
    fi
    info "${u}：$cur → $next"
    (( DRY_RUN )) && continue
    release_as_commit "$branch" "$u" "$p" "$next"
  done
}

# release-please 依「commit 觸及哪些路徑」歸屬 Release-As，所以這個 commit 必須觸及本單元路徑；又不能
# 是空的，因為空 commit 會被歸屬到所有路徑（release-please src/manifest.ts 的 CommitSplit
# includeEmpty: true），一個單元的 Release-As 就會污染其他單元。標記檔為此存在，時間戳讓重跑時仍產生
# 真實 diff。它只活在發布分支上，merge-back 會先刪掉再算差異，不進 main；各單元的打包設定也排除它，
# 不進入發布產物（兩個套件 package.json 的 files 白名單不列入它）。
release_as_commit() { # release_as_commit <branch> <unit> <path> <version>
  local branch="$1" u="$2" p="$3" v="$4"
  {
    printf '%s\n' "$v"
    printf '%s\n' "#"
    printf '%s\n' "# 由發布腳本在首次發布、推進階段或 GA 時寫入，用途只有一個：讓帶 Release-As footer 的"
    printf '%s\n' "# commit 觸及本單元路徑且非空。發布結束前會被刪除，不會進入預設分支或發布產物。"
    printf '%s\n' "# 理由見 scripts/lib/release-stages.sh 的 release_as_commit 註解。"
    printf '%s\n' "# released from $branch at $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  } > "$p/.release-marker"
  git add "$p/.release-marker"
  git commit -q -m "chore($branch): $u $v" -m "Release-As: $v"
}
