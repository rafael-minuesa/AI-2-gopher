# AI-2 Gopher

A native Gopher browser with a consistent text interface, typed menus and documents, search, bookmarks, and browsing history.

Current native app version: **1.1.1+4**. See [CHANGELOG.md](CHANGELOG.md) for release changes.

**Gopher Reader extension 1.1.1** converts a loaded web page into a local text-and-links view in one click. With the Linux app installed, **Open in Gopher app** saves that copy and delivers it through actual Gopher. See [extension installation and usage](extension/README.md).

Testing on another computer? Use the [quick test guide](TESTING.md) for setup, expected results and a short report checklist.

## Install and use on Linux

The first validated build target is Linux x86-64. The package contains the application, Flutter runtime libraries, and assets; Flutter is not needed to run it. A graphical Linux desktop with GTK 3 is required. Builds use Flutter 3.32.7; portable compatibility across Linux distributions still needs validation.

Download `ai-2-gopher-<version>-linux-x86_64.tar.gz` from the [latest release](https://github.com/rafael-minuesa/AI-2-gopher/releases/latest), extract it, and either run `bundle/ai-2-gopher` directly or run:

```bash
./install.sh
```

The installer copies the complete bundle into your user data directory, adds AI-2 Gopher to the application menu, registers browser native messaging, and registers `gopher://` links when `xdg-mime` is available. It does not require administrator access. Use `./install.sh --no-register` to keep your existing default Gopher handler; browser integration still installs. Applications install under `${XDG_DATA_HOME:-$HOME/.local/share}/ai-2-gopher/<version>`.

Install the extension, convert a page, and choose **Open in Gopher app**. The app opens a local Gopher menu containing article text, full-page text, the original source, and numbered links. Other saved destinations stay in Gopher; unsaved web destinations open in the browser. This saves a snapshot of the loaded page, including content you can currently access, without fetching the site again. It does not automatically convert linked websites.

Use **Saved web pages** in the app toolbar to reopen or remove copies and **Stop serving** to stop the local server while keeping saved data. Copies live under `${XDG_DATA_HOME:-$HOME/.local/share}/gopher-reader/pages`, capped at 100 pages and 64 MiB. The companion serves only this library on `127.0.0.1:7070`, accessible to other local Gopher clients and local processes. It remains available after the browser or app closes; an enabled library restarts when the app opens. Opening the library or sending a new copy starts serving again. Nothing is published on your network or the internet. Port 7070 must be free.

The companion is a compiled executable bundled with the Linux package: no Dart, Flutter, Node, or Python installation is needed to run it. Linux integration is tested with Chromium and Firefox desktop. Sandboxed Snap/Flatpak browsers may require a native messaging portal or additional host installation; Windows/macOS integration remains future work. The standalone extension continues to work without the app.

Developers can also generate the package with the command below; the Linux CI workflow also uploads build artifacts.

Open the app and enter a Gopher URL or bare hostname. The starting screen includes example destinations. Text pages support selection, copying, and a working wrap toggle; menus provide directory, text, search, and web-link actions. Bookmark and history selections return you to Browse. Back, Forward, Reload, and Retry preserve the resource type and search query.

Standard URLs include the resource type immediately after the first slash:

```text
gopher://gopher.floodgap.com                 root menu
gopher://example.org/1/docs                  menu with selector /docs
gopher://example.org/0/readme.txt            text with selector /readme.txt
gopher://example.org/7search%09two%20words    search selector search, query two words
```

Selectors are opaque; the app does not guess parent directories. An explicit port is supported, including local servers. Gopher is a plain TCP protocol. Text responses use UTF-8, with Latin-1 fallback for legacy bytes; this fallback does not detect other legacy character sets.

## Translations

The app follows your computer's language, and shows English for anything not translated yet. It speaks English, Spanish and German so far, and adding a language takes one file and no tools. See [TRANSLATING.md](TRANSLATING.md).

| Language | Code | Translators |
|---|---|---|
| Español | `es` | [Rafael Minuesa](https://github.com/rafael-minuesa) |
| Deutsch | `de` | [ProWoos team](https://github.com/ProWoos-Devs) |

## Develop and test

Use Flutter **3.32.7**, the version recorded in `.flutter-version`, and its bundled Dart 3.8.1. The application's resolved dependencies are committed in `pubspec.lock`. Native platform build tools are also required; `flutter doctor` describes missing prerequisites.

```bash
git clone https://github.com/rafael-minuesa/AI-2-gopher.git
cd AI-2-gopher
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter run -d linux
```

The tests use a local Gopher fixture server rather than public servers. They cover URL round trips, protocol framing, text encoding, search requests, response bounds and deadlines, cancellation, typed navigation, stale responses, persistence recovery, and the search/bookmark/wrap UI.

Validated locally on 2026-10-09 with Flutter 3.32.7: 44 protocol, persistence, navigation and UI tests pass, analysis/formatting are clean, and Linux packaging and the web landing-page build succeed. Chromium 148 and Firefox 157 tests install the complete package in temporary XDG directories (including spaces and a percent sign), send actual native messages, read converted content over TCP Gopher, and verify second-page navigation in the existing app window. The library tests cover persistence, framing, removal, damaged data, size/input limits, stop/restart and error recovery. Extension dependencies audit clean. Other native platforms, signed stores and sandboxed browser portals remain unvalidated.

The app also accepts a Gopher URL as a native command-line argument:

```bash
./build/linux/x64/release/bundle/ai-2-gopher 'gopher://example.org/0/readme.txt'
```

## Build packages

```bash
dev-tools/package-linux.sh
```

This builds Linux in release mode and writes the complete archive and SHA-256 checksum into `dist/`. Set `FLUTTER_BIN` to select a particular SDK. Do not distribute the executable by itself: it requires the accompanying `lib/` and `data/` directories. `.github/workflows/checks.yml` checks formatting, analyzes, tests, builds, and uploads the Linux package without publishing a release.

Native runner projects are also present for Android, iOS, Windows, and macOS. Android has release network permission; macOS has outgoing-network sandbox entitlements. Their builds and OS link integration have not been validated in this Linux environment:

```bash
flutter build apk --release
flutter build ios --release
flutter build windows --release
flutter build macos --release
```

Use the appropriate host toolchain for each target. Android currently uses Flutter's generated development signing setup; configure release signing before public distribution. iOS and macOS distribution require their respective signing configuration.

The web target preserves the download landing page and GitHub Pages deployment. It does not browse Gopher: a browser client needs a separate HTTPS/WebSocket gateway transport for direct TCP resources. HTML conversion and the Linux native handoff are implemented in [extension/](extension/README.md) and [native/](native/README.md).

## Supported content

| Resource | Behavior |
| --- | --- |
| Type `1`: menu | Parsed list of typed links and information |
| Type `0`: text | Selectable document with protocol framing removed |
| Type `7`: search | Query dialog and navigable results; query preserved in URLs/history |
| Type `h`: external `URL:http(s)` link | Opens the system web browser |
| Type `h`: Gopher-hosted HTML | Displays HTML source as text |
| Information and error rows | Displayed without navigation |
| Binary, images, Telnet, and other types | Listed as unsupported for reading; no download UI |

Connections have a 30-second total deadline and an 8 MiB response limit. A new visit cancels the previous connection and ignores obsolete results. Saved-data failures leave browsing available; damaged JSON is preserved under recovery keys and valid entries remain usable.

## Layout

```text
lib/models/      Typed addresses and menu items
lib/services/    TCP client, navigation state, persistence
lib/screens/     Browse, bookmarks, history
lib/widgets/     Address, menu and text controls
test/            Protocol, state, storage and UI regression tests
dev-tools/       Linux packaging and user installation
```

Licensed under [MIT](LICENSE). Protocol references: [RFC 1436](https://www.rfc-editor.org/rfc/rfc1436) and [RFC 4266](https://www.rfc-editor.org/rfc/rfc4266).
