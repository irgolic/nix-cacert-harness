# frostwire-bin, for bin/ca-live-check only (shims/live/ is not picked up by ca-check's behavioral
# matrix). bin/frostwire runs share/java/frostwire, whose JAVA_PROGRAM_DIR the package points at
# nixpkgs' jre; the bundled share/java/jre (removed by the fix, with its stale cacerts) is only the
# launcher's fallback when that directory is missing. The shim runs TlsProbe on the java the
# launcher would pick. A control: expected REFUSED on both sides (INCONCLUSIVE-BEFORE), because
# that openjdk already uses cacert at the base (#576518).
{ pkgs, probes, ... }:
{
  inputs = [ pkgs.gnused ];
  script = ''
    dir=$(sed -n 's/^export JAVA_PROGRAM_DIR=//p' "$PKG/share/java/frostwire" | head -1)
    echo "share/java/frostwire: JAVA_PROGRAM_DIR=$dir"
    if [ -d "$PKG/share/java/jre" ]; then
      echo "bundled share/java/jre present (only the launcher's fallback)"
    fi
    "''${dir%/}/java" -cp ${probes.java} TlsProbe "$URL"
  '';
}
