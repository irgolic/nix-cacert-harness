# headphones: Headphones.py puts the bundled lib/ first on sys.path; headphones.request
# (request_response, used for all its HTTP) calls requests with verify=VERIFY_SSL_CERT, which
# is on by default, so the bundle is requests' default, lib/certifi/cacert.pem.
# The shim runs the interpreter of Headphones.py with the same sys.path and does one
# requests.get with verify=True (headphones.request itself needs an initialised CONFIG).
{ ... }:
{
  inputs = [ ];
  script = ''
    prog="$PKG/opt/headphones/Headphones.py"
    py=$(head -1 "$prog" | cut -c3-)
    exec "$py" -I - "$PKG/opt/headphones" "$URL" <<'PY'
    import os, sys
    root, url = sys.argv[1], sys.argv[2]
    sys.path.insert(0, os.path.join(root, "lib/"))
    import certifi, requests
    print("python", sys.executable, flush=True)
    print("requests", requests.__version__, "from", requests.__file__, flush=True)
    print("certifi.where() =", certifi.where(), "->", os.path.realpath(certifi.where()), flush=True)
    r = requests.get(url, timeout=10, verify=True)
    print("status", r.status_code)
    PY
  '';
}
