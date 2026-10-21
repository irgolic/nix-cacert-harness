# shellcheck shell=bash
# Shared helpers for the cacert de-vendoring harness. Sourced by bin/ca-static-check and
# bin/ca-behave-check. Never touches the git index/HEAD of $CAH_REPO; "before" is read
# from a commit via builtins.fetchGit (read-only export into the store).

CAH_HOME=${CAH_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
CAH_REPO=${CAH_REPO:-$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}
CAH_NIXB=${CAH_NIXB:-$CAH_HOME/bin/nixb}
CAH_OUT=${CAH_OUT:-$CAH_HOME/out}
# Pinned so results are reproducible; override with CAH_SCANNER_REF=github:zimbatm/nix-cacert-scan
CAH_SCANNER_REF=${CAH_SCANNER_REF:-github:zimbatm/nix-cacert-scan/3bae26b1140e29ed0f6e6f64021567cc3c85804d}
# Max number of derivations a side may need to *build* before we refuse (diff-only).
CAH_MAX_BUILDS=${CAH_MAX_BUILDS:-4}
# Anything matching this in the to-build list is considered a big from-source build.
CAH_HEAVY_RE=${CAH_HEAVY_RE:-'-(julia|kodi|jetbrains|graalvm|supertuxkart|chromium|firefox|thunderbird|electron|llvm|clang|gcc|rustc|ghc|qtbase|qtwebengine|webkitgtk|openjdk|libreoffice|linux|mesa|texlive|ffmpeg|boost|gtk[34]?|nodejs|go|python3)-[0-9]'}

log() { printf '%s\n' "$*" >&2; }
die() { log "error: $*"; exit 2; }

# --- base revision -------------------------------------------------------------------
cah_resolve_base() {
  local b
  if b=$(git -C "$CAH_REPO" merge-base HEAD upstream/master 2>/dev/null); then echo "$b"; return; fi
  if b=$(git -C "$CAH_REPO" rev-parse --verify -q cacert-devendor 2>/dev/null); then echo "$b"; return; fi
  die "cannot determine base: no upstream/master and no cacert-devendor branch (pass --base REV)"
}

# Export <rev> of the local repo into the store (cached by nix after the first ~100 s).
cah_base_src() {
  local rev=$1
  nix eval --raw --impure --expr \
    "(builtins.fetchGit { url = \"$CAH_REPO\"; rev = \"$rev\"; shallow = true; }).outPath"
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
