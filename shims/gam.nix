# gam: the vendored gam/cacerts.pem is the fallback when gam.cfg's cacerts_pem is empty.
# The nixpkgs wrapper sets GAM_CA_FILE, but gam reads that variable only when it *creates*
# gam.cfg (it becomes cacerts_pem there); an existing gam.cfg with an empty cacerts_pem, or
# running gam without the wrapper, uses $GAM_PATH/cacerts.pem. The shim runs the program the
# wrapper execs (bin/.gam-wrapped) with no GAM_CA_FILE (env -i) and a fresh GAMCFGDIR, so the
# new gam.cfg has `cacerts_pem =` and the vendored path decides.
# (At base 8915027df the wrapper itself exits 127 before reaching gam: its --run lines are
# quoted literally, e.g. `'export GAMCFGDIR=...'` runs as a command name.)
# Request: `gam user <u> create drivefile url <URL>` fetches the URL with gam's own httplib2
# object (getHttpObj: ca_certs = cacerts_pem) before it needs Google credentials;
# `config user_service_account_access_only true` skips the Directory API object that resolving
# `user <u>` would otherwise build first. The driver stops gam right after that fetch
# (sys.exit(0) after getMediaBody returns), because the next step contacts Google.
{ pkg, ... }:
{
  inputs = [ ];
  script = ''
    export GAMCFGDIR="$TMPDIR/gam"
    prog="$PKG/bin/.gam-wrapped"
    py=$(head -1 "$prog" | cut -c3-)
    exec "$py" - "$prog" "$URL" <<'PY'
    import os, sys
    prog, url = sys.argv[1], sys.argv[2]
    src = open(prog).read()
    exec(src[:src.index("from gam.__main__ import main")])  # the program's own sys.path setup
    import gam
    fetch = gam.getMediaBody
    def getMediaBody(parameters):
        ca = gam.GC.Values[gam.GC.CACERTS_PEM]
        print("cacerts_pem =", ca, "->", os.path.realpath(ca), flush=True)
        fetch(parameters)
        print("fetched", parameters[gam.DFA_URL], "content-type", parameters[gam.DFA_LOCALMIMETYPE], flush=True)
        sys.exit(0)
    gam.getMediaBody = getMediaBody
    from gam.__main__ import main
    sys.argv = ["gam", "config", "user_service_account_access_only", "true",
                "user", "nobody@example.com", "create", "drivefile", "url", url]
    sys.exit(main())
    PY
  '';
}
