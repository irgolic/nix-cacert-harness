// Minimal HTTPS client for the behavioral check. Uses only the JRE's default trust
// (JAVA_HOME/lib/security/cacerts) and default hostname verification.
// Compiled once with --release 8 so it runs on every JRE from 8 up.
import java.io.InputStream;
import java.net.URL;
import javax.net.ssl.HttpsURLConnection;

public class TlsProbe {
    public static void main(String[] args) throws Exception {
        System.out.println("java.home=" + System.getProperty("java.home")
            + " trustStore=" + System.getProperty("javax.net.ssl.trustStore", "(default)"));
        HttpsURLConnection c = (HttpsURLConnection) new URL(args[0]).openConnection();
        c.setConnectTimeout(10000);
        c.setReadTimeout(10000);
        c.connect(); // TLS handshake incl. certificate validation happens here
        String cipher = c.getCipherSuite();
        int status = c.getResponseCode();
        try (InputStream in = c.getInputStream()) {
            byte[] buf = new byte[4096];
            while (in.read(buf) > 0) { }
        }
        System.out.println("OK status=" + status + " cipher=" + cipher);
    }
}
