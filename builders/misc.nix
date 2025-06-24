{...} @ self: {
  dummyTokenPath = {
    pkgs ? self.pkgs,
    writeText ? pkgs.writeText,
  }:
    writeText "minecraft-dummy-access-token" "dummytoken";

  doNothingScript = {
    pkgs ? self.pkgs,
    writeScript ? pkgs.writeScript,
  }:
    writeScript "does-nothing-ignore-this" '''';
}
