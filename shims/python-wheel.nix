# Like python-lib.nix, but for the wheel in the package's `dist` output instead of the
# installed package: pip installs that wheel offline (--no-index --no-deps) into a directory
# inside the sandbox, and a one-request snippet runs against it. The interpreter has pip and
# the package's Python dependencies, but not the package itself, so the import can only come
# from the wheel (checked before the snippet runs).
# Use: `--shim python-wheel` (ca-check / ca-behave-check) runs the httplib2 request below.
# For another library, write shims/python-wheel-<name>.nix as
#   args: import ./python-wheel.nix (args // { module = "<import name>"; snippet = "<python>"; })
# `snippet` runs after `import <module>`, with the URL in sys.argv[1] and `sys` imported;
# `prelude` runs before the import (see python-wheel-raven.nix).
# The default injection rebuilds the package with the test-root cacert, and the wheel with it.
{
  pkg,
  module ? "httplib2",
  prelude ? "",
  snippet ? ''
    print("CA_CERTS =", httplib2.CA_CERTS)
    resp, _ = httplib2.Http(timeout=10).request(sys.argv[1])
    print("status", resp.status)
  '',
  ...
}:
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
    ${prelude}
    import ${module}
    print("${module}", getattr(${module}, "__version__", getattr(${module}, "VERSION", "?")), "from", ${module}.__file__)
    if not ${module}.__file__.startswith(sys.argv[2] + "/"):
        sys.exit("${module} was not imported from the installed wheel")
    ${snippet}
    PY
  '';
}
