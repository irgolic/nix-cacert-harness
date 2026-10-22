# shellcheck shell=bash
# Shared helpers for the cacert de-vendoring harness. Sourced by bin/ca-static-check and
# bin/ca-behave-check. Never touches the git index/HEAD of $CAH_REPO; "before" is read
# from a commit via builtins.fetchGit (read-only export into the store).

CAH_HOME=${CAH_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
CAH_REPO=${CAH_REPO:-$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}
CAH_NIXB=${CAH_NIXB:-$CAH_HOME/bin/nixb}
CAH_OUT=${CAH_OUT:-${XDG_CACHE_HOME:-$HOME/.cache}/nix-cacert-harness}
# Pinned so results are reproducible; override with CAH_SCANNER_REF=github:zimbatm/nix-cacert-scan
CAH_SCANNER_REF=${CAH_SCANNER_REF:-github:zimbatm/nix-cacert-scan/3bae26b1140e29ed0f6e6f64021567cc3c85804d}
# Max number of derivations a side may need to *build* before we refuse (diff-only).
CAH_MAX_BUILDS=${CAH_MAX_BUILDS:-4}
# Anything matching this in the to-build list is considered a big from-source build.
CAH_HEAVY_RE=${CAH_HEAVY_RE:-'-(julia|kodi|jetbrains|graalvm|supertuxkart|chromium|firefox|thunderbird|electron|llvm|clang|gcc|rustc|ghc|qtbase|qtwebengine|webkitgtk|openjdk|corretto[0-9]*|libreoffice|linux|mesa|texlive|ffmpeg|boost|gtk[34]?|nodejs|go|python3)-[0-9]'}

log() { printf '%s\n' "$*" >&2; }
die() { log "error: $*"; exit 2; }

# --- base revision -------------------------------------------------------------------
cah_resolve_base() {
  local b r
  cah_have_repo || die "not inside a nixpkgs checkout: pass --base REV (the before-fix commit)"
  for r in upstream/master origin/master master; do
    if b=$(git -C "$CAH_REPO" merge-base HEAD "$r" 2>/dev/null) && [[ $b != $(git -C "$CAH_REPO" rev-parse HEAD) ]]; then echo "$b"; return; fi
  done
  die "cannot determine the before-fix base: HEAD has no merge-base with upstream/master, origin/master or master that differs from HEAD (pass --base REV)"
}

# Is $CAH_REPO a nixpkgs git checkout?
cah_have_repo() { [[ -e $CAH_REPO/pkgs/top-level/all-packages.nix ]] && git -C "$CAH_REPO" rev-parse --verify -q HEAD >/dev/null 2>&1; }

# cah_src_for <REV>: a nixpkgs source tree in the store for one side.
#   github:OWNER/REPO/REV   -> GitHub archive tarball of that commit
#   a commit in $CAH_REPO   -> read-only export of the local repo (fetchGit, no checkout)
#   a bare commit hash      -> GitHub archive from ${CAH_GITHUB_REPO:-NixOS/nixpkgs}
# (PR head commits are reachable through the base repo's archive URL once the PR exists.)
cah_src_for() {
  local rev=$1 url
  if [[ $rev == github:*/*/* ]]; then
    rev=${rev#github:}; url="https://github.com/${rev%/*}/archive/${rev##*/}.tar.gz"
  elif cah_have_repo && git -C "$CAH_REPO" rev-parse --verify -q "$rev^{commit}" >/dev/null 2>&1; then
    rev=$(git -C "$CAH_REPO" rev-parse "$rev^{commit}")
    nix eval --raw --impure --expr \
      "(builtins.fetchGit { url = \"$CAH_REPO\"; rev = \"$rev\"; shallow = true; }).outPath"
    return
  elif [[ $rev =~ ^[0-9a-f]{7,40}$ ]]; then
    url="https://github.com/${CAH_GITHUB_REPO:-NixOS/nixpkgs}/archive/$rev.tar.gz"
  else
    die "cannot resolve revision '$rev': not a commit in $CAH_REPO, not a hash, not github:OWNER/REPO/REV"
  fi
  log "fetching $url"
  nix eval --raw --impure --expr "(builtins.fetchTarball \"$url\")"
}
cah_base_src() { cah_src_for "$1"; }

# cah_after_src [REV]: the after side. Default is the local worktree.
cah_after_src() {
  if [[ -n ${1:-} ]]; then cah_src_for "$1"; return; fi
  cah_have_repo || die "not inside a nixpkgs checkout: pass --after REV (and --base REV), or set CAH_REPO"
  echo "$CAH_REPO"
}

# --- nix arg vectors for a side ----------------------------------------------------------
# cah_side_args <src> [overlay]  -> prints NUL-separated args for `nix build/eval`
cah_side_args() {
  local src=$1 overlay=${2:-}
  if [[ -n $overlay ]]; then
    printf '%s\0' -f "$CAH_HOME/lib/nixpkgs.nix" --argstr src "$src" --argstr overlay "$overlay"
  else
    printf '%s\0' -f "$src"
  fi
}

# --- dry run -----------------------------------------------------------------------------
# cah_dry_run <outfile> nix-args...   -> writes to-build .drv list to <outfile>, returns 0
cah_dry_run() {
  local outfile=$1; shift
  nix build --dry-run "$@" 2>&1 | awk '
    /will be built/ {b=1; next}
    /will be fetched|will be copied|^warning|^evaluat/ {b=0}
    b && /\.drv$/ {gsub(/^ +/, ""); print}' > "$outfile"
}

# cah_build_policy <drvlist> -> echoes "ok" | "heavy:<reason>"
cah_build_policy() {
  local list=$1 n heavy
  n=$(grep -c . "$list" || true)
  heavy=$(grep -E -- "$CAH_HEAVY_RE" "$list" | head -3 | sed 's|.*/[a-z0-9]\{32\}-||' | tr '\n' ' ' || true)
  if [[ -n $heavy ]]; then echo "heavy:$n drvs to build incl. ${heavy}"; return; fi
  if (( n > CAH_MAX_BUILDS )); then echo "heavy:$n drvs to build (> CAH_MAX_BUILDS=$CAH_MAX_BUILDS)"; return; fi
  echo ok
}

# --- tools --------------------------------------------------------------------------------
cah_tools() {   # <base-src>
  cah_realise -f "$CAH_HOME/lib/tools.nix" --argstr src "$1" 2>"$CAH_OUT/.tools.log" | tail -1
}
cah_scanner() {
  local p
  if p=$(cah_realise "$CAH_SCANNER_REF" 2>"$CAH_OUT/.scanner.log" | tail -1) && [[ -x $p/bin/cacert-scan ]]; then
    echo "$p"
  else
    log "warning: nix-cacert-scan unavailable (see $CAH_OUT/.scanner.log); falling back to file heuristics"
  fi
}

# --- certificate sets ---------------------------------------------------------------------
# Print "<SHA256 FP, uppercase hex, no colons>\t<subject>" for every cert in PEM file(s).
pem_fps() { python3 -I "$CAH_HOME/lib/certset.py" "$@"; }

# Keystore listing via keytool. Tries the classic password, then no password (JDK>=18
# style passwordless PKCS12, which is what the JDK itself uses for cacerts).
# Sets KS_NOTE. Prints "<FP>\t<alias / owner>".
KS_NOTE=
ks_fps() {
  local f=$1 raw
  KS_NOTE=
  if raw=$(keytool -list -v -keystore "$f" </dev/null 2>/dev/null) && grep -q 'SHA256:' <<<"$raw"; then
    KS_NOTE="no-password"
  elif raw=$(keytool -list -v -keystore "$f" -storepass changeit 2>/dev/null) && grep -q 'SHA256:' <<<"$raw"; then
    KS_NOTE="needs-password(changeit)"
  else
    KS_NOTE="unreadable-by-keytool"; return 1
  fi
  awk '/^Owner: / {sub(/^Owner: /,""); o=$0}
       /^[ \t]*SHA256: / {sub(/^[ \t]*SHA256: /,""); gsub(/:/,""); print $0 "\t" o}' <<<"$raw"
}

is_keystore() {  # by magic bytes
  local m
  m=$(od -An -N4 -tx1 "$1" 2>/dev/null | tr -d ' \n')
  case $m in
    feedfeed|cececece) return 0 ;;
    3082*|3083*|3080*) [[ $(basename "$1") =~ (cacerts|\.p12|\.pfx|\.jks|keystore|truststore)$ ]] && return 0 ;;
  esac
  return 1
}

# cert_set <file> <dst>: writes "<fp>\t<name>" to <dst>.tsv and sorted unique fps to <dst>;
# sets CS_KIND (pem|keystore) and CS_NOTE.
CS_KIND= CS_NOTE=
cert_set() {
  local f=$1 dst=$2
  CS_NOTE=
  if is_keystore "$f"; then
    CS_KIND=keystore
    ks_fps "$f" > "$dst.tsv" || true
    CS_NOTE=$KS_NOTE
  else
    CS_KIND=pem
    pem_fps "$f" > "$dst.tsv"
  fi
  cut -f1 "$dst.tsv" | sort -u > "$dst"
}

# cah_realise <nix build args...>: print out paths. If every requested output is already a
# valid store path, nothing needs to be built or fetched and we skip the nixb queue
# entirely; otherwise go through the nixb wrapper (machine-wide build semaphore).
cah_realise() {
  local p
  if p=$(nix path-info "$@" 2>/dev/null) && [[ -n $p ]]; then echo "$p"; return 0; fi
  "$CAH_NIXB" "$@"
}

# --- GitHub helpers -------------------------------------------------------------------------
cah_gh_api() {
  local r m
  r=$(curl -sL -H 'Accept: application/vnd.github+json' ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} "https://api.github.com/$1") || die "GitHub API request failed: $1"
  if m=$(jq -er '.message' <<<"$r" 2>/dev/null); then
    die "GitHub API: $m ($1). Set GITHUB_TOKEN to raise the rate limit, or pass --base/--after explicitly."
  fi
  printf '%s' "$r"
}

# cah_split_ref <REV> -> prints "OWNER/REPO SHA" for github:OWNER/REPO/SHA or a bare hash.
cah_split_ref() {
  local rev=$1
  if [[ $rev == github:*/*/* ]]; then rev=${rev#github:}; echo "${rev%/*} ${rev##*/}"
  elif [[ $rev =~ ^[0-9a-f]{7,40}$ ]]; then echo "${CAH_GITHUB_REPO:-NixOS/nixpkgs} $rev"
  else return 1; fi
}

# cah_parent_of <REV>: first parent of a GitHub commit, as github:OWNER/REPO/SHA.
cah_parent_of() {
  local repo sha p
  read -r repo sha < <(cah_split_ref "$1") || die "--after must be github:OWNER/REPO/REV or a commit hash to infer --base"
  p=$(cah_gh_api "repos/$repo/commits/$sha" | jq -r '.parents[0].sha // empty') || true
  [[ -n $p ]] || die "could not get the parent of $sha from GitHub ($repo); pass --base REV"
  echo "github:$repo/$p"
}

# cah_pr <N> [OWNER/REPO]: prints "github:REPO/BASE_SHA github:REPO/HEAD_SHA" for a pull request.
# Head commits of a fork PR are served through the base repository's archive URLs.
cah_pr() {
  local n=$1 repo=${2:-${CAH_GITHUB_REPO:-NixOS/nixpkgs}} j b h
  j=$(cah_gh_api "repos/$repo/pulls/$n") || die "could not read PR #$n of $repo from GitHub"
  b=$(jq -r '.base.sha // empty' <<<"$j"); h=$(jq -r '.head.sha // empty' <<<"$j")
  [[ -n $b && -n $h ]] || die "PR #$n: missing base/head sha"
  log "PR #$n: $(jq -r .title <<<"$j")  base=${b:0:12} head=${h:0:12}"
  echo "github:$repo/$b github:$repo/$h"
}
