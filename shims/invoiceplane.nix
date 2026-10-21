# InvoicePlane: its Stripe gateway (application/modules/guest/controllers/gateways/Stripe.php)
# uses stripe-php's StripeClient, whose requests go through ApiRequestor to
# \Stripe\HttpClient\CurlClient::instance(). CurlClient sets CURLOPT_CAINFO to
# Stripe::getCABundlePath(): vendor/stripe/stripe-php/data/ca-certificates.crt unless the
# caller sets one (InvoicePlane does not). The shim does one GET through that client with
# the shipped autoloader. (ApiRequestor would then json_decode the reply, which the test
# server's HTML status page is not.) The fix's other file, application/config/cacert.pem, is
# not read by any PHP code in the package.
{ pkg, pkgs, ... }:
{
  inputs = [ pkgs.php ];
  script = ''
    exec php -d display_errors=stderr -r '
      require $argv[1] . "/vendor/autoload.php";
      $ca = \Stripe\Stripe::getCABundlePath();
      echo "stripe-php ", \Stripe\Stripe::VERSION, " CA bundle ", $ca, "\n";
      echo "  link: ", is_link($argv[1] . "/vendor/stripe/stripe-php/data/ca-certificates.crt") ? "symlink" : "file", "\n";
      list($body, $code, $headers) = \Stripe\HttpClient\CurlClient::instance()->request("get", $argv[2], [], [], false);
      echo "status ", $code, "\n";
    ' -- "${pkg}" "$URL"
  '';
}
