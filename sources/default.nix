{lib, ...}: let
  inherit (lib.self) readJSON;
in {
  # Dictionary mapping minecraft assets to their SHA256 hashes
  # { "b6/b6b4755cb992e14700dd6bb9fe3d582751ac07ae" = "sha256-9Ck57K/qqdEd/2Iv11nhcrkhYhDaUuYRor/3AA7ImIA="; ... }
  asset-sha256 = readJSON ./asset-sha256.json;
}
