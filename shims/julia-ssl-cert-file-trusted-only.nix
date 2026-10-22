# --shim julia-ssl-cert-file-trusted-only --sides before: SSL_CERT_FILE = only the TRUSTED blocks of ca-bundle.crt
args: import ./julia-env.nix args { trustedOnly = true; }
