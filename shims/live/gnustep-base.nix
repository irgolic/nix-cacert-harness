# gnustep-base, for bin/ca-live-check only (shims/live/ is not picked up by ca-check's behavioral matrix).
# GSTLS (Source/GSTLS.m) takes its default CA file from the GSTLSCAFile user default, then
# GS_TLS_CA_FILE, then SSL_CERT_FILE, then GSTLS/ca-certificates.crt in the base library's
# resource bundle: the vendored file. Under ca-live-check's `env -i` none of the first three is set.
# Server verification is off by default in GNUstep (GSTLSVerifyServer / GS_TLS_VERIFY_S), so the
# shim turns it on with GS_TLS_VERIFY_S=YES; with it off, any chain connects.
# The probe is a small Objective-C program built against the side's gnustep-base (wrapped by
# wrapGNUstepAppsHook like any nixpkgs GNUstep app, so the bundle resolves). It prints the CA file
# GSTLS resolves, then does one NSURLConnection GET. A verification failure comes back as the
# NSError "TLS verification: remote certificate is not trusted."
{ pkg, pkgs, ... }:
let
  src = pkgs.writeText "ca-tls-probe-gnustep.m" ''
    #import <Foundation/Foundation.h>
    #include <stdio.h>

    int main(int argc, char **argv)
    {
      NSAutoreleasePool *pool = [NSAutoreleasePool new];
      NSBundle *b = [NSBundle bundleForClass: [NSObject class]];
      NSString *ca = [b pathForResource: @"ca-certificates" ofType: @"crt" inDirectory: @"GSTLS"];
      printf("GSTLS/ca-certificates.crt of gnustep-base: %s\n", ca ? [ca UTF8String] : "(none)");
      fflush(stdout);
      NSURL *u = [NSURL URLWithString: [NSString stringWithUTF8String: argv[1]]];
      NSURLRequest *r = [NSURLRequest requestWithURL: u
        cachePolicy: NSURLRequestReloadIgnoringCacheData timeoutInterval: 10];
      NSURLResponse *resp = nil;
      NSError *err = nil;
      NSData *d = [NSURLConnection sendSynchronousRequest: r returningResponse: &resp error: &err];
      if (d == nil)
        {
          printf("error: %s\n", [[err description] UTF8String]);
          return 1;
        }
      printf("status %ld\n", (long)[(NSHTTPURLResponse *)resp statusCode]);
      [pool release];
      return 0;
    }
  '';
  probe = pkgs.clangStdenv.mkDerivation {
    name = "ca-tls-probe-gnustep";
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.gnustep-make pkgs.wrapGNUstepAppsHook ];
    buildInputs = [ pkg pkgs.gnustep-libobjc ];
    buildPhase = ''
      cc -o probe ${src} $(gnustep-config --objc-flags) -I${pkg.dev}/include -L${pkg.lib}/lib -lgnustep-base -lobjc
    '';
    installPhase = "install -Dm755 probe $out/bin/ca-tls-probe-gnustep";
  };
in
{
  inputs = [ probe ];
  script = ''
    GS_TLS_VERIFY_S=YES ca-tls-probe-gnustep "$URL"
  '';
}
