# LibGit2 (Julia's stdlib wrapper around the bundled libgit2) against the cell's TLS server.
# LibGit2.initialize() passes NetworkOptions.ca_roots() to git_libgit2_opts(SET_SSL_CERT_LOCATIONS),
# so libgit2 loads the same file as Downloads (in the cell: share/julia/cert.pem). 1.13's libgit2
# links OpenSSL 3, 1.10's mbedTLS 2.28. The server is `openssl s_server -www`, not a git server,
# so a clone cannot succeed; the shim tells the two outcomes apart by libgit2's error:
#   certificate refused: exit 1 (REFUSED). libgit2 hands an unverified certificate to Julia's
#     certificate_callback (valid = 0), which prints "TLS host verification: ..." and returns
#     CERT_REJECT; libgit2 then raises "user rejected certificate for <host>" (class HTTP,
#     code ERROR). GIT_ECERTIFICATE (-17) is accepted as well.
#   an HTTP-layer error after the handshake  -> TLS verified, CA file loaded and used: exit 0
#   anything else (CA file not loadable, ...) -> exit 2 (ERROR)
# Usable on both sides; the package declares cacert after the fix (default injection).
{ pkg, ... }:
{
  inputs = [ pkg ];
  script = ''
    julia --startup-file=no --history-file=no -e '
      using LibGit2, NetworkOptions
      p = NetworkOptions.ca_roots()
      println("julia ", VERSION, ", libgit2 ", LibGit2.version(), ": ca_roots() = ", p, " -> ", realpath(p))
      dir = mktempdir()
      try
          LibGit2.clone(ARGS[1] * "repo.git", joinpath(dir, "r"))
          println("clone succeeded against a non-git server?"); exit(2)
      catch e
          e isa LibGit2.GitError || rethrow()
          println("GitError class=", e.class, " code=", e.code, ": ", e.msg)
          if e.code == LibGit2.Error.ECERTIFICATE || occursin("rejected certificate", e.msg)
              println("certificate verify failed (libgit2: server certificate not verified)"); exit(1)
          elseif e.class in (LibGit2.Error.HTTP, LibGit2.Error.Net) && !occursin(r"ssl|tls|certificate"i, e.msg)
              println("TLS handshake verified; error from the HTTP/git layer after it"); exit(0)
          else
              exit(2)
          end
      end
    ' "$URL"
  '';
}
