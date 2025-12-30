{
  description = "maze solver and visualizer in zig";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      treefmt-nix,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        project = "maze solver and visualizer";
      in
      {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "maze_solver";
          version = "0.1.0";
          src = ./.;

          zigBuildFlags = [ "-Doptimize=ReleaseFast" ];

          nativeBuildInputs = with pkgs; [
            zig.hook
            pkg-config
          ];

          buildInputs = with pkgs; [
            csfml
          ];
        };
        devShells.default = pkgs.mkShell {
          name = project;
          LSP_SERVER = "zls";
          packages = with pkgs; [
            zig
            zls

            lldb

            csfml

            pkg-config
            valgrind
            gdb
          ];
          shellHook = ''
            echo -e '(¬_¬") Entered ${project} :D'
          '';
        };
        formatter = treefmt-nix.lib.mkWrapper pkgs {
          projectRootFile = "flake.nix";
          programs = {
            nixfmt.enable = true;
            zig.enable = true;
          };
        };
      }
    );
}
