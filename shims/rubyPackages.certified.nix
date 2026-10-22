# certified: `require "certified"` patches Net::HTTP#use_ssl= to set ca_file to the gem's
# certs/ca-bundle.crt (and VERIFY_PEER), and OpenSSL::X509::Store#set_default_paths to add it.
# The shim requires it and does one Net::HTTP GET.
args:
import ./ruby-gem.nix args {
  require = "certified";
  code = ''
    f = File.join(spec.gem_dir, "certs/ca-bundle.crt")
    puts "certs/ca-bundle.crt -> #{File.realpath(f)}"
    r = Net::HTTP.get_response(URI(ARGV[0]))
    puts "status #{r.code}"
  '';
}
