# tautulli: Tautulli.py puts the bundled lib/ first on sys.path; plexpy's HTTPHandler (every
# request to Plex Media Server and plex.tv) passes verify=certifi.where(), i.e.
# lib/certifi/cacert.pem, and the websocket client uses it as ca_certs.
# The shim runs the interpreter of the wrapped Tautulli.py with the same sys.path and does one
# GET through plexpy.http_handler.HTTPHandler (explicit headers, so no config is needed). The
# handler logs request errors instead of raising, so its logger is sent to stdout.
{ ... }:
{
  inputs = [ ];
  script = ''
    prog="$PKG/libexec/tautulli/.Tautulli.py-wrapped"
    py=$(head -1 "$prog" | cut -c3-)
    exec "$py" -I - "$PKG/libexec/tautulli" "$URL" <<'PY'
    import logging, os, sys
    root, url = sys.argv[1], sys.argv[2]
    sys.path.insert(0, os.path.join(root, "lib"))
    sys.path.insert(1, root)
    import certifi, requests
    print("python", sys.executable, flush=True)
    print("requests", requests.__version__, "from", requests.__file__, flush=True)
    print("certifi.where() =", certifi.where(), "->", os.path.realpath(certifi.where()), flush=True)
    from plexpy import logger
    logger.logger.addHandler(logging.StreamHandler(sys.stdout))
    from plexpy.http_handler import HTTPHandler
    h = HTTPHandler(urls=url, headers={"Accept": "*/*"}, ssl_verify=True)
    print("ssl_verify =", h.ssl_verify, flush=True)
    r = h.make_request(uri="/", return_response=True)
    if r is None:
        sys.exit("request failed")
    print("status", r.status_code)
    PY
  '';
}
