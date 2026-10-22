# tracecompass: the tarball ships a JustJ JRE in trace-compass/plugins/org.eclipse.justj.openjdk.*/jre,
# whose lib/security/cacerts the fix regenerates from cacert. The launcher's tracecompass.ini gets
# `-vm <nixpkgs jdk21>`, so Trace Compass itself does not run on it; this tests the bundled JRE as
# such. The package does not patchelf that JRE: run it through the loader. The package declares
# `cacert`: default injection.
args:
import ./bundled-jre.nix args {
  jre = "trace-compass/plugins/org.eclipse.justj.openjdk.*/jre";
  loader = true;
}
