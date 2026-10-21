# graalvmPackages.graalvm-ce (also usable for graalvm-ce-musl): graalvm-ce/default.nix declares
# only { stdenv, fetchurl, graalvmPackages, useMusl }, so the default injection finds no `cacert`.
# The fix is in the scope's community-edition/buildGraalvm.nix, which is `self.callPackage`d
# and also takes `...` (unknown arguments are forwarded into mkDerivation). Inject by giving the
# package a graalvmPackages scope that holds the test cacert, and only when buildGraalvm.nix
# declares `cacert` (the before side does not, so its test cell is the same derivation: NO-OP).
{ pkg, pkgs, probes, ... }:
let
  builder = import "${pkgs.path}/pkgs/development/compilers/graalvm/community-edition/buildGraalvm.nix";
in
{
  inputs = [ pkg ];
  inject =
    p: c:
    if (builtins.functionArgs builder) ? cacert then
      p.override { graalvmPackages = pkgs.graalvmPackages.overrideScope (_: _: { cacert = c; }); }
    else
      p;
  script = ''
    java -cp ${probes.java} TlsProbe "$URL"
  '';
}
