#!/usr/bin/env bash
# Run from an extracted Linux package. Installs for the current user only.
set -euo pipefail
case "${1:-}" in
  '') register=1 ;;
  --no-register) register=0 ;;
  *) echo 'Usage: ./install.sh [--no-register]' >&2; exit 1 ;;
esac
source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
version="$(cat "$source_dir/VERSION")"
case "$version" in
  ''|*[!a-zA-Z0-9._+-]*) echo 'Invalid package version' >&2; exit 1 ;;
esac
[[ -x "$source_dir/bundle/ai-2-gopher" ]] || { echo 'Missing application bundle' >&2; exit 1; }
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
case "$data_home" in
  /*) ;;
  *) echo 'XDG_DATA_HOME must be an absolute path' >&2; exit 1 ;;
esac
bin_home="${XDG_BIN_HOME:-$HOME/.local/bin}"
case "$bin_home" in
  /*) ;;
  *) echo 'XDG_BIN_HOME must be an absolute path' >&2; exit 1 ;;
esac
case "$data_home$bin_home" in
  *$'\n'*|*$'\r'*) echo 'Installation paths cannot contain newlines' >&2; exit 1 ;;
esac
app_dir="$data_home/ai-2-gopher/$version"
mkdir -p "$app_dir" "$data_home/applications"
# Reinstalling must replace mapped executables, not truncate a running binary.
cp -a --remove-destination "$source_dir/bundle/." "$app_dir/"
[[ -x "$app_dir/gopher_reader_companion" ]] || { echo 'Missing native companion; extract the complete package' >&2; exit 1; }
"$app_dir/gopher_reader_companion" --install-browser-hosts
# Desktop Exec entries have their own quoting and percent field syntax.
executable="$(printf '%s' "$app_dir/ai-2-gopher" | sed 's/[\\"`$]/\\&/g; s/%/%%/g')"
cat > "$data_home/applications/org.gopherclient.gopher_flutter_client.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=AI-2 Gopher
Comment=Read Gopher menus and text documents
Comment[es]=Lee menús y documentos de texto de Gopher
Comment[de]=Gopher-Menüs und Textdokumente lesen
Exec="$executable" %u
Terminal=false
Categories=Network;
MimeType=x-scheme-handler/gopher;
StartupWMClass=org.gopherclient.gopher_flutter_client
DESKTOP
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$data_home/applications"
fi
if [[ "$register" == 1 ]] && command -v xdg-mime >/dev/null 2>&1; then
  xdg-mime default org.gopherclient.gopher_flutter_client.desktop x-scheme-handler/gopher
fi
# The short command. A file of someone else's under that name stays.
mkdir -p "$bin_home"
if [[ -e "$bin_home/ai-2-gopher" && ! -L "$bin_home/ai-2-gopher" ]]; then
  printf 'Left %s as it is; the app is at %s\n' "$bin_home/ai-2-gopher" "$app_dir/ai-2-gopher"
else
  ln -sfn "$app_dir/ai-2-gopher" "$bin_home/ai-2-gopher"
  case ":${PATH:-}:" in
    *":$bin_home:"*) ;;
    *) printf 'To run ai-2-gopher by name, add %s to your PATH. The application menu works without it.\n' "$bin_home" ;;
  esac
fi
printf 'Installed AI-2 Gopher in %s\n' "$app_dir"
