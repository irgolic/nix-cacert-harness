# Matomo: Piwik\Http::configCurlCertificate (core/Http.php) sets CURLOPT_CAINFO on every curl
# request (marketplace, GeoIP database downloads, update checks) to the `custom_cacert_pem` config
# value, which is empty by default, else to composer/ca-bundle's CaBundle::getBundledCaBundlePath(),
# i.e. vendor/composer/ca-bundle/res/cacert.pem, the file the fix replaces. That call does not look
# at any system store first. The shim loads the shipped autoloader and does one GET with a curl
# handle configured the same way (Matomo's Config, needed to read custom_cacert_pem, is not
# bootstrapped). getSystemCaRootBundlePath() (used by vendored maxmind/web-service-common) is printed
# for information: the sandbox has no /etc/ssl and the environment is scrubbed, so it falls back to
# the same bundled file.
{ pkg, pkgs, ... }:
{
  inputs = [ pkgs.php ];
  script = ''
    exec php -d display_errors=stderr -d "error_reporting=E_ALL & ~E_DEPRECATED" -r '
      $share = $argv[1] . "/share";
      require $share . "/vendor/autoload.php";
      $v = require $share . "/vendor/composer/installed.php";
      echo "composer/ca-bundle ", $v["versions"]["composer/ca-bundle"]["pretty_version"], "\n";
      $ca = Composer\CaBundle\CaBundle::getBundledCaBundlePath();
      echo "getBundledCaBundlePath() -> ", realpath($ca), "\n";
      echo "getSystemCaRootBundlePath() -> ", realpath(Composer\CaBundle\CaBundle::getSystemCaRootBundlePath()), " (informational)\n";
      $ch = curl_init($argv[2]);
      curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
      curl_setopt($ch, CURLOPT_TIMEOUT, 10);
      @curl_setopt($ch, CURLOPT_CAINFO, $ca);
      if (curl_exec($ch) === false) {
        echo "curl error ", curl_errno($ch), ": ", curl_error($ch), "\n";
        exit(1);
      }
      echo "status ", curl_getinfo($ch, CURLINFO_RESPONSE_CODE), "\n";
    ' -- "${pkg}" "$URL"
  '';
}
