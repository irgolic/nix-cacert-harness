# --shim julia-ssl-cert-file --sides before: the unmodified julia with SSL_CERT_FILE=<cacert>/etc/ssl/certs/ca-bundle.crt
args: import ./julia-env.nix args { }
