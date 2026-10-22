# Not a fix: a variant of the cacert/julia-bin fix branch for a review question ("Julia already
# reads /etc/ssl/certs/ca-bundle.crt on NixOS, so cert.pem could point at cacert's ca-bundle.crt").
# On top of the fix branch it links share/julia/cert.pem to cacert's ca-bundle.crt (the bundle
# WITH OpenSSL trust-rule blocks, "BEGIN TRUSTED CERTIFICATE") instead of
# ca-no-trust-rules-bundle.crt. Use with --after-overlay and --after <fix branch sha>.
#
# The edit is a string replacement inside the fix's installPhase, so the cacert store path in it
# stays the one the package was called with: `.override { cacert = cacertTest; }` (the harness's
# default injection) still reaches it. It also keeps doInstallCheck = false, like
# julia-bin-skip-installcheck.nix (the install check runs Julia's whole test suite).
# Evaluation fails if the fix's ln line is not there (e.g. used against the base commit).
final: prev:
prev.lib.genAttrs [ "julia_110-bin" "julia_111-bin" "julia_112-bin" "julia_113-bin" ] (
  a:
  prev.${a}.overrideAttrs (old: {
    doInstallCheck = false;
    installPhase =
      let
        from = "/etc/ssl/certs/ca-no-trust-rules-bundle.crt $out/share/julia/cert.pem";
        to = "/etc/ssl/certs/ca-bundle.crt $out/share/julia/cert.pem";
      in
      assert prev.lib.assertMsg (prev.lib.hasInfix from old.installPhase)
        "julia-bin-trust-rules.nix: the fix's cert.pem symlink is not in ${a}'s installPhase";
      builtins.replaceStrings [ from ] [ to ] old.installPhase;
  })
)
