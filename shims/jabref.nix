# jabref: JabRef accepts a server chain if EITHER the JRE's cacerts OR its own truststore trusts it.
# At startup (jabgui and jabkit launchers) org.jabref.logic.net.ssl.TrustStoreManager
# .createTruststoreFileIfNotExist(<data dir>/ssl/truststore.jks) seeds that file from the
# /ssl/truststore.jks resource in its jars (the file the fix regenerates from cacert) and installs a
# merged X509TrustManager as the default SSLContext. The probe calls exactly that (reflectively, so
# it compiles with --release 8 against nothing) on the package's own JRE and jabkit jar, then does
# the GET with TlsProbe in the same JVM. The JRE (jre25_minimal from jdk25) is built with the stock
# cacert in every cell, so only JabRef's store can make a cell connect. Default injection.
{ pkg, pkgs, probes, ... }:
let
  probe = pkgs.runCommand "ca-tls-probe-jabref" { nativeBuildInputs = [ pkgs.jdk_headless ]; } ''
    mkdir -p $out
    cat > JabRefTlsProbe.java <<'EOF'
    import java.nio.file.*;
    public class JabRefTlsProbe {
      public static void main(String[] args) throws Exception {
        Path ts = Paths.get(System.getenv("TMPDIR"), "jabref", "ssl", "truststore.jks");
        Class.forName("org.jabref.logic.net.ssl.TrustStoreManager")
          .getMethod("createTruststoreFileIfNotExist", Path.class).invoke(null, ts);
        System.out.println("seeded " + ts + " (" + Files.size(ts) + " bytes)");
        TlsProbe.main(args);
      }
    }
    EOF
    javac --release 8 -Xlint:-options -cp ${probes.java} -d $out JabRefTlsProbe.java
  '';
in
{
  inputs = [ pkgs.gnugrep ];
  script = ''
    java=$(grep -oE '/nix/store/[^ "]+/bin/java' ${pkg}/bin/jabkit | head -1)
    set -- ${pkg}/lib/jabkit-*-all.jar
    if [ $# -ne 1 ] || [ ! -x "$java" ]; then echo "expected one jabkit jar and the wrapper's java, got: $* / $java"; exit 2; fi
    echo "jre: $java jar: $1"
    "$java" -cp "$1:${probes.java}:${probe}" JabRefTlsProbe "$URL"
  '';
}
