# Shared shim for a package that ships its own JRE inside its output (Eclipse RCP apps with a
# JustJ or similar JRE plugin, ...): run the TLS probe on that JRE's bin/java, so the JVM's
# java.home is the bundled JRE and its trust store is <jre>/lib/security/cacerts.
# Use from shims/<attr>.nix:
#   args: import ./bundled-jre.nix args { jre = "<glob of the JRE dir under the output>"; }
# `jre` must match exactly one directory (checked; anything else is an ERROR cell, never REFUSED).
# `loader = true` runs bin/java through nixpkgs' dynamic loader, for JREs the package leaves
# unpatched (their interpreter is /lib64/ld-linux-*.so.2, which the build sandbox does not have).
# The launcher then finds its java.home from libjli.so's location, so it is still the bundled JRE
# (the probe prints java.home). `inject` is passed through (default: `.override { cacert }`).
{ pkg, pkgs, lib, probes, ... }:
{
  jre,
  loader ? false,
  inject ? null,
}:
{
  inputs = [ ];
  script = ''
    set -- ${pkg}/${jre}
    if [ $# -ne 1 ] || [ ! -x "$1/bin/java" ]; then
      echo "expected exactly one bundled JRE at ${pkg}/${jre}, found: $*"
      exit 2
    fi
    echo "bundled JRE: $1"
    ${lib.optionalString loader "${pkgs.stdenv.cc.bintools.dynamicLinker} --library-path ${
      lib.makeLibraryPath [
        pkgs.stdenv.cc.libc
        pkgs.zlib
      ]
    }"} "$1/bin/java" -cp ${probes.java} TlsProbe "$URL"
  '';
}
// lib.optionalAttrs (inject != null) { inherit inject; }
