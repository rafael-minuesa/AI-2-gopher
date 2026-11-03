# Distribution Guide for AI-2 Gopher

Current installation instructions, tested platform support, and SDK requirements are in [README.md](README.md). Linux releases include a user installer. Other platform release builds still require validation and signing before distribution.

## Quick Start: Android APK

### Build the APK
```bash
flutter build apk --release
```

The APK will be located at: `build/app/outputs/flutter-apk/app-release.apk`

### Share via GitHub Releases

1. Go to your repository on GitHub
2. Click "Releases" → "Create a new release"
3. Upload the `app-release.apk` file
4. Users can download and install directly on Android

### Installation for Users
1. Download the APK file
2. Enable "Install from Unknown Sources" in Android settings
3. Tap the APK to install

---

## Web Deployment (GitHub Pages)

### Build for Web
```bash
flutter build web --release
```

### Deploy to GitHub Pages
```bash
# Copy build output
mkdir -p docs
cp -r build/web/* docs/

# Commit and push
git add docs/
git commit -m "Deploy web version"
git push

# Enable GitHub Pages:
# Go to Settings → Pages → Source: main branch /docs folder
```

Your app will be live at: `https://yourusername.github.io/AI-2-gopher/`

---

## Desktop Builds

### Windows
```bash
flutter build windows --release
# Output: build/windows/runner/Release/
# Zip the Release folder and share
```

### macOS
```bash
flutter build macos --release
# Output: build/macos/Build/Products/Release/AI-2 Gopher.app
```

### Linux
```bash
dev-tools/package-linux.sh
# Output: dist/ai-2-gopher-<version>-linux-x86_64.tar.gz
# Includes the compiled companion and user installer; install.sh registers browser integration.
```

---

## Professional Distribution

### Google Play Store
1. Create a Google Play Console account ($25 one-time fee)
2. Build app bundle: `flutter build appbundle --release`
3. Upload to Play Console and fill in app details
4. Submit for review

### Apple App Store
1. Enroll in Apple Developer Program ($99/year)
2. Build iOS app: `flutter build ios --release`
3. Upload via App Store Connect
4. Submit for review

### Web Hosting Services
- **Netlify**: Drag and drop `build/web` folder
- **Vercel**: Connect GitHub repo, auto-deploy
- **Firebase Hosting**: `firebase deploy`

---

## Best Practice: GitHub Releases

Create releases for all platforms:

```bash
# Build all platforms
flutter build apk --release
flutter build web --release
# (build desktop platforms if on respective OS)

# Create release on GitHub with files:
# - app-release.apk (Android)
# - web-build.zip (Web version)
# - windows-build.zip (Windows)
# - linux-build.tar.gz (Linux)
```

Users can choose which version to download based on their platform.
