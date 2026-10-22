# ZoneMinder: the API (share/zoneminder/www/api) is a CakePHP 2.10 app. CakeSocket::_setSslContext
# (lib/Cake/Network/CakeSocket.php) sets the stream context's ssl `cafile` to
# CAKE . 'Config' . DS . 'cacert.pem', the file the fix replaces, whenever the caller gives none;
# HttpSocket (a CakeSocket) defaults to ssl_verify_peer => true and ssl_verify_host => true.
# ZoneMinder's own code never constructs HttpSocket, CakeSocket or CakeEmail. The one route from a
# ZoneMinder install to that socket is CakePHP's XML request-body parsing: every API controller
# loads RequestHandler (AppController::$components), whose convertXml() calls
# Xml::build($body, ['readFile' => false]), and Xml::build's test
# `$options['readFile'] && strpos($input, 'http://') === 0 || strpos($input, 'https://') === 0`
# fetches an https:// body anyway, with `new HttpSocket(['request' => ['redirect' => 10]])`.
# The shim loads the shipped CakePHP class loader (no app config, no database), prints what
# Xml::build makes of $URL as convertXml calls it (informational: it turns a TLS failure into
# "XML cannot be read."), then does one GET with an HttpSocket built exactly as Xml::build builds
# it. The exit code is that GET's; a refusal is CakeSocket's uncaught SocketException carrying
# PHP's OpenSSL "certificate verify failed".
# __d (CakePHP's translation function) is stubbed before basics.php, which only defines it when
# missing: the real one needs Configure and the I18n cache, i.e. the app's bootstrap.
{ pkg, pkgs, ... }:
{
  inputs = [ pkgs.php ];
  script = ''
    exec php -d display_errors=stderr -d "error_reporting=E_ALL & ~E_DEPRECATED" -r '
      define("DS", DIRECTORY_SEPARATOR);
      define("ROOT", $argv[1] . "/share/zoneminder/www/api");
      define("APP_DIR", "app");
      define("APP", ROOT . DS . APP_DIR . DS);
      define("APPLIBS", APP . "Lib" . DS);
      define("WWW_ROOT", APP . "webroot" . DS);
      define("CAKE_CORE_INCLUDE_PATH", ROOT . DS . "lib");
      define("CORE_PATH", CAKE_CORE_INCLUDE_PATH . DS);
      define("CAKE", CORE_PATH . "Cake" . DS);
      function __d($domain, $msg, $args = null) { return $msg; }
      require CAKE . "basics.php";
      require CAKE . "Core" . DS . "App.php";
      require CAKE . "Error" . DS . "exceptions.php";
      spl_autoload_register(array("App", "load"));
      App::uses("HttpSocket", "Network/Http");
      App::uses("Xml", "Utility");
      $v = file(CAKE . "VERSION.txt");
      $cafile = CAKE . "Config" . DS . "cacert.pem";
      echo "CakePHP ", trim(end($v)), "; Cake/Config/cacert.pem -> ", realpath($cafile), "\n";
      try {
        $x = "root <" . Xml::build($argv[2], array("readFile" => false))->getName() . ">";
      } catch (Exception $e) {
        $x = get_class($e) . ": " . $e->getMessage();
      }
      echo "Xml::build(URL, readFile=false): ", $x, "\n";
      $s = new HttpSocket(array("request" => array("redirect" => 10)));
      echo "HttpSocket ssl_verify_peer=", var_export($s->config["ssl_verify_peer"], true), "\n";
      try {
        $r = $s->get($argv[2]);
      } finally {
        echo "HttpSocket context cafile ", $s->config["context"]["ssl"]["cafile"], "\n";
      }
      echo "status ", $r->code, "\n";
      exit($r->isOk() ? 0 : 1);
    ' -- "${pkg}" "$URL"
  '';
}
