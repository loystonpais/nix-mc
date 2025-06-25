{writeShellScriptBin}:
writeShellScriptBin "standard-instance-launch" ''
  set -euo pipefail
  export MC_LAUNCH_DIR="$HOME/.nix-mc/instances/$MC_INSTANCE_NAME"
  mkdir -p "$MC_LAUNCH_DIR" || {
    echo "Failed to create directory at $MC_LAUNCH_DIR"
    exit 1
  }
  cd "$MC_LAUNCH_DIR" || {
    echo "Failed to cd to $MC_LAUNCH_DIR"
    exit 1
  }
  exec "$MC_COMMAND" "$@"
''
