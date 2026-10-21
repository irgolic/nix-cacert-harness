# nap: REST::Request verifies only with tls_verify (or verify_ssl): true, and then uses
# support/cacert.pem unless tls_ca_file is given. Without tls_verify it does not verify at all
# (VERIFY_NONE), so the vendored file only matters for callers that ask for verification.
args:
import ./ruby-gem.nix args {
  require = "rest";
  code = ''
    f = File.join(Gem.loaded_specs["nap"].gem_dir, "support/cacert.pem")
    puts "support/cacert.pem = #{f} -> #{File.realpath(f)}"
    r = REST.get(ARGV[0], {}, { tls_verify: true })
    puts "status #{r.status_code}"
  '';
}
