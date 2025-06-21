{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    flake-utils = {
      url = "github:numtide/flake-utils";
    };

    version-manifest-v2 = {
      url = "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json";
      flake = false;
    };
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
    version-manifest-v2,
  }: let
    lib = nixpkgs.lib.extend (final: prev: {
      self = self.lib final;
    });

    builders = import ./builders {
      inherit lib;
    };
  in
    flake-utils.lib.eachSystem ["x86_64-linux" "aarch64-linux"] (system: let
      pkgs = import nixpkgs {
        inherit system;
      };

      minecraft =
        import ./minecraft-launcher.nix
        {
          inherit pkgs;
          mcManifest = version-manifest-v2;
        };
      clients = builtins.mapAttrs (name: value: value.client) minecraft.versions;
      servers = builtins.mapAttrs (name: value: value.server) minecraft.versions;
    in {
      packages = {
        oldType = {
          inherit clients;
          inherit servers;
        };
        builders = builders {
          manifest = version-manifest-v2;
          pkgs = pkgs;
        };
      };

      formatter = pkgs.alejandra;
    })
    // {
      lib = import ./lib;
    };
}
