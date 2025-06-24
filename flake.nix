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
  } @ inputs: let
    lib = nixpkgs.lib.extend (final: prev: {
      self = self.lib final;
    });

    self' =
      self
      // {
        inherit lib;
        inherit sources;
        inherit builders;
      };

    sources = import ./sources self';
    builders = import ./builders self';

    inherit (lib.self) readJSON;
    inherit (builtins) listToAttrs map mapAttrs;

    manifest = readJSON version-manifest-v2;

    # Generate a normalized versions attr
    # { "1.16.1" = ...; "1.21.4" = ...; ... }
    versions = listToAttrs (map (versionInfo: {
        name = versionInfo.id;
        value = versionInfo;
      })
      manifest.versions);

    mkOfficialClientPerSystem = builders: system: pkgs: (
      id: versionInfo:
        builders.client.mkMinecraftFromVersionInfo {
          inherit versionInfo;
          inherit pkgs;
          minecraftDir = builders.client.mkMinecraftDirFromVersionInfo {
            inherit versionInfo;
            inherit system;
            inherit pkgs;
          };
        }
    );
  in
    flake-utils.lib.eachSystem ["x86_64-linux" "aarch64-linux"] (system: let
      pkgs = import nixpkgs {
        inherit system;
      };

      builders' = builders.factories.mkBuilders {
        inherit pkgs;
        inherit system;
      };

      officialClients = mapAttrs (mkOfficialClientPerSystem builders' system pkgs) versions;
    in {
      packages = {
        official = {
          clients =
            officialClients
            // {
              latestRelease = officialClients.${manifest.latest.release};
            };

          # servers = ...
        };
        unofficial = with builders'; rec {
          instances = {
            test = client.mkMinecraftInstance {
              addDesktopItem = false;
              minecraft = speedrunpack-1_16_1;
              instanceName = "Test speedrun pack instance";
            };
            test-ephemeral-instance = client.mkMinecraftInstance {
              addDesktopItem = false;
              launchScript = self.scripts.${system}.mc-client-launch-scripts.ephemeral;
              minecraft = speedrunpack-1_16_1;
              instanceName = "Ephemeral instance";
            };
          };
          speedrunpack-1_16_1 = let
            mrpack = modrinth.parseMrpack {
              src = pkgs.fetchurl {
                url = "https://cdn.modrinth.com/data/1uJaMUOm/versions/rycNlp7U/SpeedrunPack-mc1.16.1-v4.6.0.mrpack";
                hash = "sha256-xIL62QBD7qPTgiSYVI2ROaM0xjKMQ1K1gBVzZdI983Q=";
              };
            };
          in
            client.mkMinecraftFromMrpack {
              inherit mrpack;
              minecraft = officialClients.${mrpack.mcVersion};
              fabricLoader = fetchers.fetchFabricLoaderImpure {
                client = true;
                mcVersion = mrpack.mcVersion;
                loaderVersion = mrpack.fabricLoaderVersion;
                sha256Hash = "sha256-V/t1CtOxoX4huwJn89Jz+X+nK1Od6mmEOjC6A6eZjcA=";
              };
            };

          fabulously-optimized-1_16_5 = let
            mrpack = modrinth.parseMrpack {
              src = pkgs.fetchurl {
                url = "https://cdn.modrinth.com/data/1KVo5zza/versions/1.12.3/Fabulously%20Optimized-1.12.3.mrpack";
                hash = "sha256-jj9mOU2SoKf8aF6VEhj1UmUQDKmqPN+0jK8m10/qL8Q=";
              };
            };
          in
            client.mkMinecraftFromMrpack {
              inherit mrpack;
              minecraft = officialClients.${mrpack.mcVersion}.overrideAttrs {
                jre = pkgs.jre8;
              };
              fabricLoader = fetchers.fetchFabricLoaderImpure {
                client = true;
                mcVersion = mrpack.mcVersion;
                loaderVersion = mrpack.fabricLoaderVersion;
                sha256Hash = "sha256-/gAav/wOpefX5N+zOqTgjKoJNps2oQXhjaoA8mBLHU8=";
              };
            };

          simply-optimized-1_21 = let
            mrpack = modrinth.parseMrpack {
              src = pkgs.fetchurl {
                url = "https://cdn.modrinth.com/data/BYfVnHa7/versions/UAbWeR2g/Simply%20Optimized-1.21-1.0.mrpack";
                hash = "sha256-3e5Yp00ZEhrr+h/nTNJ1VHJ5RvkEjpCLIb9uJMYxbXQ=";
              };
            };
          in
            client.mkMinecraftFromMrpack {
              inherit mrpack;
              minecraft = officialClients."${mrpack.mcVersion}";
              fabricLoader = fetchers.fetchFabricLoaderImpure {
                client = true;
                mcVersion = mrpack.mcVersion;
                loaderVersion = mrpack.fabricLoaderVersion;
                sha256Hash = "sha256-yFrn4HiaWiBJOPccHpyK9RuiaUfCgjn0mOk+6tumjxc=";
              };
            };
        };
      };

      scripts = {
        mc-client-launch-scripts = {
          standard = pkgs.callPackage ./scripts/mc-client-launch-scripts/standard.nix {};
          ephemeral = pkgs.callPackage ./scripts/mc-client-launch-scripts/ephemeral.nix {};
        };
      };

      formatter = pkgs.alejandra;
    })
    // {
      inherit builders;
      inherit sources;

      lib = import ./lib;
    };
}
