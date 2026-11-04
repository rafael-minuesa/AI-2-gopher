import 'package:ai_2_gopher/models/gopher_item.dart';
import 'package:ai_2_gopher/screens/home_screen.dart';
import 'package:ai_2_gopher/services/app_state.dart';
import 'package:ai_2_gopher/services/find_state.dart';
import 'package:ai_2_gopher/services/gopher_client.dart';
import 'package:ai_2_gopher/widgets/menu_view.dart';
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
        tester.element(find.byType(SelectableText)),
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
      final scroll = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView).first,
      );
      final first = scroll.controller!.offset;
      expect(first, greaterThan(1000));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('2 of 2'), findsOneWidget);
      expect(scroll.controller!.offset, greaterThan(first));
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
}
