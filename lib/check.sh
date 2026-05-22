#!/usr/bin/env bash
# Source-of-truth shell template for nixpkgs-tracker.
# Read by lib/mk-check.nix and spliced into a writeShellApplication via
# builtins.replaceStrings. Template variables:
#   @ENTRIES_JSON@      — JSON array of {url, description, message, targetChannel}
#   @TIMEOUT_SECONDS@   — per-request curl timeout
#   @FAIL_OPEN@         — "1" to swallow network errors, "0" to print them
set -uo pipefail

ENTRIES_JSON='@ENTRIES_JSON@'
TIMEOUT='@TIMEOUT_SECONDS@'
FAIL_OPEN='@FAIL_OPEN@'

UA="nixpkgs-tracker/1 (+https://github.com/devinbhatt/nixpkgs-tracker)"
API="https://api.github.com"
DEFAULT_PR_ACTION="Run 'nix flake update' and remove the overlay."
DEFAULT_ISSUE_ACTION="Verify the fix and remove the overlay."
DEFAULT_UPSTREAM_ACTION="Bump the package and remove the overlay."

warn() { printf '[nixpkgs-tracker] %s\n' "$*" >&2; }

diag() {
  if [[ $FAIL_OPEN != "1" ]]; then
    warn "$*"
  fi
}

# gh_get <path>  — prints body on success, returns non-zero on HTTP error.
gh_get() {
  local path="$1"
  local resp http
  resp=$(curl -fsSL \
    --max-time "$TIMEOUT" \
    -H "Accept: application/vnd.github+json" \
    -H "User-Agent: $UA" \
    -w '\n%{http_code}' \
    "$API$path" 2>/dev/null) || return 1
  http=${resp##*$'\n'}
  if [[ $http != 2* ]]; then
    return 1
  fi
  printf '%s' "${resp%$'\n'*}"
}

# has_stale_label <pr-json>  — true if any label name contains "stale".
has_stale_label() {
  local body="$1" hit
  hit=$(jq -r '
		[ .labels[]?.name // empty
		  | select(ascii_downcase | test("stale"))
		] | length
	' <<<"$body")
  [[ ${hit:-0} -gt 0 ]]
}

# parse_url <url>  — sets OWNER REPO KIND NUM (KIND ∈ {pull,issue}).
# Accepts:
#   https://github.com/<owner>/<repo>/{pull,pulls,issues}/<n>
#   http://github.com/<owner>/<repo>/{pull,pulls,issues}/<n>
#   github:<owner>/<repo>/{pull,pulls,issues}/<n>
parse_url() {
  local url="$1" rest
  rest=${url#https://github.com/}
  rest=${rest#http://github.com/}
  rest=${rest#github:}
  OWNER=${rest%%/*}
  rest=${rest#*/}
  REPO=${rest%%/*}
  rest=${rest#*/}
  case $rest in
  pull/*) KIND=pull ;;
  pulls/*) KIND=pull ;;
  issues/*) KIND=issue ;;
  *) return 1 ;;
  esac
  rest=${rest#*/}
  NUM=${rest%%[/#?]*}
  [[ $NUM =~ ^[0-9]+$ ]]
}

# check_nixpkgs_pr <num> <description> <message> <target_channel>
check_nixpkgs_pr() {
  local num=$1 desc=$2 msg=$3 channel=$4 body state merged sha cmp cmp_status action
  body=$(gh_get "/repos/NixOS/nixpkgs/pulls/$num") || {
    diag "$desc: failed to query PR #$num"
    return 0
  }
  state=$(jq -r '.state' <<<"$body")
  merged=$(jq -r '.merged' <<<"$body")
  sha=$(jq -r '.merge_commit_sha // ""' <<<"$body")

  if [[ $state == "open" ]]; then
    if has_stale_label "$body"; then
      warn "$desc: PR #$num is marked stale — it may be abandoned; consider an alternative."
    fi
    return 0
  fi
  if [[ $merged != "true" ]]; then
    warn "$desc: PR #$num was closed without merging — investigate."
    return 0
  fi
  if [[ -z $sha ]]; then
    diag "$desc: PR #$num merged but no merge_commit_sha — skipping propagation check."
    return 0
  fi
  cmp=$(gh_get "/repos/NixOS/nixpkgs/compare/$channel...$sha") || {
    diag "$desc: failed to compare $channel...$sha"
    return 0
  }
  cmp_status=$(jq -r '.status' <<<"$cmp")
  # "behind" / "identical" → merge commit is reachable from channel tip.
  if [[ $cmp_status == "behind" || $cmp_status == "identical" ]]; then
    action=${msg:-$DEFAULT_PR_ACTION}
    warn "$desc: PR #$num has reached $channel. $action"
  fi
}

# check_nixpkgs_issue <num> <description> <message>
check_nixpkgs_issue() {
  local num=$1 desc=$2 msg=$3 body state action timeline pr
  body=$(gh_get "/repos/NixOS/nixpkgs/issues/$num") || {
    diag "$desc: failed to query issue #$num"
    return 0
  }
  state=$(jq -r '.state' <<<"$body")
  if [[ $state == "closed" ]]; then
    action=${msg:-$DEFAULT_ISSUE_ACTION}
    warn "$desc: issue #$num is closed. $action"
    return 0
  fi
  # Open: look for cross-referenced PRs.
  timeline=$(gh_get "/repos/NixOS/nixpkgs/issues/$num/timeline?per_page=100") || return 0
  local linked=()
  mapfile -t linked < <(jq -r '
		[ .[]
		  | select(.event == "cross-referenced")
		  | .source.issue
		  | select(.pull_request != null)
		  | .number
		] | unique | .[]?
	' <<<"$timeline")
  for pr in "${linked[@]}"; do
    [[ -n $pr ]] || continue
    warn "$desc: issue #$num now has linked PR #$pr — consider tracking that instead."
  done
}

# check_external <owner> <repo> <kind> <num> <description> <message>
check_external() {
  local owner=$1 repo=$2 kind=$3 num=$4 desc=$5 msg=$6 path body state merged action label
  if [[ $kind == "pull" ]]; then
    path="/repos/$owner/$repo/pulls/$num"
    label="PR"
  else
    path="/repos/$owner/$repo/issues/$num"
    label="issue"
  fi
  body=$(gh_get "$path") || {
    diag "$desc: failed to query $owner/$repo $label #$num"
    return 0
  }
  state=$(jq -r '.state' <<<"$body")
  merged=$(jq -r '.merged // false' <<<"$body")
  if [[ $state == "open" ]]; then
    if [[ $kind == "pull" ]]; then
      if has_stale_label "$body"; then
        warn "$desc: upstream $owner/$repo PR #$num is marked stale — it may be abandoned; consider an alternative."
      fi
    else
      local timeline linked=() pr
      timeline=$(gh_get "/repos/$owner/$repo/issues/$num/timeline?per_page=100") || return 0
      mapfile -t linked < <(jq -r '
			[ .[]
			  | select(.event == "cross-referenced")
			  | .source.issue
			  | select(.pull_request != null)
			  | .number
			] | unique | .[]?
		' <<<"$timeline")
      for pr in "${linked[@]}"; do
        [[ -n $pr ]] || continue
        warn "$desc: upstream $owner/$repo issue #$num now has linked PR #$pr — consider tracking that instead."
      done
    fi
    return 0
  fi
  if [[ $kind == "pull" && $merged == "true" ]]; then
    action=${msg:-$DEFAULT_UPSTREAM_ACTION}
    warn "$desc: upstream $owner/$repo PR #$num is merged. $action"
  elif [[ $state == "closed" ]]; then
    action=${msg:-$DEFAULT_UPSTREAM_ACTION}
    warn "$desc: upstream $owner/$repo $label #$num is closed. $action"
  fi
}

main() {
  local count
  count=$(jq 'length' <<<"$ENTRIES_JSON")
  if [[ $count == "0" ]]; then
    return 0
  fi

  local i url description message channel
  for ((i = 0; i < count; i++)); do
    url=$(jq -r ".[$i].url" <<<"$ENTRIES_JSON")
    description=$(jq -r ".[$i].description" <<<"$ENTRIES_JSON")
    message=$(jq -r ".[$i].message // \"\"" <<<"$ENTRIES_JSON")
    channel=$(jq -r ".[$i].targetChannel" <<<"$ENTRIES_JSON")

    if ! parse_url "$url"; then
      diag "skipping unparseable url: $url"
      continue
    fi

    if [[ $OWNER == "NixOS" && $REPO == "nixpkgs" ]]; then
      if [[ $KIND == "pull" ]]; then
        check_nixpkgs_pr "$NUM" "$description" "$message" "$channel"
      else
        check_nixpkgs_issue "$NUM" "$description" "$message"
      fi
    else
      check_external "$OWNER" "$REPO" "$KIND" "$NUM" "$description" "$message"
    fi
  done
}

main "$@"
