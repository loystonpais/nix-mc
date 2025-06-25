# Fully ephemeral. Nothing is saved
{
  writeShellScriptBin,
  coreutils,
}:
writeShellScriptBin "ephemeral-instance-launch" ''
  set -euo pipefail

  TMP_DIR="$(${coreutils}/bin/mktemp -d -t mc-ephemeral-XXXXXX)"
  export MC_LAUNCH_DIR="$TMP_DIR"

  echo "Created temporary game directory at: $MC_LAUNCH_DIR"

  cleanup() {
    echo "Cleaning up temporary directory..."
    rm -rf "$TMP_DIR"
  }

  trap cleanup EXIT INT TERM

  cd "$MC_LAUNCH_DIR" || {
    echo "Failed to cd to $MC_LAUNCH_DIR"
    exit 1
  }

  echo "Launching Minecraft..."
  "$MC_COMMAND" "$@"
''
