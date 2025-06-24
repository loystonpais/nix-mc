{...} @ self: let
  mkBuilders = {pkgs}: let
    self' =
      self
      // {
        inherit pkgs;
        inherit fetchers;
        inherit misc;
        inherit modrinth;
        inherit client;
      };
    fetchers = import ./fetchers.nix self';
    misc = import ./misc.nix self';
    modrinth = import ./modrinth.nix self';
    client = import ./client.nix self';
  in {
    inherit fetchers;
    inherit misc;
    inherit modrinth;
    inherit client;
  };
in {
  factories = {
    inherit mkBuilders;
  };
}
# {
#   manifest,
#   pkgs,
#   ...
# }: let
#   manifest' = readJSON manifest;
#   versions = builtins.listToAttrs (map (versionInfo: {
#       name = "v" + versionInfo.id;
#       value = client.mkMinecraftInstance {
#         minecraft = client.mkMinecraftFromVersionInfo {
#           inherit versionInfo;
#           inherit (pkgs) jre;
#           inherit pkgs;
#           minecraftDir = client.mkMinecraftDirFromVersionInfo {
#             inherit versionInfo;
#             system = "linux";
#             inherit (pkgs) runCommand;
#             inherit pkgs;
#           };
#         };
#         instanceName = "Speedrun Instance";
#         inherit pkgs;
#         icon = ../assets/icons/chicken.svg;
#       };
#     })
#     manifest'.versions);
# in
#   versions

