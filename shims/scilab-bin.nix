# scilab-bin: Scilab's Java parts (GUI, xcos, its HTTP client functions) run on the JRE bundled in
# thirdparty/java. Run the TLS probe on that JRE directly: autoPatchelf has fixed its RUNPATHs
# (the fix's postFixup already runs its keytool), and the probe needs only java.base, so none of
# the launcher's environment is required. The package declares `cacert`: default injection.
{ pkg, probes, ... }:
{
  inputs = [ ];
  script = ''
    "${pkg}/thirdparty/java/bin/java" -cp ${probes.java} TlsProbe "$URL"
  '';
}
