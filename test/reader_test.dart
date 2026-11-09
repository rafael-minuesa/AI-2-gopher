import 'package:ai_2_gopher/models/gopher_item.dart';
import 'package:ai_2_gopher/screens/home_screen.dart';
import 'dart:io';

import 'package:ai_2_gopher/services/app_state.dart';
import 'package:ai_2_gopher/services/export_text.dart';
import 'package:ai_2_gopher/services/saved_page.dart';
import 'package:ai_2_gopher/services/find_state.dart';
import 'package:ai_2_gopher/services/gopher_client.dart';
import 'package:ai_2_gopher/widgets/menu_view.dart';
import 'package:ai_2_gopher/widgets/text_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PageClient extends GopherClient {
  final List<GopherItem> menu;
  final String text;

  PageClient({this.menu = const [], this.text = ''});

  @override
  Future<List<GopherItem>> fetchMenu(
    GopherAddress address, {
    GopherRequest? request,
    void Function(List<GopherItem>)? onPartial,
  }) async => menu;

  @override
  Future<String> fetchText(
    GopherAddress address, {
    GopherRequest? request,
  }) async => text;
}

List<GopherItem> lines(int count) => [
  for (var i = 0; i < count; i++)
    GopherItem.fromLine(
      i == count - 1 ? 'iThe needle line' : 'iLine number $i\t\tnull\t0',
    ),
];

Future<AppState> open(
  WidgetTester tester,
  GopherClient client,
  String url,
) async {
  final state = AppState(client: client);
  addTearDown(state.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const MaterialApp(home: HomeScreen()),
    ),
  );
  await state.init();
  await state.navigate(url);
  await tester.pumpAndSettle();
  return state;
}

Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

Future<void> typeInFind(WidgetTester tester, String words) async {
  await tester.enterText(find.widgetWithIcon(TextField, Icons.search), words);
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('FindState', () {
    test('counts every match, in any case, and wraps around', () {
      final state = FindState()..report(['Water and water', 'no', 'WATER']);
      state.setQuery('water');
      expect(state.total, 3);
      expect(state.position, 1);
      expect(state.on(0).map((m) => m.start), [0, 10]);
      state.previous();
      expect(state.position, 3);
      state.next();
      expect(state.position, 1);
    });

    test('a symbol is searched for as itself', () {
      final state = FindState()..report(['a.b and axb']);
      state.setQuery('a.b');
      expect(state.total, 1);
    });

    test('accents do not matter either way, and the place stays exact', () {
      final state = FindState()
        ..report(['Vive en París', 'paris', 'ÜBER über']);
      state.setQuery('paris');
      expect(state.total, 2);
      expect(state.on(0).single.start, 8);
      expect(state.on(0).single.end, 13);
      state.setQuery('parís');
      expect(state.total, 2);
      state.setQuery('uber');
      expect(state.total, 2);
    });

    test('n with a tilde is its own letter', () {
      final state = FindState()..report(['el año', 'el ano']);
      state.setQuery('año');
      expect(state.on(0), hasLength(1));
      expect(state.on(1), isEmpty);
    });

    test('text arriving does not move the current match', () {
      final state = FindState()..report(['one word']);
      state.setQuery('word');
      final revision = state.revision;
      state.report(['one word', 'two word']);
      expect(state.total, 2);
      expect(state.position, 1);
      expect(state.revision, revision);
    });

    test('stops at the limit', () {
      final state = FindState()..report(['a' * (FindState.limit + 5)]);
      state.setQuery('a');
      expect(state.total, FindState.limit);
      expect(state.reachedLimit, isTrue);
    });
  });

  group('text size', () {
    testWidgets('A+ and A- step, stop at the ends, and are remembered', (
      tester,
    ) async {
      final state = await open(
        tester,
        PageClient(text: 'A document'),
        'gopher://example.org/0/doc',
      );
      double scale() => MediaQuery.textScalerOf(
        tester.element(find.text('A document')),
      ).scale(1);
      expect(scale(), 1.0);
      await tester.tap(find.byTooltip('Larger text (Ctrl +)'));
      await tester.pump();
      expect(state.textSize, 1.15);
      expect(scale(), 1.15);
      await ctrl(tester, LogicalKeyboardKey.equal);
      expect(state.textSize, 1.3);
      await ctrl(tester, LogicalKeyboardKey.minus);
      expect(state.textSize, 1.15);
      await ctrl(tester, LogicalKeyboardKey.digit0);
      expect(state.textSize, 1.0);
      for (var i = 0; i < 12; i++) {
        state.growText();
      }
      expect(state.textSize, 2.0);
      expect(state.canGrowText, isFalse);
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.text_increase),
            )
            .onPressed,
        isNull,
      );

      final again = AppState(client: PageClient());
      addTearDown(again.dispose);
      await again.init();
      expect(again.textSize, 2.0);
    });

    testWidgets('a size from anywhere else is ignored', (tester) async {
      SharedPreferences.setMockInitialValues({'textSize': 40.0});
      final state = AppState(client: PageClient());
      addTearDown(state.dispose);
      await state.init();
      expect(state.textSize, 1.0);
    });
  });

  group('find', () {
    testWidgets('Ctrl+F on a document marks and scrolls to the match', (
      tester,
    ) async {
      final body =
          '${'A line of text.\n' * 400}The needle is here.\n'
          '${'A line of text.\n' * 400}And a needle again.';
      await open(tester, PageClient(text: body), 'gopher://example.org/0/doc');
      await ctrl(tester, LogicalKeyboardKey.keyF);
      await typeInFind(tester, 'needle');
      expect(find.text('1 of 2'), findsOneWidget);
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final scroll = tester.widget<ListView>(find.byType(ListView));
      final first = scroll.controller!.offset;
      expect(first, greaterThan(1000));
      expect(find.textContaining('The needle is here.'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.text('2 of 2'), findsOneWidget);
      expect(scroll.controller!.offset, greaterThan(first));
      expect(find.textContaining('And a needle again.'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
    });

    testWidgets('goes to a menu line that had not been built', (tester) async {
      await open(
        tester,
        PageClient(menu: lines(3000)),
        'gopher://example.org/1/long',
      );
      expect(find.textContaining('The needle line'), findsNothing);
      await tester.tap(find.byTooltip('Find on this page'));
      await tester.pumpAndSettle();
      await typeInFind(tester, 'needle');
      await tester.pumpAndSettle();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.text('1 of 1'), findsOneWidget);
      expect(find.textContaining('The needle line'), findsOneWidget);
      expect(find.byType(MenuView), findsOneWidget);
    });

    testWidgets('says when there is nothing, and searches the next page too', (
      tester,
    ) async {
      final state = await open(
        tester,
        PageClient(menu: lines(3)),
        'gopher://example.org/1/short',
      );
      await ctrl(tester, LogicalKeyboardKey.keyF);
      await typeInFind(tester, 'zebra');
      expect(find.text('Not found'), findsOneWidget);
      await typeInFind(tester, 'line');
      expect(find.text('1 of 3'), findsOneWidget);
      await state.navigate('gopher://example.org/1/other');
      await tester.pumpAndSettle();
      expect(find.text('1 of 3'), findsOneWidget);
    });

    testWidgets('the keyboard goes back to the chat box on closing', (
      tester,
    ) async {
      await open(
        tester,
        PageClient(
          menu: [
            GopherItem.fromLine('iHello there'),
            GopherItem.fromLine('7Ask\t/chat\t127.0.0.1\t7071'),
          ],
        ),
        'gopher://127.0.0.1:7071/7/chat',
      );
      final box = find.byType(TextField).last;
      await tester.tap(box);
      await tester.pumpAndSettle();
      final focusBefore = FocusManager.instance.primaryFocus;
      await ctrl(tester, LogicalKeyboardKey.keyF);
      await typeInFind(tester, 'hello');
      expect(find.text('1 of 1'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus, isNot(focusBefore));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, focusBefore);
    });
  });

  group('long documents', () {
    final pieces = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(RichText),
    );

    test('are cut at line ends, and the pieces joined are the text', () {
      final many = [for (var i = 0; i < 100; i++) 'line $i'].join('\n');
      for (final text in [
        '',
        'one',
        'a\n\nb',
        '\n\na\n \n\nb\n',
        'a\nb\nc\n\n',
        ' \n \nx',
        many,
      ]) {
        final pieces = readerPieces(text);
        expect(pieces.join(), text);
        expect(pieces.continued, everyElement(isFalse));
      }
      expect(readerPieces('a\nb\n\nc\n\n\nd').texts, ['a\nb\n', 'c\n\n', 'd']);
      expect(readerPieces(many).texts.length, 3);
    });

    test('a line too long for one piece is cut inside, after a space', () {
      final words = 'word ' * 200000;
      final unbroken = 'x' * 20000;
      final faces = '\u{1F600}' * 9000;
      final marks = 'e\u0301' * 9000;
      final mixed = 'A title\n\n${'long ' * 5000}\nits next line\n\nThe end.';
      final lines = [for (var i = 0; i < 39; i++) 'y' * 500].join('\n');
      for (final text in [words, unbroken, faces, marks, mixed, lines]) {
        final pieces = readerPieces(text);
        expect(pieces.join(), text);
        for (final piece in pieces.texts) {
          expect(piece.length, lessThanOrEqualTo(8000));
        }
        expect(pieces.continued.first, isFalse);
      }
      final cut = readerPieces(words);
      expect(cut.texts.length, 125);
      expect(cut.continued.skip(1), everyElement(isTrue));
      expect(cut.texts, everyElement(endsWith(' ')));
      // Never between the two halves of a character, or a letter and its mark.
      for (final piece in readerPieces(faces).texts) {
        expect(piece.length.isEven, isTrue);
        expect(piece.runes.length * 2, piece.length);
      }
      for (final piece in readerPieces(marks).texts) {
        expect(piece.startsWith('e'), isTrue);
      }
      final parts = readerPieces(mixed);
      expect(parts.texts.first, 'A title\n');
      expect(parts.texts.last, 'The end.');
      expect(parts.continued.where((c) => c).length, 3);
    });

    test('Find sees a line through its pieces', () {
      final state = FindState()
        ..report(
          ['First line', 'a long li', 'ne cut in thr', 'ee pieces', 'Last'],
          continued: [false, false, true, true, false],
        );
      expect(
        state.pageText,
        'First line\na long line cut in three pieces\nLast',
      );
      state.setQuery('line');
      expect(state.total, 2);
      state.next();
      expect(state.current!.line, 1);
      expect((state.current!.start, state.current!.end), (7, 9));
      expect(state.on(2).single.head, same(state.current));
      expect((state.on(2).single.start, state.on(2).single.end), (0, 2));
      state.setQuery('three');
      expect(state.total, 1);
      expect(state.current!.line, 2);
      expect(state.on(3).single.end, 2);
      state.setQuery('in thr');
      expect(state.total, 1);
      expect(state.on(3), isEmpty);
      // A line end is still a line end.
      state.setQuery('line a');
      expect(state.total, 0);
      state.setQuery('pieces last');
      expect(state.total, 0);
    });

    testWidgets('only what is near the window is laid out', (tester) async {
      final body = [
        for (var i = 0; i < 5000; i++) 'Paragraph $i of the document.',
      ].join('\n\n');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TextView(content: body)),
        ),
      );
      expect(tester.widgetList(pieces).length, lessThan(60));
      expect(find.text('Paragraph 0 of the document.\n'), findsOneWidget);
    });

    testWidgets('take the room they took as one text', (tester) async {
      const body =
          'A title\n\nA paragraph that is long enough to need several lines '
          'on a narrow page, so it wraps.\nAnd its second line.\n\n\n'
          'After two empty lines.\n \nThe end.\n';
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(width: 300, child: TextView(content: body)),
            ),
          ),
        ),
      );
      expect(tester.widgetList(pieces).length, 4);
      final style = tester.widget<RichText>(pieces.first).text.style;
      final whole = TextPainter(
        text: TextSpan(text: body, style: style),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 300 - 32);
      final list = tester.getRect(find.byType(ListView));
      final first = tester.getRect(pieces.first);
      final last = tester.getRect(pieces.last);
      expect(first.top, list.top + 16);
      expect(last.bottom - first.top, moreOrLessEquals(whole.height));
      whole.dispose();
    });

    testWidgets('are copied with their line ends', (tester) async {
      // A line of 20,000 letters is three pieces, and the window is large
      // enough to hold them all.
      final body =
          'First paragraph.\nIts second line.\n\n${'long ' * 4000}\n\n\nThird.';
      final copies = <String?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copies.add((call.arguments as Map)['text'] as String?);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.binding.setSurfaceSize(const Size(4000, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TextView(content: body)),
        ),
      );
      expect(tester.widgetList(pieces).length, 5);
      await tester.tap(find.textContaining('Third.'));
      await tester.pump();
      await ctrl(tester, LogicalKeyboardKey.keyA);
      await ctrl(tester, LogicalKeyboardKey.keyC);
      // The first is what the selection itself holds, piece after piece.
      expect(copies.first, body);
      expect(copies.last, body);
    });

    testWidgets(
      'Select all and copy takes the whole document',
      (tester) async {
        final body = [
          for (var i = 0; i < 5000; i++) 'Paragraph $i of the document.',
        ].join('\n\n');
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String?;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: TextView(content: body)),
          ),
        );
        await tester.tap(find.textContaining('Paragraph 2 of'));
        await tester.pump();
        await ctrl(tester, LogicalKeyboardKey.keyA);
        await ctrl(tester, LogicalKeyboardKey.keyC);
        expect(copied, body);
        // A click ends it: the document is no longer what is copied.
        copied = null;
        await tester.tap(
          find.textContaining('Paragraph 3 of'),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump(const Duration(seconds: 1));
        await ctrl(tester, LogicalKeyboardKey.keyC);
        expect(copied, isNot(body));
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );

    for (final how in ['Find is closed', 'nothing is found', 'one scrolls']) {
      testWidgets('the way to a far match ends when $how', (tester) async {
        final state = FindState();
        addTearDown(state.dispose);
        final body = [
          for (var i = 0; i < 5000; i++) 'Paragraph $i has ordinary words.',
          'needle',
        ].join('\n\n');
        await tester.pumpWidget(
          ChangeNotifierProvider<FindState>.value(
            value: state,
            child: MaterialApp(
              home: Scaffold(body: TextView(content: body)),
            ),
          ),
        );
        final scroll = tester
            .widget<ListView>(find.byType(ListView))
            .controller!;
        state.open();
        state.setQuery('needle');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        expect(scroll.offset, greaterThan(0));
        if (how == 'Find is closed') {
          state.close();
        } else if (how == 'nothing is found') {
          state.setQuery('there is no such phrase in the document');
        } else {
          scroll.jumpTo(scroll.offset - 300);
        }
        await tester.pump(const Duration(milliseconds: 16));
        final left = scroll.offset;
        for (var frame = 0; frame < 12; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(scroll.offset, left);
        expect(find.textContaining('needle'), findsNothing);
        // And asking again still gets there.
        if (how == 'one scrolls') {
          state.next();
        } else {
          state.setQuery('needle');
        }
        for (var frame = 0; frame < 200; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(find.textContaining('needle'), findsOneWidget);
      });
    }

    testWidgets('Find goes to a match inside a long line', (tester) async {
      final body = '${'word ' * 30000}needle ${'word ' * 30000}';
      await open(tester, PageClient(text: body), 'gopher://example.org/0/doc');
      await ctrl(tester, LogicalKeyboardKey.keyF);
      await typeInFind(tester, 'needle');
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.text('1 of 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // It is in sight: the piece holding it is one of the few laid out.
      expect(tester.widgetList(pieces).length, lessThan(8));
      final marked = tester
          .widgetList<RichText>(pieces)
          .where((text) => text.text.toPlainText().contains('needle'));
      expect(marked.length, 1);
      await tester.tap(find.byTooltip('Disable word wrap'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Find gets there after a click in the text', (tester) async {
      final body = [
        for (var i = 0; i < 600; i++) 'Paragraph $i of the document.',
        'The needle is here.',
        for (var i = 0; i < 600; i++) 'More text, paragraph $i.',
      ].join('\n\n');
      await open(tester, PageClient(text: body), 'gopher://example.org/0/doc');
      // The line clicked is kept by the list when it goes out of sight.
      await tester.tap(find.textContaining('Paragraph 2 of'));
      await tester.pumpAndSettle();
      await ctrl(tester, LogicalKeyboardKey.keyF);
      await typeInFind(tester, 'needle');
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.text('1 of 1'), findsOneWidget);
      expect(find.textContaining('The needle is here.'), findsOneWidget);
    });

    testWidgets('unwrapped, Find goes across to a match far to the right', (
      tester,
    ) async {
      final body =
          '${'A line of text.\n' * 300}${'word ' * 400}needle\n'
          '${'A line of text.\n' * 300}';
      await open(tester, PageClient(text: body), 'gopher://example.org/0/doc');
      await tester.tap(find.byTooltip('Disable word wrap'));
      await tester.pumpAndSettle();
      await ctrl(tester, LogicalKeyboardKey.keyF);
      await typeInFind(tester, 'needle');
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.takeException(), isNull);
      final across = tester.widget<SingleChildScrollView>(
        find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.horizontal,
        ),
      );
      expect(across.controller!.offset, greaterThan(1000));
      final down = tester.widget<ListView>(find.byType(ListView));
      expect(down.controller!.offset, greaterThan(1000));
    });
  });

  group('export text', () {
    test('the Downloads folder is found under its own name', () {
      String? read(String path) => path == '/home/x/.config/user-dirs.dirs'
          ? '# comment\nXDG_DOWNLOAD_DIR="\$HOME/Descargas"\n'
          : null;
      expect(
        downloadsFolder(environment: {'HOME': '/home/x'}, read: read),
        '/home/x/Descargas',
      );
      expect(
        downloadsFolder(environment: {'HOME': '/home/x'}, read: (_) => null),
        '/home/x/Downloads',
      );
      expect(
        downloadsFolder(
          environment: {'HOME': '/home/x'},
          read: (_) => 'XDG_DOWNLOAD_DIR="\$HOME/"',
        ),
        '/home/x/Downloads',
      );
    });

    test('names are safe and short', () {
      expect(exportFileName('A title: with/slashes?'), 'A-title-with-slashes');
      expect(exportFileName('Ñandú día'), 'Ñandú-día');
      expect(exportFileName('gopher://example.org/1/x'), 'example-org-1-x');
      expect(exportFileName('../../etc/passwd'), 'etc-passwd');
      expect(exportFileName('???'), 'page');
      expect(exportFileName('a' * 200).length, 80);
    });

    test('an earlier export is never overwritten', () async {
      final folder = Directory.systemTemp.createTempSync('export');
      addTearDown(() => folder.deleteSync(recursive: true));
      final inside = '${folder.path}/not/yet';
      final first = await exportText('one', 'doc', folder: inside);
      final second = await exportText('two\n', 'doc', folder: inside);
      expect(first, '$inside/doc.txt');
      expect(second, '$inside/doc-2.txt');
      expect(File(first).readAsStringSync(), 'one\n');
      expect(File(second).readAsStringSync(), 'two\n');
    });
  });

  group('saved pages', () {
    const id = '11111111-1111-4111-8111-111111111111';
    final menu = [
      GopherItem.fromLine('iMy page\t\tnull\t0'),
      GopherItem.fromLine('iCaptured: today\t\tnull\t0'),
      GopherItem.fromLine('0Read article\t/text/$id/article\t127.0.0.1\t7070'),
      GopherItem.fromLine('0Read full page\t/text/$id/page\t127.0.0.1\t7070'),
      GopherItem.fromLine('1Saved web pages\t/\t127.0.0.1\t7070'),
      GopherItem.fromLine(
        'hOriginal page (browser)\tURL:https://example.org/\t127.0.0.1\t7070',
      ),
      GopherItem.fromLine('iLinks\t\tnull\t0'),
      GopherItem.fromLine(
        'h[1] A link (browser)\tURL:https://example.org/a\t127.0.0.1\t7070',
      ),
    ];

    test('only the saved pages of this computer count', () {
      SavedPage? of(String url) => SavedPage.of(GopherAddress.fromUrl(url));
      expect(of('gopher://127.0.0.1:7070/1/page/$id')?.view, SavedView.links);
      expect(
        of('gopher://127.0.0.1:7070/0/text/$id/page')?.view,
        SavedView.page,
      );
      expect(of('gopher://127.0.0.1:7071/1/page/$id'), isNull);
      expect(of('gopher://example.org:7070/1/page/$id'), isNull);
      expect(of('gopher://127.0.0.1:7070/1/'), isNull);
    });

    testWidgets('buttons replace the menu lines, and the links stay', (
      tester,
    ) async {
      final opened = <Uri>[];
      final state = AppState(
        client: PageClient(menu: menu, text: 'The article'),
        openUrl: (uri) async {
          opened.add(uri);
          return true;
        },
      );
      addTearDown(state.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await state.navigate('gopher://127.0.0.1:7070/1/page/$id');
      await tester.pumpAndSettle();
      expect(find.text('Read article'), findsNothing);
      expect(find.text('Original page (browser)'), findsNothing);
      expect(find.text('[1] A link (browser)'), findsOneWidget);
      expect(find.text('Saved web pages'), findsOneWidget);

      await tester.tap(find.text('Article'));
      await tester.pumpAndSettle();
      expect(state.savedPage?.view, SavedView.article);
      expect(find.textContaining('The article'), findsOneWidget);
      expect(state.exportName, 'My-page-article');

      await tester.tap(find.text('Original page'));
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse('https://example.org/')]);
      expect(state.savedPage?.view, SavedView.article);
    });

    test('a saved page opens on its article, anything else as it is', () {
      expect(
        SavedPage.opening('gopher://127.0.0.1:7070/1/page/$id'),
        'gopher://127.0.0.1:7070/0/text/$id/article',
      );
      for (final url in [
        'gopher://127.0.0.1:7070/0/text/$id/page',
        'gopher://127.0.0.1:7070/1/',
        'gopher://example.org/1/page/$id',
        'not an address',
      ]) {
        expect(SavedPage.opening(url), url);
      }
    });

    testWidgets('a page opened directly as text still gets its buttons', (
      tester,
    ) async {
      final state = await open(
        tester,
        PageClient(menu: menu, text: 'Words'),
        'gopher://127.0.0.1:7070/0/text/$id/page',
      );
      await tester.pumpAndSettle();
      expect(find.text('Full page'), findsOneWidget);
      expect(find.text('Original page'), findsOneWidget);
      expect(state.savedInfo?.title, 'My page');
    });

    testWidgets('other pages have no such buttons', (tester) async {
      await open(
        tester,
        PageClient(menu: menu),
        'gopher://example.org/1/page/$id',
      );
      expect(find.text('Full page'), findsNothing);
      expect(find.text('Read article'), findsOneWidget);
    });
  });
}
