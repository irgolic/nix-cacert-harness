# bazarr: bazarr/app/libs.py (imported by bazarr.py before anything else) puts the bundled
# libs/ and custom_libs/ first on sys.path, so `requests` and `certifi` are the vendored copies
# and requests' default `verify` is libs/certifi/cacert.pem (certifi.where()). subliminal_patch
# (custom_libs/subliminal_patch/http.py) passes certifi.where() explicitly as well.
# The shim runs the interpreter that bin/bazarr execs, imports app.libs (the program's own
# sys.path setup) and does one requests.get with the default verify.
{ ... }:
{
  inputs = [ ];
  script = ''
    py=
    while read -r w1 w2 _; do
      if [ "$w1" = exec ]; then py=''${w2//\"/}; fi
    done < "$PKG/bin/bazarr"
    exec "$py" -I - "$PKG/lib/bazarr/bazarr" "$URL" <<'PY'
    import os, sys
    appdir, url = sys.argv[1], sys.argv[2]
    sys.path.insert(0, appdir)
    import app.libs
    import certifi, requests
    print("python", sys.executable, flush=True)
    print("requests", requests.__version__, "from", requests.__file__, flush=True)
    print("certifi.where() =", certifi.where(), "->", os.path.realpath(certifi.where()), flush=True)
    r = requests.get(url, timeout=10)
    print("status", r.status_code)
    PY
  '';
}
