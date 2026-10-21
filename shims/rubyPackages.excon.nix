# excon: with no ssl_ca_file/ssl_ca_path/ssl_cert_store and no SSL_CERT_FILE/SSL_CERT_DIR, Excon's
# SSLSocket adds Excon::DEFAULT_CA_FILE (data/cacert.pem) to a store with OpenSSL's default paths.
args:
import ./ruby-gem.nix args {
  require = "excon";
  code = ''
    f = Excon::DEFAULT_CA_FILE
    puts "DEFAULT_CA_FILE = #{f} -> #{File.realpath(f)}"
    r = Excon.get(ARGV[0], connect_timeout: 10, read_timeout: 10)
    puts "status #{r.status}"
  '';
}
