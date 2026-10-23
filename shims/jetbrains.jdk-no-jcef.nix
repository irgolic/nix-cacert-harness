# jetbrains.jdk-no-jcef (also fits jetbrains.jdk): the generic Java probe (java-runtime.nix) on the JBR.
# Injection: pkgs/development/compilers/jetbrains-jdk/default.nix declares neither `cacert` nor `...`;
# it calls common.nix (which takes `cacert` after the fix) through its own `callPackage` argument. The
# default injection therefore sees no `cacert` and would be a NO-OP. Override that `callPackage` with
# one that also passes `cacert` to functions that declare it, only when common.nix declares it (the
# before-fix side does not: before-test is the before-stock derivation).
args@{ pkgs, lib, ... }:
let
  common = import "${pkgs.path}/pkgs/development/compilers/jetbrains-jdk/common.nix";
in
import ./java-runtime.nix args
// {
  inject =
    p: c:
    if (lib.functionArgs common) ? cacert then
      p.override {
        callPackage =
          fn: fargs:
          let
            f = if lib.isFunction fn then fn else import fn;
          in
          pkgs.callPackage fn (fargs // lib.optionalAttrs ((lib.functionArgs f) ? cacert) { cacert = c; });
      }
    else
      p;
}
