# httpclient: SSLConfig lazily loads lib/httpclient/cacert.pem (load_trust_ca -> load_cacerts)
# as the trust anchor unless the caller changes the cert store.
args:
import ./ruby-gem.nix args {
  require = "httpclient";
  code = ''
    f = File.join(Gem.loaded_specs["httpclient"].gem_dir, "lib/httpclient/cacert.pem")
    puts "cacert.pem = #{f} -> #{File.realpath(f)}"
    c = HTTPClient.new
    c.connect_timeout = c.receive_timeout = 10
    r = c.get(ARGV[0])
    puts "status #{r.status}"
  '';
}
