# WordPress: WP_Http pins the Requests library to wp-includes/certificates/ca-bundle.crt
# (class-wp-http.php: Requests::set_certificate_path(ABSPATH . WPINC . '/certificates/ca-bundle.crt')).
# Reproduce exactly that with the shipped Requests library and do one GET.
# Also works for the wordpress_* version attrs.
{ pkg, pkgs, ... }:
{
  inputs = [ pkgs.php ];
  script = ''
    exec php -d display_errors=stderr -r '
      $abspath = $argv[1] . "/share/wordpress/";
      require $abspath . "wp-includes/Requests/src/Autoload.php";
      WpOrg\Requests\Autoload::register();
      $bundle = $abspath . "wp-includes/certificates/ca-bundle.crt";
      WpOrg\Requests\Requests::set_certificate_path($bundle);
      echo "ca-bundle.crt -> ", realpath($bundle), "\n";
      $r = WpOrg\Requests\Requests::get($argv[2], [], ["verify" => $bundle, "timeout" => 10]);
      echo "status ", $r->status_code, "\n";
    ' -- "${pkg}" "$URL"
  '';
}
