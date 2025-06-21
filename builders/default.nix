{lib}: let
  inherit (lib) concatMapStringsSep hasSuffix;
  inherit (lib.self) readJSON;
  inherit (lib.self.manifest) mkAssetHashPath filterArtifacts;
  inherit (builtins) toJSON mapAttrs attrValues dirOf toFile;

  misc = {
    dummyTokenPath = {writeText}: writeText "minecraft-dummy-access-token" "dummytoken";
  };

  fetchers = {
    fetchAssetFromHash = {fetchSha1}: sha1:
      fetchSha1 {
        inherit sha1;
        url =
          "https://resources.download.minecraft.net/" + (mkAssetHashPath sha1);
      };

    fetchSha1 = {fetchurl}: {
      url,
      sha1,
      ...
    }:
      fetchurl {
        inherit url;
        inherit sha1;
      };
  };

  client = let
    validateVersionInfo = versionInfo: url: sha1:
      if versionInfo != null
      then versionInfo
      else if url != null && sha1 != null
      then {
        inherit url sha1;
      }
      else throw "You must provide either versionInfo or both url and sha1";

    validateSystem = system:
      if system == "linux" || (hasSuffix "-linux" system)
      then "linux"
      else throw "Only 'linux' is currently supported";
  in {
    # Builds a minecraft client
    # it combines a minecraftDir with a wrapper script
    # the minecraft dir will be placed in $out/share
    mkMinecraftFromVersionInfo = {
      jre,
      pkgs,
      minecraftDir,
      fetchSha1 ? fetchers.fetchSha1 {inherit (pkgs) fetchurl;},
      runCommand,
      makeWrapper,
      versionInfo ? null,
      url ? null,
      sha1 ? null,
      accessTokenPath ? misc.dummyTokenPath {inherit (pkgs) writeText;},
    }: let
      versionInfo' = validateVersionInfo versionInfo url sha1;

      versionData = readJSON (fetchSha1 versionInfo');

      libPath = lib.makeLibraryPath [
        pkgs.libpulseaudio
        pkgs.xorg.libXcursor
        pkgs.xorg.libXrandr
        pkgs.xorg.libXxf86vm # Needed only for versions <1.13
        pkgs.libGL
      ];
    in
      runCommand "minecraft-client-${versionData.id}" {
        version = versionData.id;
        buildInputs = [
          makeWrapper
        ];
      } ''
        mkdir -p $out/bin

        mkdir -p $out/share
        MINECRAFT_DIR=$out/share/minecraft
        ln -s ${minecraftDir} $MINECRAFT_DIR

        makeWrapper ${jre}/bin/java $out/bin/minecraft \
            --add-flags "\$JRE_OPTIONS" \
            --add-flags "-Djava.library.path='$MINECRAFT_DIR/natives'" \
            --add-flags "-cp '$(find $MINECRAFT_DIR/libraries -name '*.jar' | tr -s '\n' ':')'" \
            --add-flags "${versionData.mainClass}" \
            --add-flags "--version ${versionData.id}" \
            --add-flags "--assetsDir ${
          if versionData.assets == "legacy"
          then "$MINECRAFT_DIR/assets/virtual/legacy"
          else "$MINECRAFT_DIR/assets"
        }" \
            --add-flags "--assetIndex ${versionData.assets}" \
            --add-flags "--accessToken \"\$(cat ${accessTokenPath})\"" \
            --prefix LD_LIBRARY_PATH : "${libPath}"
      '';

    # A minecraft client dir contains
    # natives/
    # libraries/
    # assets/
    mkMinecraftDirFromVersionInfo = {
      system,
      pkgs,
      runCommand,
      fetchAssetFromHash ? fetchers.fetchAssetFromHash {inherit fetchSha1;},
      fetchSha1 ? fetchers.fetchSha1 {inherit (pkgs) fetchurl;},
      versionInfo ? null,
      url ? null,
      sha1 ? null,
    }: let
      versionInfo' = validateVersionInfo versionInfo url sha1;
      system' = validateSystem system;

      versionData = readJSON (fetchSha1 versionInfo');
      client = fetchSha1 versionData.downloads.client;

      artifacts = filterArtifacts system' versionData.libraries;

      # [ { src = ...; path = ...; } ...  ]
      librariesListWithPath = map (
        artif: {
          src = fetchSha1 artif.downloads.artifact;
          path = dirOf artif.downloads.artifact.path;
        }
      ) (lib.filter (x: !(x.downloads ? "classifiers")) artifacts);

      # Native libraries come zipped
      nativeLibrariesZippedList = map (
        artif: fetchSha1 artif.downloads.classifiers.${artif.natives.${system'}}
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
      runCommand "minecraft-client-dir-${versionData.id}" {
        buildInputs = with pkgs; [unzip];
      } (scripts.genMinecraftDir);
  };
in
  {
    manifest,
    pkgs,
    ...
  }: let
    manifest' = readJSON manifest;
    versions = builtins.listToAttrs (map (versionInfo: {
        name = "v" + versionInfo.id;
        value = client.mkMinecraftFromVersionInfo {
          inherit versionInfo;

          inherit (pkgs) runCommand makeWrapper jre;
          inherit pkgs;

          minecraftDir = client.mkMinecraftDirFromVersionInfo {
            inherit versionInfo;
            system = "linux";

            inherit (pkgs) runCommand;
            inherit pkgs;
          };
        };
      })
      manifest'.versions);
  in
    versions
