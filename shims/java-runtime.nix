# Generic shim for anything that provides bin/java (JDKs, JREs, bundled runtimes):
# run a precompiled (--release 8) HTTPS probe with the JVM's default truststore.
{ pkg, probes, ... }:
{
  inputs = [ pkg ];
  script = ''
    java -cp ${probes.java} TlsProbe "$URL"
  '';
}
