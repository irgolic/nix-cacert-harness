{
  description = "Before/after test harness for nixpkgs packages that vendor CA trust stores (NixOS/nixpkgs#576475)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAll (
        pkgs:
        let
          harness = pkgs.stdenvNoCC.mkDerivation {
            pname = "nix-cacert-harness";
            version = "0.1.0";
            src = self;
            nativeBuildInputs = [ pkgs.makeWrapper ];
            dontBuild = true;
            installPhase = ''
              runHook preInstall
              mkdir -p $out/libexec
              cp -r bin lib shims probes fixtures fixes README.md RESULTS.md $out/libexec/
              chmod +x $out/libexec/bin/*
              patchShebangs $out/libexec/bin
              mkdir -p $out/bin
              for tool in ca-check ca-static-check ca-behave-check ca-live-check nixb; do
                # nix and git are taken from the user's PATH on purpose (daemon/version match);
                # everything else is pinned here.
                makeWrapper $out/libexec/bin/$tool $out/bin/$tool \
                  --suffix PATH : ${
                    pkgs.lib.makeBinPath (
                      with pkgs;
                      [
                        bash
                        coreutils
                        gnugrep
                        gnused
                        gawk
                        findutils
                        diffutils
                        util-linux
                        jq
                        git
                        nix
                        curl
                      ]
                    )
                  }
              done
              runHook postInstall
            '';
            meta = {
              description = "Before/after test harness for nixpkgs packages that vendor CA trust stores";
              homepage = "https://github.com/irgolic/nix-cacert-harness";
              license = pkgs.lib.licenses.mit;
              mainProgram = "ca-check";
              platforms = systems;
            };
          };
        in
        {
          default = harness;
          nix-cacert-harness = harness;
        }
      );

      apps = forAll (pkgs: {
        default = {
          type = "app";
          program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/ca-check";
        };
        static = {
          type = "app";
          program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/ca-static-check";
        };
        behave = {
          type = "app";
          program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/ca-behave-check";
        };
        live = {
          type = "app";
          program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/ca-live-check";
        };
      });

      formatter = forAll (pkgs: pkgs.nixfmt);
    };
}
