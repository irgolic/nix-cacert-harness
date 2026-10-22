# n98-magerun2 vendors rmccue/requests 2.x, whose default `verify` option is
# Requests::$certificate_path, i.e. certificates/cacert.pem, the file the fix replaces.
# n98-magerun2's own calls (self-update, github:pr, DownloadHelper, the compatibility clients) all
# pass `'verify' => true`, which makes Requests leave CURLOPT_CAINFO unset, so libcurl uses its
# default store and the vendored file is not read. The file is only the library default, for any
# other code running on n98-magerun2's autoloader (dev:console, module commands) that calls Requests
# without `verify`. The shim prints the n98-magerun2-style call's outcome for information (the
# sandbox has no system store, so it refuses on both sides; only the cURL error number is printed so
# that the line cannot pass for the verdict's refusal), then does one GET with the library default.
# The exit code is that GET's.
{ pkg, pkgs, ... }:
{
  inputs = [ pkgs.php ];
  script = ''
    exec php -d display_errors=stderr -d "error_reporting=E_ALL & ~E_DEPRECATED" -r '
      require $argv[1] . "/share/php/n98-magerun2/vendor/autoload.php";
      echo "rmccue/requests ", Composer\InstalledVersions::getPrettyVersion("rmccue/requests"), ": get_certificate_path() -> ", realpath(WpOrg\Requests\Requests::get_certificate_path()), "\n";
      try {
        $r = WpOrg\Requests\Requests::get($argv[2], [], ["verify" => true, "timeout" => 10]);
        $s = "status " . $r->status_code;
      } catch (WpOrg\Requests\Exception $e) {
        $s = preg_match("/cURL error \\d+/", $e->getMessage(), $m) ? $m[0] : get_class($e);
      }
      echo "informational, n98-magerun2 style (verify => true, libcurl default store): ", $s, "\n";
      try {
        $r = WpOrg\Requests\Requests::get($argv[2], [], ["timeout" => 10]);
      } catch (WpOrg\Requests\Exception $e) {
        echo "library default (certificates/cacert.pem): ", $e->getMessage(), "\n";
        exit(1);
      }
      echo "library default (certificates/cacert.pem): status ", $r->status_code, "\n";
    ' -- "${pkg}" "$URL"
  '';
}
