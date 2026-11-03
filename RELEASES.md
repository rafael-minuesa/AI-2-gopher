# Release Guide

Current installation instructions, tested platform support, and SDK requirements are in [README.md](README.md). Linux releases include a user installer. Other platform release builds still require validation and signing before distribution.

This document explains how to create and publish releases for the AI-2 Gopher.

## Publishing a Release

Releases ship the Linux package that was tested, not a fresh rebuild. Tag pushes do not trigger a build.

1. Push the release commit. The "Check and package Linux" workflow uploads `ai-2-gopher-<version>-linux-x86_64.tar.gz` and its `.sha256` as build artifacts.
2. Test that package, for example with [TESTING.md](TESTING.md).
3. Create a draft release on that commit with the tested files, then publish it:
   ```bash
   gh release create v<version> --draft --target <commit> ai-2-gopher-<version>-linux-x86_64.tar.gz ai-2-gopher-<version>-linux-x86_64.tar.gz.sha256
   ```
   Publishing creates the tag.

### Multi-platform builds

The "Build Releases" workflow builds Android, Windows, macOS and Linux. It runs only when triggered manually, and creates no release. To run it:
1. Go to Actions tab on GitHub
2. Select "Build Releases" workflow
3. Click "Run workflow"

## Platform-Specific Builds

### Android

**Automated via GitHub Actions:**
- Builds release APK on every tag push
- Output: `app-release.apk`

**Manual build:**
```bash
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk
```

**Installation:**
- Users download the APK
- Enable "Install from Unknown Sources" on Android
- Tap the APK to install

**Publishing to Google Play:**
1. Build App Bundle:
   ```bash
   flutter build appbundle --release
   ```
2. Create a Google Play Console account ($25 one-time fee)
3. Upload the AAB file from `build/app/outputs/bundle/release/`
4. Fill in app details and screenshots
5. Submit for review

### Windows

**Automated via GitHub Actions:**
- Builds on Windows runner
- Output: `ai-2-gopher-windows-x64.zip`

**Manual build:**
```bash
flutter build windows --release
# Output: build/windows/x64/runner/Release/
```

**Distribution:**
- Users extract the ZIP and run the .exe file
- No installation required (portable app)

**Microsoft Store (Optional):**
- Requires Windows Developer account ($19/year)
- Package with MSIX
- Submit via Partner Center

### macOS

**Automated via GitHub Actions:**
- Builds on macOS runner
- Output: `ai-2-gopher-macos.zip`

**Manual build:**
```bash
flutter build macos --release
# Output: build/macos/Build/Products/Release/AI-2 Gopher.app
```

**Distribution:**
- Users extract the ZIP and drag the .app to Applications
- May need to allow the app in System Preferences > Security

**App Store (Optional):**
- Requires Apple Developer account ($99/year)
- Code signing required
- Submit via App Store Connect

### Linux

**Automated via GitHub Actions:**
- Builds on Ubuntu runner
- Output: `ai-2-gopher-<version>-linux-x86_64.tar.gz`

**Manual build:**
```bash
dev-tools/package-linux.sh
# Output: dist/ai-2-gopher-<version>-linux-x86_64.tar.gz, including the native companion
```

**Distribution:**
- Users extract the tarball and run `./install.sh` to install the complete app and browser native messaging host; direct bundle execution does not register browser integration.
- May need to install GTK dependencies:
  ```bash
  sudo apt-get install libgtk-3-0
  ```

**Package Managers (Optional):**
- **Snap Store:** Create a snapcraft.yaml
- **Flathub:** Create a Flatpak manifest
- **AppImage:** Package as AppImage for universal compatibility

### iOS

**Requirements:**
- macOS with Xcode
- Apple Developer account ($99/year)

**Manual build:**
```bash
flutter build ios --release
```

**Distribution:**
1. **TestFlight** (Beta testing):
   - Open Xcode
   - Archive the app
   - Upload to App Store Connect
   - Invite testers

2. **App Store:**
   - Build and archive in Xcode
   - Submit via App Store Connect
   - Fill in app details and screenshots
   - Wait for Apple review (typically 1-3 days)

**Note:** iOS builds are not included in the automated workflow because they require macOS, Xcode, and Apple Developer credentials.

## Version Management

### Updating Version Number

Edit `pubspec.yaml`:
```yaml
version: 1.0.1+2  # version+buildNumber
```

- First number (1.0.1): Version name shown to users
- Second number (+2): Build number (must increase with each release)

### Versioning Strategy

Follow [Semantic Versioning](https://semver.org/):
- **Major (1.0.0)**: Breaking changes
- **Minor (1.1.0)**: New features, backwards compatible
- **Patch (1.0.1)**: Bug fixes, backwards compatible

## Release Checklist

Before creating a release:

- [ ] Update version in `pubspec.yaml`
- [ ] Update CHANGELOG.md with release notes
- [ ] Test on at least one platform
- [ ] Commit all changes
- [ ] Create and push git tag
- [ ] Wait for GitHub Actions to complete
- [ ] Verify all artifacts in the release
- [ ] Test downloaded artifacts
- [ ] Update README.md if needed

## Download Statistics

You can view download statistics for your releases:
- Go to Insights → Traffic → Releases
- Or use GitHub API: `https://api.github.com/repos/rafael-minuesa/AI-2-gopher/releases`

## Troubleshooting

### Build Failures

**Android:**
- Check Java version (requires JDK 17)
- Verify gradle wrapper is correct
- Clear gradle cache: `./gradlew clean`

**Windows:**
- Ensure Visual Studio 2022 is installed
- Check Windows SDK is available

**macOS:**
- Verify Xcode Command Line Tools: `xcode-select --install`
- Check code signing settings

**Linux:**
- Install dependencies: GTK, pkg-config, ninja-build
- Verify DISPLAY environment variable

### Release Upload Failures

- Check GitHub token permissions
- Verify tag follows semantic versioning
- Ensure artifacts are generated correctly
- Check workflow logs in Actions tab

## Support

For issues with releases:
1. Check the [GitHub Actions logs](https://github.com/rafael-minuesa/AI-2-gopher/actions)
2. Review Flutter documentation
3. Open an issue on GitHub
