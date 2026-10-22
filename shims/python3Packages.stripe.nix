# stripe-python: stripe.ca_bundle_path is stripe/data/ca-certificates.crt, and every HTTP
# client it ships passes it explicitly (requests verify=, pycurl CAINFO, httpx/aiohttp cafile),
# so neither certifi nor the environment is consulted. The shim makes one API call
# (Balance.retrieve) against $URL with the default client. The test server answers with an
# HTML page, so a verified connection ends in an APIError carrying the HTTP status, which
# counts as connected; a certificate failure is an APIConnectionError.
{ pkg, ... }:
{
  inputs = [ (pkg.pythonModule.withPackages (_: [ pkg ])) ];
  script = ''
    exec python3 -I - "$URL" <<'PY'
    import os, sys
    import stripe
    print("stripe", stripe.VERSION, "ca_bundle_path =", stripe.ca_bundle_path, "->", os.path.realpath(stripe.ca_bundle_path), flush=True)
    stripe.api_base = sys.argv[1].rstrip("/")
    stripe.api_key = "sk_test_x"
    stripe.max_network_retries = 0
    stripe.default_http_client = stripe.new_default_http_client()
    print("http client", type(stripe.default_http_client).__name__, flush=True)
    try:
        stripe.Balance.retrieve()
    except stripe.APIError as e:
        if e.http_status is None:
            raise
        print("status", e.http_status, "(non-JSON body from the test server)")
    PY
  '';
}
