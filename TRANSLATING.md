# Translating AI-2 Gopher

AI-2 Gopher speaks these languages:

- English
- Spanish
- German

Anyone can add a language. You need a GitHub account and nothing else. There is no program to install and nothing to compile, and everything can be done in the GitHub web editor. It is one file of about 90 short texts, an afternoon of work.

The app follows your computer's language by itself. Whatever a language has not translated yet shows in English, so a language never breaks by being incomplete, and a partial translation is a welcome contribution.

## Before you start

1. Find your language's code, the two letters the system uses for it, such as `fr` for French, `pt` for Portuguese or `it` for Italian. For a regional variant use the full form, `pt_BR`.
2. Look at the [open pull requests](https://github.com/rafael-minuesa/AI-2-gopher/pulls) and [issues](https://github.com/rafael-minuesa/AI-2-gopher/issues) for your language, so two people do not translate the same thing. If you are starting, open an issue titled "Translation: <your language>" to say so.
3. Fork the repository. On https://github.com/rafael-minuesa/AI-2-gopher press **Fork** (top right). You work in your fork and cannot push to ours directly; that is normal.

## Translate the file

1. Open [`lib/l10n/app_es.arb`](https://github.com/rafael-minuesa/AI-2-gopher/blob/main/lib/l10n/app_es.arb) or [`lib/l10n/app_de.arb`](https://github.com/rafael-minuesa/AI-2-gopher/blob/main/lib/l10n/app_de.arb), whichever you read better, and copy all of it (the **Raw** button shows it as plain text). The English originals are in [`lib/l10n/app_en.arb`](https://github.com/rafael-minuesa/AI-2-gopher/blob/main/lib/l10n/app_en.arb), which also has notes for a few texts.
2. In your fork, go to `lib/l10n/`, press **Add file > Create new file**, name it `app_<code>.arb` (for example `app_fr.arb`) and paste.
3. In the second line change `"@@locale": "es"` to your code, `"@@locale": "fr"`.
4. Each line is `"name": "text"`. **Change only the text after the colon**, and never the name before it, which is how the app finds your text.

Rules for each text:

- **Keep every `{name}` in braces exactly as it is**, spelled the same, even though the word inside is English. The app puts a title, a number or a message there. You can move it within the sentence.
- **Counted texts have one form per number.** In `{count, plural, =1{1 minute ago} other{{count} minutes ago}}`, translate only the words inside `=1{...}` and `other{...}`. Keep `count, plural,` as it is. If your language has more forms for numbers, you can add `few{...}` or `many{...}`, and we can help in the pull request.
- **These are names and stay as they are:** AI-2, AI-2 Gopher, Gopher, Gopher Reader, and Gopher+.
- **"Open in Gopher app" stays in English.** It is the label of a button in the browser extension, which is in English for now.
- **Addresses and technical forms stay as they are:** `gopher://`, `127.0.0.1:7070`, `/7selector%09query`, HTTP and HTTPS.
- For words every desktop uses (Bookmarks, Clipboard), use the words your language's programs use.
- To mention a word in quotes, use your language's own quotation marks, as Spanish «...» and German „...“ do.

## Add your name

Add a row with your language to the Translations table in [`README.md`](https://github.com/rafael-minuesa/AI-2-gopher/blob/main/README.md), and add your language to the list at the top of this page.

## Open the pull request

Commit your changes to a new branch in your fork, with a message that says what it is ("French translation"), then press **Contribute > Open pull request**.

The checks run on your pull request by themselves. On your first pull request to this repository, GitHub holds them until a maintainer approves the run, which protects the project from code nobody has read; that happens when we first look at it. The check called **Check and package Linux** runs the translation tests, and if something needs fixing its log says what, for example:

```
app_fr.arb, the text "couldNotOpenUrl"
```

which means a `{name}` in that text differs from the English. Fix it in the same branch, and the pull request updates itself. You do not need a new one.

Then a maintainer reads it and may suggest wording. When it is merged, your translation goes into the next release and you are named in the [changelog](CHANGELOG.md). There is nothing else to register, because the app finds each language from its file.

## What is not in this file

The browser extension and the pages of the Saved web pages library, which the app's small background helper writes, are in English for now.

## Checking it on your own computer

Not needed, the checks do this for you. If you have the repository cloned and [Flutter](https://docs.flutter.dev/get-started/install) installed:

```
flutter test test/translations_test.dart
```

Questions go in your pull request or in an [issue](https://github.com/rafael-minuesa/AI-2-gopher/issues).
