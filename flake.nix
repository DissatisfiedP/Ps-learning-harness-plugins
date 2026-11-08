{
  description = "P's Learning Harness plugin registry: plugin sources, packed and published by GitHub Actions";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      # The exact tools scripts/registry.sh runs, locally and in CI. Pinning
      # tar and gzip (flake.lock) is what makes a version's package bytes, and
      # so its sha256, the same on every run.
      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            nativeBuildInputs = with pkgs; [
              luau
              luau-lsp

              bash
              coreutils
              findutils
              gnutar
              gzip
              jq
              yq-go
              curl
              gh
              git
            ];
            LANG = "C.UTF-8";
            LC_ALL = "C.UTF-8";
          };
        }
      );
    };
}
