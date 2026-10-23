# Probes shared by the behavioral cells (lib/behave.nix) and the live wrapper (lib/live.nix),
# built with the harness tools (the base nixpkgs), so they are cached across sides.
{ tools }:
{
  java = tools.runCommand "ca-tls-probe-java" { nativeBuildInputs = [ tools.jdk_headless ]; } ''
    mkdir -p $out
    cp ${../probes/TlsProbe.java} TlsProbe.java
    javac --release 8 -Xlint:-options -d $out TlsProbe.java
  '';
}
