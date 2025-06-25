# Minecraft launcher in nix (WIP)

Adoped from https://gist.github.com/eyJhb/623c723ddf068a1c8de26e1ca467f002

# Features

Support fabric loader
Supports mrpack mods (only fabric based)

# Usage

To run minecraft in the current directory

```sh
nix run github:loystonpais/nix-mc#packages.x86_64-linux.official.clients.\"1.16.1\"
```
