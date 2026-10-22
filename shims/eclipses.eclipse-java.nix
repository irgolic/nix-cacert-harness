# eclipses.eclipse-java (works for any eclipses.eclipse-*): the tarball ships a JustJ JRE in
# eclipse/plugins/org.eclipse.justj.openjdk.*/jre, whose lib/security/cacerts the fix regenerates
# from cacert. Eclipse itself does not run on it (build-eclipse.nix drops the JustJ -vm line from
# eclipse.ini and puts nixpkgs' jdk on PATH), so this tests the bundled JRE as such, for anything
# that launches it. build-eclipse.nix does not patchelf that JRE: run it through the loader.
# Injection: the package is buildEclipseUnversioned (callPackage ./build-eclipse.nix { ... } in
# eclipse/default.nix) applied to per-edition data; the result has no `.override` of its own, so the
# default injection is a NO-OP. Re-evaluate the eclipses set with a callPackage that also passes
# `cacert`, only when build-eclipse.nix declares it (the base does not: before-test is a NO-OP).
args@{ pkgs, lib, ... }:
let
  builder = import "${pkgs.path}/pkgs/applications/editors/eclipse/build-eclipse.nix";
in
import ./bundled-jre.nix args {
  jre = "eclipse/plugins/org.eclipse.justj.openjdk.*/jre";
  loader = true;
  inject =
    p: c:
    if (lib.functionArgs builder) ? cacert then
      (pkgs.eclipses.override {
        callPackage =
          fn: fargs:
          let
            f = if lib.isFunction fn then fn else import fn;
          in
          pkgs.callPackage fn (fargs // lib.optionalAttrs ((lib.functionArgs f) ? cacert) { cacert = c; });
      }).${p.pname}
    else
      p;
}
