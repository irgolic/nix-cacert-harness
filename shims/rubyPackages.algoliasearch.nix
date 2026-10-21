# algoliasearch (1.x): Algolia::Client builds one HTTPClient session per host and calls
# ssl_config.add_trust_ca(resources/ca-bundle.crt) on it, which also stops httpclient from
# loading its own cacert.pem: that file is the session's only trust anchor. The client takes
# `hosts:` and needs no real credentials to be constructed (application_id/api_key are only
# sent as headers). The shim takes the session the client builds for $URL's host and does one
# GET with it; the client's own request methods would go on to JSON.parse the reply, which the
# test server's HTML status page is not.
# algolia/client.rb requires base64, a bundled (not default) gem since Ruby 3.4 that the gem does
# not declare, so `require "algoliasearch"` fails on nixpkgs' ruby without extraGems.
args:
import ./ruby-gem.nix args {
  require = "algoliasearch";
  extraGems = [ "base64" ];
  code = ''
    f = File.join(Gem.loaded_specs["algoliasearch"].gem_dir, "resources/ca-bundle.crt")
    puts "resources/ca-bundle.crt = #{f} -> #{File.realpath(f)}"
    u = URI(ARGV[0])
    c = Algolia::Client.new(application_id: "harness", api_key: "none", hosts: ["#{u.host}:#{u.port}"])
    host = c.send(:thread_local_hosts, true).first
    puts "session for #{host[:base_url]}"
    r = host[:session].get(host[:base_url] + u.path)
    puts "status #{r.status}"
  '';
}
