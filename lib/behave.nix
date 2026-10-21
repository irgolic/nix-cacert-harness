# One cell of the behavioral matrix: build <attr> from <src> (+ optional overlay), optionally
# with a cacert that additionally trusts a throwaway test root, start a TLS server on
# localhost inside the build sandbox with a leaf signed by that root, and run the per-package
# shim against it. The cell *always* builds; its result is in $out/result (CONNECTED/REFUSED).
{
  src, # nixpkgs for the side under test (base export or worktree)
  overlay ? "", # optional overlay file (e.g. a simulated fix)
  toolsSrc, # nixpkgs for harness tools (openssl, curl, javac): the base, so it is cached
  attr, # "python3Packages.httplib2"
  shim, # absolute path of the shim (.nix or .sh)
  variant ? "test", # "stock" | "test"
  fixtures, # absolute path of the dir holding root.pem / leaf.pem / leaf.key
  salt ? "", # change to force a re-run
}:
let
  pkgs = import src { overlays = if overlay == "" then [ ] else [ (import overlay) ]; };
  tools = import toolsSrc { overlays = [ ]; };
  inherit (pkgs) lib;
  fx = builtins.path { path = /. + fixtures; name = "ca-harness-fixtures"; };

  pkg0 = lib.getAttrFromPath (lib.splitString "." attr) pkgs;
  cacertTest = pkgs.cacert.override { extraCertificateFiles = [ "${fx}/root.pem" ]; };
  cacertUsed = if variant == "test" then cacertTest else pkgs.cacert;

  # Default injection: the package's own function takes `cacert` -> override it.
  # A before-fix package usually does not take cacert at all, so this is a no-op there,
  # which is exactly the point (its trust store is not a function of cacert).
  defaultInject =
    p: c: if (lib.functionArgs (p.override or (_: { }))) ? cacert then p.override { cacert = c; } else p;

  probes = {
    java = tools.runCommand "ca-tls-probe-java" { nativeBuildInputs = [ tools.jdk_headless ]; } ''
      mkdir -p $out
      cp ${../probes/TlsProbe.java} TlsProbe.java
      javac --release 8 -Xlint:-options -d $out TlsProbe.java
    '';
  };

  shimPath = /. + shim;
  shimFn =
    if lib.hasSuffix ".nix" shim then
      import shimPath
    else
      ({ pkg, ... }: { inputs = [ pkg ]; script = builtins.readFile shimPath; });
  shimArgs = p: { inherit pkgs lib probes; pkg = p; cacert = cacertUsed; };
  inject = (shimFn (shimArgs pkg0)).inject or defaultInject;
  pkg = if variant == "test" then inject pkg0 cacertTest else pkg0;
  shimRes = shimFn (shimArgs pkg);
  injected = pkg.drvPath != pkg0.drvPath;
in
tools.runCommand "ca-behave-${lib.replaceStrings [ "." ] [ "-" ] attr}-${variant}"
  {
    nativeBuildInputs = [ tools.openssl tools.curl ];
    shimScript = tools.writeText "shim.sh" shimRes.script;
    shimPath = lib.makeBinPath ((shimRes.inputs or [ ]) ++ [ tools.coreutils tools.bash ]);
    pkgUnderTest = pkg;
    pkgDrv = builtins.unsafeDiscardStringContext pkg.drvPath;
    inherit variant salt;
    injected = if variant != "test" then "n/a (stock cacert)" else if injected then "yes (rebuilt with cacert + test root)" else "NO-OP (package does not take cacert)";
    cacertUsed = cacertUsed;
  }
  ''
    mkdir -p $out
    port=8443
    openssl s_server -accept "$port" -cert ${fx}/leaf.pem -key ${fx}/leaf.key -www -quiet \
      > $out/server.log 2>&1 &
    srv=$!
    for i in $(seq 1 100); do
      openssl s_client -connect 127.0.0.1:$port </dev/null >/dev/null 2>&1 && break
      sleep 0.1
    done
    url="https://localhost:$port/"
    # Controls: the server is reachable and only the test root makes it valid.
    if curl -sS --max-time 10 --cacert ${fx}/root.pem "$url" -o /dev/null 2>>$out/control.log; then
      echo CONNECTED > $out/control-testroot; else echo REFUSED > $out/control-testroot; fi
    crc=0; curl -sS --max-time 10 --cacert ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt "$url" -o /dev/null 2>>$out/control.log || crc=$?
    case $crc in 0) echo CONNECTED ;; 60) echo REFUSED ;; *) echo "ERROR(curl $crc)" ;; esac > $out/control-stock

    # The shim runs with a scrubbed environment: no SSL_CERT_FILE/NIX_SSL_CERT_FILE/..., and the
    # sandbox has no /etc/ssl, so the only trust a program has is what its package wires in.
    set +e
    env -i HOME="$TMPDIR" TMPDIR="$TMPDIR" PATH="$shimPath" \
      URL="$url" HOST=localhost PORT="$port" PKG="$pkgUnderTest" CACERT="$cacertUsed" \
      timeout 120 bash -eu "$shimScript" > $out/shim.log 2>&1
    rc=$?
    set -e
    kill $srv 2>/dev/null || true
    echo "$rc" > $out/rc
    # REFUSED only counts if the failure is a certificate-verification failure; anything else
    # (import error, connection refused, timeout, shim bug) is ERROR so it cannot pass as a
    # "refusal" in the matrix.
    if [ "$rc" = 0 ]; then echo CONNECTED > $out/result
    elif grep -Eiq 'certificate verify failed|CERTIFICATE_VERIFY_FAILED|unable to get local issuer|PKIX path|unable to find valid certification path|self[- ]signed certificate|unknown ca|certificate (is )?not trusted|untrusted|SSLHandshakeException|server certificate verification failed|x509: certificate signed by unknown authority' $out/shim.log
    then echo REFUSED > $out/result
    else echo ERROR > $out/result; fi
    {
      echo "attr=${attr}"
      echo "variant=$variant"
      echo "package=$pkgUnderTest"
      echo "package.drv=$pkgDrv"
      echo "injected=$injected"
      echo "cacert=$cacertUsed"
    } > $out/info
  ''
