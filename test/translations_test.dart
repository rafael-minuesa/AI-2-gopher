import 'dart:convert';
import 'dart:io';

import 'package:ai_2_gopher/l10n/l10n.dart';
import 'package:ai_2_gopher/screens/home_screen.dart';
import 'package:ai_2_gopher/services/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// These languages ship complete. Any other may be partial, and shows English
/// for whatever it has not translated yet.
const complete = {'es', 'de'};

Map<String, dynamic> read(File file) =>
    json.decode(file.readAsStringSync()) as Map<String, dynamic>;

Set<String> placeholders(String text) =>
    RegExp(r'\{(\w+)[,}]').allMatches(text).map((m) => m[1]!).toSet();

void main() {
  final files = Directory(
    'lib/l10n',
  ).listSync().whereType<File>().where((f) => f.path.endsWith('.arb')).toList();
  final english = read(File('lib/l10n/app_en.arb'));
  final keys = english.keys.where((k) => !k.startsWith('@')).toSet();

  tearDown(() => localeOverride = null);

  for (final file in files) {
    final name = file.uri.pathSegments.last;
    final code = RegExp(r'^app_(\w+)\.arb$').firstMatch(name)?[1];

    group(name, () {
      test('is named like app_<code>.arb and says the same code inside', () {
        expect(code, isNotNull, reason: 'Name it app_<code>.arb');
        expect(read(file)['@@locale'], code);
      });

      test('Flutter has its own texts for this language', () {
        final language = code!.split('_').first;
        expect(
          kMaterialSupportedLanguages,
          contains(language),
          reason: 'Buttons built into Flutter have no $language translation',
        );
      });

      test('has only texts the English file has', () {
        final extra = read(
          file,
        ).keys.where((k) => !k.startsWith('@')).toSet().difference(keys);
        expect(extra, isEmpty, reason: 'Not in app_en.arb, check the spelling');
      });

      test('keeps every {name} of the English text', () {
        read(file).forEach((key, value) {
          if (key.startsWith('@')) return;
          expect(
            placeholders(value as String),
            placeholders(english[key] as String),
            reason: '$name, the text "$key"',
          );
        });
      });

      test('leaves no text empty', () {
        read(file).forEach((key, value) {
          if (key.startsWith('@')) return;
          expect((value as String).trim(), isNotEmpty, reason: key);
        });
      });

      if (complete.contains(code)) {
        test('has every text', () {
          expect(keys.difference(read(file).keys.toSet()), isEmpty);
        });
      }
    });
  }

  group('choosing the language', () {
    Locale resolve(List<Locale> system) =>
        basicLocaleListResolution(system, AppLocalizations.supportedLocales);

    test('regional forms find their language', () {
      expect(resolve(const [Locale('es', 'ES')]).languageCode, 'es');
      expect(resolve(const [Locale('es', 'MX')]).languageCode, 'es');
      expect(resolve(const [Locale('de', 'AT')]).languageCode, 'de');
    });

    test('a language without a translation gets English, not German', () {
      expect(resolve(const [Locale('xh')]).languageCode, 'en');
      expect(resolve(const []).languageCode, 'en');
    });
  });

  group('in Spanish', () {
    setUp(() {
      localeOverride = const Locale('es');
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('the app shows its own words and Flutter\'s', (tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppState(),
          child: MaterialApp(
            locale: appLocale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Navegar'), findsOneWidget);
      expect(find.text('Marcadores'), findsOneWidget);
      expect(find.text('Browse'), findsNothing);
      final context = tester.element(find.byType(HomeScreen));
      expect(MaterialLocalizations.of(context).copyButtonLabel, 'Copiar');
    });

    test('a mistyped address is explained in Spanish', () async {
      SharedPreferences.setMockInitialValues({});
      final expected = {
        'http://example.org': t.mustStartWithGopher,
        'gopher://example.org/1a?b': t.encodeSelector,
        'gopher://example.org:70000': t.invalidPort,
        'gopher://example.org/Z': t.unknownItemType,
        'gopher://example.org/7a%09b%09c': t.gopherPlusUnsupported,
      };
      for (final entry in expected.entries) {
        final state = AppState();
        await state.navigate(entry.key);
        expect(state.error, entry.value, reason: entry.key);
        state.dispose();
      }
    });
  });

  test('every address message the shared code can raise is translated', () {
    localeOverride = const Locale('de');
    for (final english in [
      'Enter a valid Gopher host',
      'Port must be between 1 and 65535',
      'Selectors and queries cannot contain tabs or newlines',
      'Only search addresses can contain a query',
      'Invalid Gopher URL: must start with gopher://',
      'Encode selector characters such as ? and # in the URL',
      'Unknown Gopher item type',
      'Gopher+ requests are not supported',
    ]) {
      expect(localizedAddressError(english), isNot(english));
    }
  });

  test('counted texts follow each language', () {
    localeOverride = const Locale('es');
    expect(t.minutesAgo(1), 'hace 1 minuto');
    expect(t.minutesAgo(5), 'hace 5 minutos');
    localeOverride = const Locale('de');
    expect(t.daysAgo(1), 'vor 1 Tag');
    expect(t.daysAgo(3), 'vor 3 Tagen');
    localeOverride = const Locale('en');
    expect(t.hoursAgo(1), '1 hour ago');
    expect(t.hoursAgo(2), '2 hours ago');
  });
}
