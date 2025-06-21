lib: rec {
  inherit (lib) foldl' concatMapStringsSep filter;
  inherit (builtins) readFile fromJSON toJSON mapAttrs attrValues concatStringSep dirOf toFile;

  readJSON = path: fromJSON (readFile path);

  manifest = rec {
    mkAssetHashPath = sha1: (builtins.substring 0 2 sha1) + "/" + sha1;

    isArtifactAllowed = OS: artifact: let
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

    filterArtifacts = OS: artifacts: filter (isArtifactAllowed OS) artifacts;
  };
}
