{
  lib,
  misc,
  system,
  fetchers,
  client,
  ...
} @ self: let
  inherit (lib) concatMapStringsSep hasSuffix makeLibraryPath;
  inherit (lib.strings) escapeShellArgs escapeShellArg;
  inherit (lib.self) readJSON;
  inherit (lib.self.manifest) mkAssetHashPath filterArtifacts;
  inherit (builtins) toJSON mapAttrs attrValues dirOf toFile elemAt;

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

  # TODO: Figure out if validating assetType is possible or not
  validateAssetType = assetType:
    if assetType == "legacy"
    then "legacy"
    else assetType;
in {
  # Builds a minecraft client
  # Puts minecraft dir at $out/share/minecraft
  # & creates a wrapper script.
  # Attributes can be overridden using overrideAttrs
  # ex: minecraft.overrideAttrs { id = "nixified" };
  mkMinecraft = {
    pkgs ? self.pkgs,
    jre ? pkgs.jre,
    stdenvNoCC ? pkgs.stdenvNoCC,
    makeWrapper ? pkgs.makeWrapper,
    libs ?
      with pkgs; [
        libpulseaudio
        xorg.libXcursor
        xorg.libXrandr
        xorg.libXxf86vm # Needed only for versions <1.13
        libGL
      ],
    mainClass,
    minecraftDir,
    extraMinecraftOptions ? [],
    extraJreOptions ? [],
    id,
    accessTokenPath ? misc.dummyTokenPath {inherit (pkgs) writeText;},
    assetType,
    preRunScript ? misc.doNothingScript {inherit (pkgs) writeScript;},
  } @ attrs: let
    assetType = validateAssetType attrs.assetType;
    libPath = makeLibraryPath libs;
  in
    stdenvNoCC.mkDerivation {
      name = "minecraft-client-${id}";
      version = id;

      # These are automatically set as environment variables
      # so that phase scripts can access them.
      # Makes overriding possible
      inherit id;
      inherit minecraftDir;
      inherit accessTokenPath;
      inherit assetType;
      inherit libPath;
      inherit mainClass;
      inherit jre;
      inherit preRunScript;
      gameDir = ".";
      extraJreOptions = escapeShellArgs extraJreOptions;
      extraMinecraftOptions = escapeShellArgs extraMinecraftOptions;

      buildInputs = [
        makeWrapper
      ];

      phases = ["installPhase"];

      installPhase = ''
        mkdir -p $out/bin

        mkdir -p $out/share
        DIR=$out/share/minecraft
        ln -s "$minecraftDir" $DIR

        if [ $assetType = "legacy" ]; then
          assetDir="$DIR/assets/virtual/legacy"
        else
          assetDir="$DIR/assets"
        fi

        makeWrapper $jre/bin/java $out/bin/minecraft \
            --run "$preRunScript" \
            --add-flags "$extraJreOptions" \
            --add-flags "\$JRE_OPTIONS_OVERRIDE" \
            --add-flags "-Djava.library.path='$DIR/natives'" \
            --add-flags "-cp '$(find $DIR/libraries -name '*.jar' | tr -s '\n' ':')'" \
            --add-flags "'$mainClass'" \
            --add-flags "--version '$id'" \
            --add-flags "--assetsDir '$assetDir'" \
            --add-flags "--assetIndex '$assetType'" \
            --add-flags "--accessToken \"\$(cat '$accessTokenPath')\"" \
            --add-flags "--gameDir '$gameDir'" \
            --add-flags "$extraMinecraftOptions" \
            --add-flags "\$MC_OPTIONS_OVERRIDE" \
            --prefix LD_LIBRARY_PATH : "$libPath"
      '';

      meta.mainProgram = "minecraft";
    };

  mkMinecraftFromVersionInfo = {
    pkgs ? self.pkgs,
    jre ? pkgs.jre,
    minecraftDir,
    fetchSha1 ? fetchers.fetchSha1,
    mkMinecraft ? client.mkMinecraft,
    versionInfo ? null,
    url ? null,
    sha1 ? null,
    accessTokenPath ? misc.dummyTokenPath {inherit (pkgs) writeText;},
  }: let
    versionInfo' = validateVersionInfo versionInfo url sha1;

    versionData = readJSON (fetchSha1 versionInfo');

    assetType = versionData.assets;
  in
    mkMinecraft {
      inherit minecraftDir;
      inherit (versionData) mainClass id;
      inherit assetType;
      inherit jre;
      inherit accessTokenPath;
    };

  # Wraps a minecraft client,
  # Adds .desktop
  # Sets game's working dir
  # can be put in environment.systemPackages
  # TODO: improve this function
  mkMinecraftInstance = {
    minecraft,
    instanceName,
    overrideMinecraftAttrs ? {},
    addDesktopItem ? true,
    addShellCommand ? true,
    desktopName ? instanceName,
    commandName ? instanceName,
    icon ? null,
    openInTerminal ? false,
    comment ? "Nixified Minecraft instance",
    launchBin ? self.scripts.${system}.mc-client-launch-scripts.standard,
    pkgs ? self.pkgs,
    makeWrapper ? pkgs.makeWrapper,
    makeDesktopItem ? pkgs.makeDesktopItem,
    writeShellScriptBin ? pkgs.writeShellScriptBin,
    writeShellScript ? pkgs.writeShellScript,
    symlinkJoin ? pkgs.symlinkJoin,
  } @ attrs: let
    minecraft = attrs.minecraft.overrideAttrs overrideMinecraftAttrs;

    commandName = lib.strings.sanitizeDerivationName (
      if attrs ? "commandName"
      then attrs.commandName
      else instanceName
    );

    icon =
      if addDesktopItem && (attrs ? "icon")
      then attrs.icon
      else throw "icon should be passed if addDesktopItem is set to true";

    shellCommand = writeShellScriptBin commandName ''
      export MC_COMMAND='${minecraft}/bin/minecraft'
      export MC_LAUNCH_SCRIPT='${lib.getExe launchBin}'
      export MC_INSTANCE_NAME='${instanceName}'

      exec "$MC_LAUNCH_SCRIPT" "$@"
    '';

    desktopItem = makeDesktopItem {
      name = "Minecraft ${instanceName}";
      exec = "${lib.getExe shellCommand}";
      desktopName = desktopName;
      icon = icon;
      comment = comment;
      categories = ["Game"];
      terminal = openInTerminal;
    };
  in
    symlinkJoin {
      name = "minecraft-instance-${instanceName}";
      paths = (lib.optional addShellCommand shellCommand) ++ (lib.optional addDesktopItem desktopItem);
      meta.mainProgram = commandName;
    };

  # TODO: write a generic minecraft dir builder
  # mkMinecraftDir = {  }

  # A minecraft client dir contains
  # natives/
  # libraries/
  # assets/
  mkMinecraftDirFromVersionInfo = {
    system,
    versionInfo ? null,
    url ? null,
    sha1 ? null,
    fetchAssetFromHash ? fetchers.fetchAssetFromHash,
    fetchSha1 ? fetchers.fetchSha1,
    pkgs ? self.pkgs,
    runCommand ? pkgs.runCommand,
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
        src = fetchAssetFromHash {sha1 = asset.hash;};
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

  # Builds a minecraft client with fabric loader
  # Takes in a minecraft client and then modifies it using overrideAttrs
  mkMinecraftModdedFabric = {
    minecraft,
    fabricLoader,
    pkgs ? self.pkgs,
    symlinkJoin ? pkgs.symlinkJoin,
  }:
    minecraft.overrideAttrs (final: prev: {
      name = "${prev.name}-modded-fabric-loader";
      mainClass = "net.fabricmc.loader.impl.launch.knot.KnotClient";
      # Combine minecraft dir and the mod loader dir
      minecraftDir = symlinkJoin {
        name = "minecraft-dir-with-fabric-loader";
        paths = [
          prev.minecraftDir
          fabricLoader
        ];
      };
    });

  # Builds minecraft client using a mrpack
  # Takes in a minecraft client.
  # When executed in a directory, the mods and overrides are placed automatically
  mkMinecraftFromMrpack = {
    mrpack,
    # minecraft (unmodded)
    minecraft,
    fabricLoader ? null,
    # TODO: validate fabric loader and minecraft versions and warn the user
    validateMinecraftVersion ? false,
    validateFabricLoaderVersion ? false,
    # TODO: implement includeOptionalMods
    includeOptionalMods ? true,
    pkgs ? self.pkgs,
    stdenvNoCC ? pkgs.stdenvNoCC,
    runCommand ? pkgs.runCommand,
    unzip ? pkgs.unzip,
    symlinkJoin ? pkgs.symlinkJoin,
    writeShellScript ? pkgs.writeShellScript,
    fetchurl ? pkgs.fetchurl,
    mkMincraft ? client.mkMinecraft,
    mkMinecraftModdedFabric ? client.mkMinecraftModdedFabric,
  }: let
    validateModrinthIndex = index:
      if index.formatVersion == 1
      then index
      else throw "Currently only supports format version 1";

    modrinthIndex = validateModrinthIndex mrpack.index;
    mrpackVersion = modrinthIndex.versionId;
    mrpackName = modrinthIndex.name;
    mrpackDependencies = modrinthIndex.dependencies;

    modLoader =
      if
        mrpackDependencies ? "fabric-loader"
        && (
          if fabricLoader != null
          then true
          else throw "Mrpack uses fabric-loader but it is not provided"
        )
      then {
        variant = "fabric-loader";
        version = mrpackDependencies.fabric-loader;
        minecraftModded = mkMinecraftModdedFabric {
          inherit minecraft;
          inherit fabricLoader;
          inherit pkgs;
        };
      }
      else throw "Only fabric-loader is currently supported";

    filesListWithPath =
      map (attr: {
        src = fetchurl {
          url = elemAt attr.downloads 0;
          sha1 = attr.hashes.sha1;
        };
        path = attr.path;
      })
      (lib.filter (attr: attr.env.client == "required") modrinthIndex.files);

    scripts = rec {
      # Place files (mods) in the dir where minecraft is executed
      placeFiles =
        concatMapStringsSep "\n" (file: ''
          mkdir -p "$gameDir/${dirOf file.path}"
          if ln -s "${file.src}" "$gameDir/${file.path}" 2>/dev/null; then
            echo "Linked: $gameDir/${file.path} → ${file.src}"
          elif [ -e "$gameDir/${file.path}" ]; then
            echo "Skipped: $gameDir/${file.path} (already exists)"
          else
            echo "Error: Failed to link $gameDir/${file.path}" >&2
            exit 1
          fi
        '')
        filesListWithPath;

      # mrpacks come with overrides with files to be placed in game dir
      # TODO: Improve this?
      mkPlaceOverridesForDir = dir: ''
        src="${mrpack}/${dir}"
        dst="$gameDir"

        if [ ! -d "$src" ]; then
          echo "No overrides directory found at $src, skipping"
          exit 0
        fi

        # Make sure prefix‐strip always has trailing slash
        src_slash="''${src%/}/"

        # Recursively create directories (skip the top‐level with -mindepth 1)
        find "$src" -mindepth 1 -type d | while read -r subdir; do
          rel="''${subdir#$src_slash}"
          target="$dst/$rel"
          mkdir -p "$target"
          chmod 755 "$target"
        done

        # Recursively copy files & symlinks if they don't already exist
        find "$src" -mindepth 1 \( -type f -o -type l \) | while read -r file; do
          rel="''${file#$src_slash}"
          target="$dst/$rel"
          if [ ! -e "$target" ]; then
            cp -a "$file" "$target"
            chmod 644 "$target"
            echo "Copied: $rel"
          else
            echo "Skipped: $rel (already exists)"
          fi
        done
      '';

      modrinthSetup = ''
        echo "Setting up mrpack..."
        echo "Placing files..."
        ${placeFiles}
        echo "Placing overrides..."
        ${mkPlaceOverridesForDir "overrides"}
        ${mkPlaceOverridesForDir "client-overrides"}
      '';
    };

    moddedMinecraftWithMrpackSetup = modLoader.minecraftModded.overrideAttrs (final: prev: {
      name = "${prev.name}-mrpack-${mrpackName}-${mrpackVersion}";
      preRunScript = writeShellScript "prerun-script-mrpack-${mrpackName}" ''
        ${prev.preRunScript}

        gameDir="${prev.gameDir}"
        ${scripts.modrinthSetup}
      '';
    });
  in
    moddedMinecraftWithMrpackSetup;
}
