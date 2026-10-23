# olvid, for bin/ca-live-check only (shims/live/ is not picked up by ca-check's behavioral matrix).
# bin/olvid is a makeBinaryWrapper around nixpkgs' jdk21, not around the runtime bundled in lib/,
# whose stale lib/security/cacerts the fix removes. The shim takes the java that the wrapper execs
# (the /nix/store/*/bin/java string in it) and runs TlsProbe on it: that JVM's default trust store
# is what the app's HTTPS connections use. A control: expected REFUSED on both sides
# (INCONCLUSIVE-BEFORE), because that openjdk already uses cacert at the base (#576518).
{ pkgs, probes, ... }:
{
  inputs = [ pkgs.gnugrep ];
  script = ''
    java=$(grep -aoE '/nix/store/[a-z0-9]{32}-[^/[:space:]]+/bin/java' "$PKG/bin/olvid" | head -1)
    echo "bin/olvid execs $java"
    if [ -e "$PKG/lib/security/cacerts" ]; then
      echo "bundled runtime keystore lib/security/cacerts present (bin/olvid does not use it)"
    fi
    "$java" -cp ${probes.java} TlsProbe "$URL"
  '';
}
