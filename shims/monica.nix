# Monica ships two vendored bundles; the fix symlinks both, and the shim needs both to connect.
# - stripe/stripe-php (Laravel Cashier, Monica's subscriptions): \Stripe\HttpClient\CurlClient sets
#   CURLOPT_CAINFO to Stripe::getCABundlePath(), data/ca-certificates.crt unless the caller sets one
#   (Monica does not). One GET through CurlClient::instance(), as in shims/invoiceplane.nix.
# - composer/ca-bundle: its only user is maxmind/web-service-common (GeoIP2 web service, reachable
#   through stevebauman/location's MaxMind driver when `web.enabled`), which hands
#   CaBundle::getSystemCaRootBundlePath() to curl as CURLOPT_CAINFO. That checks SSL_CERT_FILE,
#   SSL_CERT_DIR, openssl.cafile/capath and the usual system paths first; the sandbox has none of
#   them and the environment is scrubbed, so it falls back to res/cacert.pem, the file the fix
#   replaces (the realistic case of a host without a system store). One GET with that CAINFO.
# Exit 0 only if both GETs succeed.
{ pkg, pkgs, ... }:
{
  inputs = [ pkgs.php ];
  script = ''
    exec php -d display_errors=stderr -d "error_reporting=E_ALL & ~E_DEPRECATED" -r '
      require $argv[1] . "/vendor/autoload.php";
      $fail = 0;
      echo "stripe/stripe-php ", Composer\InstalledVersions::getPrettyVersion("stripe/stripe-php"), ": Stripe::getCABundlePath() -> ", realpath(\Stripe\Stripe::getCABundlePath()), "\n";
      try {
        list($body, $code) = \Stripe\HttpClient\CurlClient::instance()->request("get", $argv[2], [], [], false);
        echo "  CurlClient: status ", $code, "\n";
      } catch (\Throwable $e) {
        echo "  CurlClient: ", get_class($e), ": ", $e->getMessage(), "\n";
        $fail = 1;
      }
      $ca = \Composer\CaBundle\CaBundle::getSystemCaRootBundlePath();
      echo "composer/ca-bundle ", Composer\InstalledVersions::getPrettyVersion("composer/ca-bundle"), ": getSystemCaRootBundlePath() -> ", realpath($ca), "\n";
      echo "  (getBundledCaBundlePath() -> ", realpath(\Composer\CaBundle\CaBundle::getBundledCaBundlePath()), ")\n";
      $ch = curl_init($argv[2]);
      curl_setopt_array($ch, [CURLOPT_RETURNTRANSFER => true, CURLOPT_TIMEOUT => 10, CURLOPT_CAINFO => $ca]);
      if (curl_exec($ch) === false) {
        echo "  curl with that CAINFO: error ", curl_errno($ch), ": ", curl_error($ch), "\n";
        $fail = 1;
      } else {
        echo "  curl with that CAINFO: status ", curl_getinfo($ch, CURLINFO_RESPONSE_CODE), "\n";
      }
      exit($fail);
    ' -- "${pkg}" "$URL"
  '';
}
