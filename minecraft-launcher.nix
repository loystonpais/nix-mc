{
  pkgs ? import <nixpkgs> {},
  lib ? pkgs.lib,
  OS ? "linux",
  mcManifest,
}:
with lib; let
  getJSON = data: builtins.fromJSON (builtins.readFile data);

  # builtins.fetchurl doesn'support 'sha1' hash. Which is strange, because it should
  # I've tried to overcome this with:
  # # fetchurlPath = builtins.toPath pkgs.nix + "/share/nix/corepkgs/fetchurl.nix";
  # # builtins_fetchurl = import fetchurlPath;
  # but looks like builtins.fetchurl wants some other kind of hash. So we stick with pkgs.fetchurl
  builtins_fetchurl = pkgs.fetchurl;

  buildMc = versionInfo: assetsIndex: let
    client = builtins_fetchurl {
      inherit (versionInfo.downloads.client) url sha1;
    };
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
    artifacts = lib.filter isAllowed versionInfo.libraries;

    libPath = lib.makeLibraryPath [
      pkgs.libpulseaudio
      pkgs.xorg.libXcursor
      pkgs.xorg.libXrandr
      pkgs.xorg.libXxf86vm # Needed only for versions <1.13
      pkgs.libGL
    ];
  in
    pkgs.runCommand "minecraft-client-${versionInfo.id}" {
      version = versionInfo.id;
      buildInputs = [
        pkgs.unzip
        pkgs.makeWrapper
      ];
    } ''
      mkdir -p $out/bin $out/assets/indexes $out/libraries $out/natives
      ln -s ${client} $out/libraries/client.jar
      # Java libraries
      ${concatMapStringsSep "\n" (artif: let
        library = builtins_fetchurl {
          inherit (artif.downloads.artifact) url sha1;
        };
      in ''
        mkdir -p $out/libraries/${builtins.dirOf artif.downloads.artifact.path}
        ln -s ${library} $out/libraries/${artif.downloads.artifact.path}
      '') (filter (x: !(x.downloads ? "classifiers")) artifacts)}
      # Native libraries
      ${concatMapStringsSep "\n" (artif: let
        library = builtins_fetchurl {
          inherit (artif.downloads.classifiers.${artif.natives.${OS}}) url sha1;
        };
      in ''
        unzip ${library} -d $out/natives && rm -rf $out/natives/META-INF
      '') (filter (x: (x.downloads ? "classifiers")) artifacts)}
      # assets
      ${concatStringsSep "\n" (builtins.attrValues (flip mapAttrs assetsIndex.objects (name: a: let
        asset = builtins_fetchurl {
          sha1 = a.hash;
          url = "https://resources.download.minecraft.net/" + hashTwo;
        };
        hashTwo = builtins.substring 0 2 a.hash + "/" + a.hash;
        outPath =
          if versionInfo.assets == "legacy"
          then "$out/assets/virtual/legacy/${name}"
          else "$out/assets/objects/${hashTwo}";
      in ''
        mkdir -p ${builtins.dirOf outPath}
        ln -sf ${asset} ${outPath}
      '')))}
      ln -s ${builtins.toFile "assets.json" (builtins.toJSON assetsIndex)} \
          $out/assets/indexes/${versionInfo.assets}.json
      # Launcher
      makeWrapper ${pkgs.jre}/bin/java $out/bin/minecraft \
          --add-flags "\$JRE_OPTIONS" \
          --add-flags "-Djava.library.path='$out/natives'" \
          --add-flags "-cp '$(find $out/libraries -name '*.jar' | tr -s '\n' ':')'" \
          --add-flags "${versionInfo.mainClass}" \
          --add-flags "--version ${versionInfo.id}" \
          --add-flags "--assetsDir ${
        if versionInfo.assets == "legacy"
        then "$out/assets/virtual/legacy"
        else "$out/assets"
      }" \
          --add-flags "--assetIndex ${versionInfo.assets}" \
          --add-flags "--accessToken foobarbaz" \
          --prefix LD_LIBRARY_PATH : "${libPath}"
    '';
  prepareMc = v: rec {
    versionDoc = v;
    versionInfo = getJSON (pkgs.fetchurl {
      url = versionDoc.url;
      sha1 = versionDoc.sha1;
    });
    assetsIndex = getJSON (pkgs.fetchurl {
      url = versionInfo.assetIndex.url;
      sha1 = versionInfo.assetIndex.sha1;
    });
    client = buildMc versionInfo assetsIndex;
    server = pkgs.fetchurl {
      url = versionInfo.downloads.server.url;
      sha1 = versionInfo.downloads.server.sha1;
    };
  };
in rec {
  manifest = getJSON mcManifest;
  versions = builtins.listToAttrs (map (x: {
      name = "v" + replaceStrings ["."] ["_"] x.id;
      value = prepareMc x;
    })
    manifest.versions);
}
