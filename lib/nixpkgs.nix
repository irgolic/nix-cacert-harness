# nixpkgs <src> with an optional extra overlay (used to simulate a fix without touching the
# worktree, e.g. `--after-overlay fixes/httplib2.nix`).
{ src, overlay ? "" }:
import src { overlays = if overlay == "" then [ ] else [ (import overlay) ]; }
