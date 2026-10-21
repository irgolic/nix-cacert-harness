# zulu: pkgs/development/compilers/zulu/<ver>.nix declares only { callPackage, enableJavaFX, ... }
# and forwards the rest to common.nix. The default injection inspects declared arguments, so it
# sees no `cacert`; override explicitly, but only when common.nix takes `cacert` (the before-fix
# side does not, and an unexpected argument would be an evaluation error).
{ pkg, pkgs, probes, ... }:
let
  common = import "${pkgs.path}/pkgs/development/compilers/zulu/common.nix";
in
{
  inputs = [ pkg ];
  inject = p: c: if (builtins.functionArgs common) ? cacert then p.override { cacert = c; } else p;
  script = ''
    java -cp ${probes.java} TlsProbe "$URL"
  '';
}
