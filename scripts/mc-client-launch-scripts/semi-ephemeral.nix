# Keeps everything, deletes only saves
# Symlinks screenshots to ~/Pictures
{writeShellScriptBin}:
writeShellScriptBin "ephemeral-instance-launch" ''
  set -euo pipefail

  INSTANCE_DIR="$HOME/.nix-minecraft-launcher/instances/$MC_INSTANCE_NAME"
  SAVE_DIR="$INSTANCE_DIR/saves"
  SCREENSHOTS_DIR="$INSTANCE_DIR/screenshots"
  PICTURES_TARGET="$HOME/Pictures"

  mkdir -p "$INSTANCE_DIR"
  mkdir -p "$PICTURES_TARGET"


  if [[ -e "$SCREENSHOTS_DIR" || -L "$SCREENSHOTS_DIR" ]]; then
    rm -rf "$SCREENSHOTS_DIR"
  fi
  ln -s "$PICTURES_TARGET" "$SCREENSHOTS_DIR"
  echo "Symlinked screenshots to: $PICTURES_TARGET"


  cleanup_saves() {
    if [[ -d "$SAVE_DIR" ]]; then
      echo "Cleaning up world saves..."
      rm -rf "$SAVE_DIR"/*
    else
      echo "No saves directory found to clean."
    fi
  }

  trap cleanup_saves EXIT INT TERM

  cd "$INSTANCE_DIR"

  "$MC_COMMAND" "$@"
''
