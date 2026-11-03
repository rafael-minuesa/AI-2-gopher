import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/widgets.dart' show basicLocaleListResolution;

import 'generated/app_localizations.dart';

export 'generated/app_localizations.dart' show AppLocalizations;

/// Replaces the system language, for tests.
Locale? localeOverride;

/// The system's language if there is a translation for it, otherwise English.
Locale get appLocale =>
    localeOverride ??
    basicLocaleListResolution(
      PlatformDispatcher.instance.locales,
      AppLocalizations.supportedLocales,
    );

/// The app follows the system language and has no setting of its own, so
/// every part of it, with or without a BuildContext, reads the same texts.
AppLocalizations get t => lookupAppLocalizations(appLocale);

/// Addresses are checked in code the companion shares, which cannot load
/// Flutter, so their messages arrive here in English.
String localizedAddressError(String english) => switch (english) {
  'Enter a valid Gopher host' => t.invalidHost,
  'Port must be between 1 and 65535' => t.invalidPort,
  'Selectors and queries cannot contain tabs or newlines' => t.noTabsOrNewlines,
  'Only search addresses can contain a query' => t.queryOnlyOnSearch,
  'Invalid Gopher URL: must start with gopher://' => t.mustStartWithGopher,
  'Encode selector characters such as ? and # in the URL' => t.encodeSelector,
  'Unknown Gopher item type' => t.unknownItemType,
  'Gopher+ requests are not supported' => t.gopherPlusUnsupported,
  _ => english,
};
