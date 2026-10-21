# Small, cached toolset used by the harness itself (taken from the *base* nixpkgs so
# that concurrent edits in the worktree can never force a rebuild of the tools).
{ src }:
let
  pkgs = import src { overlays = [ ]; };
in
pkgs.symlinkJoin {
  name = "ca-harness-tools";
  paths = with pkgs; [
    openssl.bin
    jq
    curl.bin
    gawk
    jre_minimal # only for bin/keytool (keytool lives in java.base)
    python3 # lib/certset.py (stdlib only)
  ];
}
