**Gopher 1.1.0 — quick test guide**

Gopher Reader turns a loaded web page into distraction-free text and numbered links. The Linux app saves selected copies and reads them through actual Gopher at `127.0.0.1:7070`. Copies stay local; linked websites need their own conversion.

Allow 20 minutes. Full integration needs **Linux x86-64 with a GTK 3 desktop**, Chromium/Chrome 112+ or Firefox desktop 142+, and port 7070 free. No development tools are needed. Windows/macOS can test the standalone reader. Snap/Flatpak browser integration remains unvalidated.

**Setup**

Extract `gopher-test-kit-1.1.0-linux-x86_64.zip`: app **1.1.0+3**, extension **1.1.0**, guide and checksums. Packages come from successful GitHub checks for commit `12d340d`. Open a terminal there:

```bash
tar -xzf ai-2-gopher-<version>-linux-x86_64.tar.gz
cd ai-2-gopher-<version>-linux-x86_64
./install.sh
```

Run as your normal user, without sudo. This installs the app and browser integration; running the executable alone does not register the integration.

- **Chromium/Chrome:** extract `gopher-reader-1.1.0-chromium.zip` into a folder you will keep. Open `chrome://extensions`, enable Developer mode, choose **Load unpacked**, and select the folder containing `manifest.json`.
- **Firefox:** extract `gopher-reader-1.1.0-firefox.zip`. Open `about:debugging#/runtime/this-firefox`, choose **Load Temporary Add-on**, and select `manifest.json`. Reload the add-on after restarting Firefox; this package is unsigned.

Pin Gopher Reader. Open an ordinary web page and click its icon, or press **Alt+Shift+G**.

**Checks — mark Pass / Fail / Not tested**

| Check | Expected result |
| --- | --- |
| Reading copy | A new text tab opens; the original stays unchanged. Article, Full page and Links work. Structure remains readable; images become descriptions and form values are excluded. |
| Reader controls | Find, font size, wrap, appearance and Export text work. Save page bookmarks the source URL. Reload preserves the copy/settings. |
| Refresh and errors | Refresh captures source changes, but reports an error if the source tab moves elsewhere. Browser-controlled pages fail clearly. |
| Native handoff | Open in Gopher app opens a menu for article/full-page text and links. Another page uses the same app window; repeating one reader's handoff updates one saved copy. |
| Native navigation | Back, Forward, Reload, bookmarks and history return the correct page. Text selection and copying work. |
| Linked pages | Save A and its directly linked destination B; reload A's native menu. Matching saved links open locally; unsaved web links open in the browser. |
| Persistence | Close browser/app and reopen Saved web pages. Saved text works offline. Browser copies are temporary; native copies persist. |
| Library controls | Remove a copy: it leaves the library. Stop serving keeps copies; reopening the library restarts serving. |

Try an article and a documentation/list page. Optional: long pages, accented/RTL text, narrow windows, reinstalling while running, and the other browser. Shortening should be disclosed.

**Report back**

Send OS/distribution, architecture, desktop, browser version/installation method and results per row. For failures, include page URL, steps, exact error and screenshot. Note whether setup/navigation felt clear. For missing native connections, confirm `install.sh` ran and whether the browser uses Snap/Flatpak.
