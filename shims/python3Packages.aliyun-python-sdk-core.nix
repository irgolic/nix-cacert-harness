# aliyun-python-sdk-core: AcsClient sends every request through
# aliyunsdkcore.http.http_response.HttpResponse, which uses the SDK's vendored requests with
# verify = the client's verify, else ALIBABA_CLOUD_CA_BUNDLE, else True; True means the vendored
# requests' DEFAULT_CA_BUNDLE_PATH, aliyunsdkcore/vendored/requests/packages/certifi/cacert.pem.
# The shim does one HTTPS GET through HttpResponse with that default.
{ pkg, ... }:
{
  inputs = [ (pkg.pythonModule.withPackages (_: [ pkg ])) ];
  script = ''
    exec python3 -I - "$HOST" "$PORT" <<'PY'
    import os, sys
    from aliyunsdkcore.http import protocol_type
    from aliyunsdkcore.http.http_response import HttpResponse
    from aliyunsdkcore.vendored.requests import utils
    ca = utils.DEFAULT_CA_BUNDLE_PATH
    print("vendored requests DEFAULT_CA_BUNDLE_PATH =", ca, "->", os.path.realpath(ca), flush=True)
    r = HttpResponse(host=sys.argv[1], url="/", method="GET", protocol=protocol_type.HTTPS,
                     port=int(sys.argv[2]), read_timeout=10, connect_timeout=10)
    print("verify =", r.get_verify_value(), flush=True)
    status, headers, body = r.get_response_object()
    print("status", status)
    PY
  '';
}
