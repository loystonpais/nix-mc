# Minecraft launcher in nix

Adoped from https://gist.github.com/eyJhb/623c723ddf068a1c8de26e1ca467f002

# Features

Added version manifest as a flake input

# Usage

Update version manifest by running `nix flake update version-manifest-v2`

# Usage 2

```nix
{
  inputs.url = "github:loystonpais/nix-minecraft-launcher";

  outputs = {
    nix-minecraft-launcher,
    ...
  }: {
    ...
  }
}
# Packages can be accessed using nix-minecraft-launcher.packages.${system}.clients.v1_16_1
```
