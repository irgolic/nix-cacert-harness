# Like python-lib.nix, but for the wheel in the package's `dist` output instead of the
# installed package: pip installs that wheel offline (--no-index --no-deps) into a directory
# inside the sandbox, and the same one-request snippet runs against it. The interpreter has
# pip and the package's Python dependencies, but not the package itself, so the import can
# only come from the wheel (the snippet also checks this).
# Use: `--shim python-wheel` (ca-check / ca-behave-check). For another library, copy this file
# and change the snippet, as for python-lib.nix.
# The default injection rebuilds the package with the test-root cacert, and the wheel with it.
{ pkg, ... }:
let
  python = pkg.pythonModule;
in
{
  inputs = [
    (python.withPackages (
      ps: [ ps.pip ] ++ builtins.filter ps.hasPythonModule pkg.requiredPythonModules
    ))
  ];
  script = ''
    echo "wheel: $(ls ${pkg.dist}/*.whl)"
    python3 -I -m pip install --quiet --no-index --no-deps --no-cache-dir \
      --disable-pip-version-check --target "$TMPDIR/wheel" ${pkg.dist}/*.whl
    exec python3 -I - "$URL" "$TMPDIR/wheel" <<'PY'
    import sys
    sys.path.insert(0, sys.argv[2])
    import httplib2
    print("httplib2", httplib2.__version__, "from", httplib2.__file__)
    print("CA_CERTS =", httplib2.CA_CERTS)
    if not httplib2.__file__.startswith(sys.argv[2] + "/"):
        sys.exit("httplib2 was not imported from the installed wheel")
    resp, _ = httplib2.Http(timeout=10).request(sys.argv[1])
    print("status", resp.status)
    PY
  '';
}
