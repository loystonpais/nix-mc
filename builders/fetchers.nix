{
  lib,
  fetchers,
  sources,
  ...
} @ self: let
  inherit (lib.self) readJSON;
  inherit (lib.self.manifest) mkAssetHashPath;
  inherit (lib) escapeShellArg;
in {
  # This is a makeshift implementation of fetchFabricLoader
  # Should be avoided
  fetchFabricLoaderImpure = let
    fabricInstaller = builtins.fetchurl {
      url = "https://maven.fabricmc.net/net/fabricmc/fabric-installer/1.0.3/fabric-installer-1.0.3.jar";
      sha256 = "sha256:0zxhfk933wpxs0qyfnw33276lw5s7g4zqhr17ymbfagq3smq5aiq";
    };
  in
    {
      mcVersion,
      loaderVersion,
      sha256Hash,
      client ? true,
      server ? false,
      pkgs ? self.pkgs,
      jre ? pkgs.jre,
      runCommand ? pkgs.runCommand,
    }: let
      mode =
        if server == client
        then throw "client and server cannot be ${client} at the same time. Either one needs to be true"
        else if client
        then "client"
        else "server";
    in
      runCommand "fabric-loader-mc${mcVersion}-v${loaderVersion}" {
        buildInputs = [jre];
        outputHashAlgo = "sha256";
        outputHashMode = "recursive";
        outputHash = sha256Hash;
      } ''
        mkdir -p $out
        java -jar ${fabricInstaller} ${mode} \
          -dir $out \
          -mcversion ${escapeShellArg mcVersion} \
          -loader ${escapeShellArg loaderVersion} \
          -noprofile
        rm -rf $out/versions
      '';

  fetchAssetFromHash = {
    sha1,
    fetchSha1 ? fetchers.fetchSha1,
    assetSha256 ? sources.asset-sha256,
  }: let
    assetHashPath = mkAssetHashPath sha1;
    url =
      "https://resources.download.minecraft.net/" + assetHashPath;
    src =
      if assetSha256 ? "${assetHashPath}"
      then
        builtins.fetchurl {
          inherit url;
          sha256 = assetSha256."${assetHashPath}";
        }
      else
        fetchSha1 {
          inherit url;
          inherit sha1;
        };
  in
    src;

  fetchSha1 = {
    url,
    sha1,
    pkgs ? self.pkgs,
    fetchurl ? pkgs.fetchurl,
    ...
  }:
    fetchurl {
      inherit url;
      inherit sha1;
    };
}
