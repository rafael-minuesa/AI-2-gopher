#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
flutter_bin="${FLUTTER_BIN:-flutter}"
"$flutter_bin" build linux --release
flutter_sdk="$(cd "$(dirname "$(readlink -f "$(command -v "$flutter_bin")")")/.." && pwd)"
"$flutter_sdk/bin/dart" compile exe native/companion.dart -o build/gopher_reader_companion
version="$(sed -n 's/^version: //p' pubspec.yaml)"
arch="$(uname -m)"
case "$arch" in
  x86_64) flutter_arch=x64 ;;
  aarch64) flutter_arch=arm64 ;;
  *) echo "Unsupported build architecture: $arch" >&2; exit 1 ;;
esac
bundle="build/linux/$flutter_arch/release/bundle"
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
package="ai-2-gopher-$version-linux-$arch"
mkdir -p "$staging/$package" dist
cp -a "$bundle" "$staging/$package/bundle"
cp build/gopher_reader_companion "$staging/$package/bundle/"
cp LICENSE "$staging/$package/"
cp dev-tools/install-linux.sh "$staging/$package/install.sh"
printf '%s\n' "$version" > "$staging/$package/VERSION"
tar -czf "dist/$package.tar.gz" -C "$staging" "$package"
(cd dist && sha256sum "$package.tar.gz" > "$package.tar.gz.sha256")
printf 'Package: %s/dist/%s.tar.gz\n' "$project_dir" "$package"
