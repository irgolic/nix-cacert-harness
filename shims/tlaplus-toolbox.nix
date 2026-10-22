# tlaplus-toolbox: the Toolbox runs on its bundled JRE (Java 14) in
# libexec/toolbox/plugins/org.lamport.openjdk.*/jre, which the package patchelfs (interpreter, plus
# zlib in the RUNPATH of bin/java), so the probe runs on it directly. The fix regenerates that JRE's
# lib/security/cacerts from cacert. The package declares `cacert`: default injection.
args:
import ./bundled-jre.nix args {
  jre = "libexec/toolbox/plugins/org.lamport.openjdk.*/jre";
}
