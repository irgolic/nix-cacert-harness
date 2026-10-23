# The runnable wrapper of bin/ca-live-check: the shim's script for the *stock* package of one side
# (no injection, no test root), with the shim's inputs on PATH and PKG/CACERT set as in a
# behavioral cell. It is run on the host, outside any sandbox, against a live URL, by
# bin/ca-live-check, which sets URL/HOST/PORT/HOME/TMPDIR under `env -i`.
{
  src, # nixpkgs for the side under test
  overlay ? "", # optional overlay file (as in lib/behave.nix)
  toolsSrc, # nixpkgs for harness tools (the base, so it is cached)
  attr,
  shim, # absolute path of the shim (.nix or .sh)
}:
let
  pkgs = import src { overlays = if overlay == "" then [ ] else [ (import overlay) ]; };
  tools = import toolsSrc { overlays = [ ]; };
  inherit (pkgs) lib;
  pkg = lib.getAttrFromPath (lib.splitString "." attr) pkgs;
  probes = import ./probes.nix { inherit tools; };
  shimPath = /. + shim;
  shimFn =
    if lib.hasSuffix ".nix" shim then
      import shimPath
    else
      ({ pkg, ... }: { inputs = [ pkg ]; script = builtins.readFile shimPath; });
  shimRes = shimFn {
    inherit pkgs lib probes pkg;
    inherit (pkgs) cacert;
  };
in
tools.writeShellScript "ca-live-${lib.replaceStrings [ "." ] [ "-" ] attr}" ''
  export PATH=${lib.makeBinPath ((shimRes.inputs or [ ]) ++ [ tools.coreutils tools.bash ])}
  export PKG=${pkg} CACERT=${pkgs.cacert}
  echo "package: $PKG"
  exec ${tools.bash}/bin/bash -eu ${tools.writeText "shim.sh" shimRes.script}
''
