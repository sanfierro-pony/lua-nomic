{
  description =
    "An implementation of nomic in lua based on capability security";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-22.11";
    luvitpkgs = {
      url = "github:aiverson/luvit-nix";
      # inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, luvitpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        # Workaround: put just the luacheck binary in as having the main package in buildInputs
        # seems to break lua requires for everything else in that dev shell
        luacheck-standalone = pkgs.runCommand "luacheck-standalone" { } ''
          mkdir -p $out/bin
          ln -s ${pkgs.luajitPackages.luacheck}/bin/luacheck $out/bin/luacheck
        '';
      in
      {
        packages = rec {
          hello = pkgs.hello;
          default = hello;
        };
        apps = rec {
          hello =
            flake-utils.lib.mkApp { drv = self.packages.${system}.hello; };
          default = hello;
        };
        checks = {
          tests = pkgs.runCommand "tests" {
            nativeBuildInputs = [
              luvitpkgs.packages.${system}.lit
              luvitpkgs.packages.${system}.luvit
            ];
          } ''
          set -euo pipefail
          for test in *-test.lua; do
            echo "Running test $test"
            luvit "$test"
          done
          mkdir $out
          '';
        };
        devShells = rec {
          nomic = pkgs.mkShell {
            buildInputs = [
              luvitpkgs.packages.${system}.lit
              luacheck-standalone
            ];
          };
          default = nomic;
        };
      });
}
