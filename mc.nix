{
  pkgs,
  lib ? pkgs.lib,
}: let
  inherit (lib) foldl' concatMapStringsSep;
  inherit (pkgs) fetchurl linkFarm symlinkJoin runCommand;
  inherit (builtins) readFile fromJSON toJSON mapAttrs attrValues concatStringSep dirOf toFile;

  readJSON = path: fromJSON (readFile path);

  mkClientJar = {src}: src;

  mkLibDir = {paths}: runCommand "libraries" {};

  mkNativeLibrary = {src}: src;

  fetchAssetFromHash = sha1:
    fetchSha1 {
      inherit sha1;
      url =
        "https://resources.download.minecraft.net/" + (mkAssetHashPath sha1);
    };

  mkAssetHashPath = sha1: (builtins.substring 0 2 sha1) + "/" + sha1;

  mkIsAllowed = {OS}: let
    isAllowed = artifact: let
      lemma1 = acc: rule:
        if rule.action == "allow"
        then
          if rule ? os
          then rule.os.name == OS
          else true
        else if rule ? os
        then rule.os.name != OS
        else false;
    in
      if artifact ? rules
      then foldl' lemma1 false artifact.rules
      else true;
  in
    isAllowed;

  fetchSha1 = {
    url,
    sha1,
    ...
  }:
    fetchurl {
      inherit url;
      inherit sha1;
    };

  mkMinecraftClientFromManifestVersion = {
    stdenv,
    versionInfo,
    OS,
  }: let
    versionData = readJSON (fetchSha1 versionInfo);
    client = fetchSha1 versionData.downloads.client;

    isAllowed = mkIsAllowed {inherit OS;};

    artifacts = lib.filter isAllowed versionData.libraries;

    libPath = lib.makeLibraryPath [
      pkgs.libpulseaudio
      pkgs.xorg.libXcursor
      pkgs.xorg.libXrandr
      pkgs.xorg.libXxf86vm # Needed only for versions <1.13
      pkgs.libGL
    ];

    # [ { src = ...; path = ...; } ...  ]
    librariesListWithPath = map (
      artif: {
        src = fetchSha1 artif.downloads.artifact;
        path = dirOf artif.downloads.artifact.path;
      }
    ) (lib.filter (x: !(x.downloads ? "classifiers")) artifacts);

    # Native libraries come zipped
    nativeLibrariesZippedList = map (
      artif: fetchSha1 artif.downloads.classifiers.${artif.natives.${OS}}
    ) (lib.filter (x: (x.downloads ? "classifiers")) artifacts);

    assetIndex = readJSON (fetchSha1 versionData.assetIndex);

    # [ { src = ...; path = ...; } ...  ]
    assetsWithPath = attrValues (mapAttrs (name: asset: {
        src = fetchAssetFromHash asset.hash;
        path =
          # goes within assets/
          if versionData.assets == "legacy"
          then "virtual/legacy/${name}"
          else "objects/${mkAssetHashPath asset.hash}";
      })
      assetIndex.objects);

    scripts = rec {
      genClient = ''
        mkdir -p $out/libraries
        ln -s ${client} $out/libraries/client.jar
      '';
      genLibDir =
        concatMapStringsSep "\n" (library: ''
          mkdir -p $out/libraries
          mkdir -p $out/libraries/${library.path}
          ln -s ${library.src} $out/libraries/${library.path}
        '')
        librariesListWithPath;
      genNativeLibDir =
        concatMapStringsSep "\n" (nativeLibrary: ''
          mkdir -p $out/natives
          unzip ${nativeLibrary} -d $out/natives && rm -rf $out/natives/META-INF
        '')
        nativeLibrariesZippedList;
      genAssetsDir =
        concatMapStringsSep "\n" (asset: ''
          mkdir -p $out/assets/${dirOf asset.path}
          ln -sf ${asset.src} $out/assets/${asset.path}
        '')
        assetsWithPath;
      genAssetIndex = ''
        mkdir -p $out/assets/indexes
        ln -s ${toFile "assets.json" (toJSON assetIndex)} $out/assets/indexes/${versionData.assets}.json
      '';

      # Finally put all the scripts together
      genMinecraftDir = ''
        ${genClient}
        ${genLibDir}
        ${genNativeLibDir}
        ${genAssetIndex}
        ${genAssetsDir}
      '';
    };
  in
    runCommand "minecraft-${versionData.id}" {
      buildInputs = with pkgs; [unzip];
    } (scripts.genMinecraftDir);

  mkMinecraftClient = {
    java,
    client,
    artifacts,
    mainClass,
    id,
    OS,
  }:
    true;
in
  {manifest, ...}: let
    manifest' = readJSON manifest;
    versions = builtins.listToAttrs (map (versionInfo: {
        name = "v" + versionInfo.id;
        value = mkMinecraftClientFromManifestVersion {
          inherit versionInfo;
          OS = "linux";
          stdenv = pkgs.stdenv;
        };
      })
      manifest'.versions);
  in
    versions
