# Shared shim for a Ruby gem that vendors a CA bundle (the rubyPackages.* gem-config fixes).
# Use from shims/rubyPackages.<gem>.nix:
#   args: import ./ruby-gem.nix args { require = "<feature>"; code = "<ruby, URL in ARGV[0]>"; }
# `extraGems` (names in the same ruby's gem set) adds gems the package needs but does not declare.
# The gem and the gems it propagates are on GEM_PATH; the shim runs `ruby -e` under env -i,
# and the sandbox has no /etc/ssl, so SSL_CERT_FILE/SSL_CERT_DIR are unset (checked) and
# OpenSSL's default paths are empty: the gem's own bundle is what decides.
# Injection: the fixes take `cacert` in gem-config (defaultGemConfig), not in the gem's own
# function, so the default `.override { cacert }` cannot reach them. `inject` rebuilds the gem
# set the way ruby's passthru.gems does (ruby-modules/with-packages), with
# gemConfig = defaultGemConfig.override { cacert = <test cacert>; }, and takes the same gem.
# Where gem-config does not take cacert (the base), it is a NO-OP.
{ pkg, pkgs, lib, ... }:
{
  require,
  code,
  extraGems ? [ ],
}:
let
  ruby = pkg.ruby;
  gemEnv = pkgs.buildEnv {
    name = "ca-shim-gems";
    # buildEnv follows propagated-user-env-packages: the gem's dependencies come along
    paths = [ pkg ] ++ map (n: ruby.gems.${n}) extraGems;
    pathsToLink = [ "/lib" ];
  };
in
{
  inputs = [ ruby ];
  script = ''
    export GEM_PATH=${gemEnv}/${ruby.gemPath} GEM_HOME="$TMPDIR/gem-home"
    exec ruby -e '
      $stdout.sync = true
      abort "SSL_CERT_FILE/SSL_CERT_DIR set" if ENV["SSL_CERT_FILE"] || ENV["SSL_CERT_DIR"]
      require "openssl"
      puts "OpenSSL default cert file #{OpenSSL::X509::DEFAULT_CERT_FILE} exists: #{File.exist?(OpenSSL::X509::DEFAULT_CERT_FILE)}"
      require "${require}"
      spec = Gem.loaded_specs["${pkg.pname}"]
      puts "${pkg.pname} #{spec.version} from #{spec.gem_dir}"
      ${code}
    ' -- "$URL"
  '';
  inject =
    p: c:
    if (lib.functionArgs pkgs.defaultGemConfig.override) ? cacert then
      (import (pkgs.path + "/pkgs/development/ruby-modules/with-packages") {
        inherit (pkgs)
          lib
          stdenv
          makeBinaryWrapper
          buildRubyGem
          buildEnv
          ;
        ruby = p.ruby;
        gemConfig = pkgs.defaultGemConfig.override { cacert = c; };
      }).gems.${p.pname}
    else
      p;
}
