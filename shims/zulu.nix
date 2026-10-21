# zulu: pkgs/development/compilers/zulu/<ver>.nix declares only { callPackage, enableJavaFX, ... }
# and forwards the rest to common.nix, which takes `cacert`. The default injection looks at
# declared arguments and so sees no `cacert`; pass it through `override` explicitly.
{ pkg, probes, ... }:
{
  inputs = [ pkg ];
  inject = p: c: p.override { cacert = c; };
  script = ''
    java -cp ${probes.java} TlsProbe "$URL"
  '';
}
