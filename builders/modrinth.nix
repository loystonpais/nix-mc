{lib, ...} @ self: let
  inherit (lib.self) readJSON;
in {
  parseMrpack = {
    src,
    pkgs ? self.pkgs,
    runCommand ? pkgs.runCommand,
    unzip ? pkgs.unzip,
  }: let
    # Some zips have weird permissions,
    # so we need to fix them
    unpacked =
      runCommand "mrpack-unpacked" {
        buildInputs = [unzip];
      } ''
        unzip "${src}" -d $out
        find $out -type d -exec chmod 755 {} \;
        find $out -type f -exec chmod 644 {} \;
      '';

    index = readJSON "${unpacked}/modrinth.index.json";

    mcVersion = index.dependencies.minecraft;
    fabricLoaderVersion =
      if index.dependencies ? "fabric-loader"
      then index.dependencies.fabric-loader
      else null;
  in {
    inherit index;
    inherit (index) name versionId formatVersion;
    inherit mcVersion;
    inherit fabricLoaderVersion;
    __toString = self: self.src;
    src = unpacked;
  };
}
