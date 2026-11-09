# Changelog

## 1.6.1+10 - 2026-11-09

- While this computer works on a search, the app shows a still hourglass and one line of text, not a turning circle. The turning circle took about half a processor core away from the search. On a 2011 laptop with two cores a search of the Knowledge Packs is now readable about 2.5 seconds sooner, in about 3.2 seconds where it took 5.7. Waiting for another server looks as before.

## 1.6.0+9 - 2026-11-08

- The AI-2 chat page shows Search Knowledge Packs, offered by the AI-2 server, as a button with a book icon.
- A search of the Knowledge Packs on this computer says it is a new search, separate from your chat, with a Search button instead of Ask.
- A Knowledge Pack topic is called by its own name in its heading, History and Bookmarks, not by the link that opened it.

## 1.5.0+8 - 2026-11-05

- A- and A+ change the size of the text you read, in pages, the chat, Bookmarks and History, and the app remembers it. Ctrl and + or -, and Ctrl+0 for the normal size.
- Find on this page: the search button or Ctrl+F. Every match is marked and the current one brought into sight, with Enter and Shift+Enter or F3 and Shift+F3 to move between them, and Esc to close. It works on documents, menus and the chat, and ignores case and accents, except that ñ stays its own letter.
- Export text saves the page you are looking at, a document, a menu or the chat, as a new text file in your Downloads folder, and says where.
- A page saved from the browser has buttons for Article, Full page, Links and Original page, as in the extension's reader. It opens on the article, and other Gopher clients still get them as menu lines.

## 1.4.0+7 - 2026-11-04

- The AI-2 chat page has buttons for what the server offers: earlier conversations and deleting this one. The list of conversations is an ordinary Gopher menu, and choosing one reopens it on the chat page.
- Menus from this computer no longer show its address under each folder.

## 1.3.0+6 - 2026-11-04

- The AI-2 chat is one page: the whole conversation, with a box for the next question at the bottom instead of a popup. The box grows as you type, Enter sends and Shift+Enter starts a new line. The page follows the answer unless you scroll up to reread. While the model is silent, the dots after its "Processing" line count from one to three.
- A chat address opens that page directly, and choosing AI-2 Chat again while chatting only brings the window up. Back leaves the chat rather than stepping through its questions.

## 1.2.0+5 - 2026-11-03

- Show a menu or search reply as it arrives, instead of after the last line.
- A search on this computer, which may be a language model thinking, can stay silent for up to 15 minutes instead of failing after 30 seconds. Everything else keeps the 30-second limit.
- Add a Cancel button while a page loads. It returns to the previous page.
- The answer to a search on this computer is not asked again by Back, Forward or Reload, and stays out of History and Bookmarks.
- No progress animation once lines are showing, so it takes no processor time from a local model.
- A search item on this computer asks for "Your question" and has an Ask button, because it is answered rather than searched.
- The text of a menu or an answer can be selected and copied.
- If an answer breaks partway, the lines that arrived stay on screen with the error, Retry and Dismiss. An answer from this computer that ends without its last line now says it stopped instead of looking complete.
- The app is always dark, with the colors and monospace look of the browser extension's reader.
- The app is now AI-2 Gopher. The command is `ai-2-gopher`, the installer adds it to `~/.local/bin` and says so if that folder is not on your PATH, and the repository is AI-2-gopher. Bookmarks and history carry over.
- The app speaks Spanish and German as well as English, following the computer's language. Anyone can add a language with one file, see TRANSLATING.md. The browser extension and the pages inside Saved web pages are in English for now.

## Gopher Reader extension 1.1.1 - 2026-10-23

- Change the default shortcut from Alt+Shift+G to Alt+Shift+0. In Firefox on Linux and Windows, Alt+Shift+letter also triggers page access keys, and Wikipedia and other MediaWiki sites bind G to the Wikidata link, so the old shortcut left the page instead of opening the reader. MediaWiki uses every other letter except A, which Chrome reserves; no digit is used by MediaWiki, Chrome or Firefox. Users can change it in the browser's extension shortcut settings.

## 1.1.1+4 — 2026-10-16

- Accept the Chrome Web Store extension ID `fcpicpdmbmnfhijbaoibfdkdeainkmoa` for Open in Gopher app. The unpacked Chromium build now uses the store's public key, so store and unpacked installs share this ID. App 1.1.0+3 accepts only the previous development ID and does not connect to the store extension.
- Release builds are no longer published automatically from tag pushes; releases ship the tested Linux package.

## 1.1.0+3 / Gopher Reader extension 1.1.0 — 2026-10-09

- Add Open in Gopher app: send an explicitly selected reading copy through browser native messaging into a persistent local library.
- Bundle a compiled Linux companion with browser host registration and a loopback Gopher server on port 7070; serve article/full-page text and typed page menus with numbered links.
- Resolve links to other saved copies locally; preserve external web/Gopher destinations without fetching or automatically converting them.
- Add the native app's Saved web pages library, removal controls, serving stop/restart, and existing-window navigation on Linux.
- Bound and validate the handoff and stored data; preserve damaged files, prevent duplicate saves of a reader snapshot, and keep stable local addresses across restarts.
- Add protocol/persistence regression tests and real Chromium/Firefox package installation, native messaging, TCP and app navigation checks.

Linux desktop integration is the first supported target. Other native platforms, sandboxed browser portal setup, public hosting, and signed/store extension releases remain later work.

Validated locally: 44 Flutter tests, 18 extraction/background cases, clean analysis/formatting, Linux and web builds, complete installed-package handoffs in actual Chromium and Firefox, compiled-host malformed-frame/caller checks, package checksums and a clean dependency audit. Mozilla's linter retains the two existing warnings in bundled Readability; no errors.

## Gopher Reader extension 1.0.0 — 2026-10-08

- Add one-click local HTML conversion for Chromium and Firefox desktop, with Article, Full page, and numbered Links views.
- Preserve headings, lists, code, tables, language/direction, and image descriptions; exclude scripts, hidden content, editable regions, and form values.
- Add find, font size, wrapping, appearance, local bookmarks, UTF-8 text export, and explicit source-tab refresh.
- Keep reading bodies in bounded session storage, preserve them across worker restarts, and remove them when reader tabs close. Persist only settings and explicit bookmark metadata.
- Package separate browser manifests with bundled Mozilla Readability, generated icons, checksums, instructions, and browser CI checks.
- Verify actual shortcut activation and reader controls in Chromium and Firefox, plus extraction and background-state regression cases.

The extension has a separate version; the native app remains at `1.0.1+2`. Store publication, signing, continuous conversion across sites, and the native companion are later phases.

## 1.0.1+2 — 2026-10-08

- Fix compile errors and parse standard Gopher URLs with resource types, escaped selectors, and search queries.
- Preserve menu, text, and search navigation through Back, Forward, bookmarks, history, Reload, and Retry.
- Implement search and word wrap; open HTTP/HTTPS menu links in the system browser.
- Bound responses, apply connection/response deadlines, cancel obsolete requests, and handle text framing and legacy encoding.
- Recover valid saved entries from damaged JSON while preserving the original data; keep reading available when persistence fails.
- Add native platform runners, network permissions, dependency locking, a pinned Flutter SDK, and Linux build checks.
- Preserve the upstream web download page and deployment workflows; update their Flutter SDK, web bootstrap, and release package paths.
- Package the complete Linux app with a user installer and Gopher link registration.
- Add 32 protocol, navigation, persistence, and UI regression tests, plus installation and architecture documentation.

Validated with Flutter 3.32.7: tests, analysis, formatting, Linux release build, a temporary installation launched against a local Gopher server, and a local browser check of the web download page. Other native platforms and the CI workflow remain unverified. The browser extension is a proposed next phase.

## 1.0.0+1

- Initial Flutter client prototype.
