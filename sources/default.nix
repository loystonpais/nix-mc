{lib, ...}: let
  inherit (lib.self) readJSON;
in {
  asset-sha256 = readJSON ./asset-sha256.json;
}
