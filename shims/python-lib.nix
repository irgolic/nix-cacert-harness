# Generic shim for a Python library: import it in an interpreter that has only this
# package (and its deps), and do one HTTPS GET with it. Set `module` / `snippet` below
# by copying this file to shims/<attr>.nix, or use as-is for httplib2-like APIs.
{ pkg, ... }:
{
  inputs = [ (pkg.pythonModule.withPackages (_: [ pkg ])) ];
  script = ''
    exec python3 -I - "$URL" <<'PY'
    import sys, httplib2
    print("httplib2", httplib2.__version__, "CA_CERTS =", httplib2.CA_CERTS)
    resp, _ = httplib2.Http(timeout=10).request(sys.argv[1])
    print("status", resp.status)
    PY
  '';
}
