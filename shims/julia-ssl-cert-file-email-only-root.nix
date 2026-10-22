# --shim julia-ssl-cert-file-email-only-root --sides before: SSL_CERT_FILE = ca-bundle.crt + the test
# root as an e-mail-only TRUSTED block (no plain copy). Read the stock cell: REFUSED = not trusted for TLS.
args: import ./julia-env.nix args { emailOnlyTestRoot = true; }
