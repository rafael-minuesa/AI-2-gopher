import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_2_gopher/models/gopher_item.dart';
import 'package:ai_2_gopher/screens/home_screen.dart';
import 'package:ai_2_gopher/services/app_state.dart';
import 'package:ai_2_gopher/services/gopher_client.dart';
import 'package:ai_2_gopher/widgets/menu_view.dart';
import 'package:ai_2_gopher/widgets/text_view.dart';

class ScreenClient extends GopherClient {
  @override
  Future<List<GopherItem>> fetchMenu(
    GopherAddress address, {
    GopherRequest? request,
    void Function(List<GopherItem>)? onPartial,
  }) async {
    if (address.query != null) {
      return [GopherItem.fromLine('iResults for ${address.query}')];
    }
    return [GopherItem.fromLine('7Search documents\t/search\texample.org\t70')];
  }

  @override
  Future<String> fetchText(
    GopherAddress address, {
    GopherRequest? request,
  }) async => 'Saved document body';
}

class StreamingClient extends GopherClient {
  final answer = Completer<List<GopherItem>>();
  void Function(List<GopherItem>)? partial;

  @override
  Future<List<GopherItem>> fetchMenu(
    GopherAddress address, {
    GopherRequest? request,
    void Function(List<GopherItem>)? onPartial,
  }) {
    partial = onPartial;
    return answer.future;
  }
}

void main() {
  testWidgets('short documents start at the reading margin', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: TextView(content: 'Short document')),
      ),
    );
    expect(tester.getTopLeft(find.byType(SelectableText)).dx, 16);
  });
  testWidgets('word wrap switches to horizontally scrollable text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: TextView(content: 'A long line ' * 100),
          ),
        ),
      ),
    );
    final horizontal = find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal,
    );
    expect(horizontal, findsNothing);
    await tester.tap(find.byTooltip('Disable word wrap'));
    await tester.pump();
    expect(horizontal, findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Enable word wrap'));
    await tester.pump();
    expect(horizontal, findsNothing);
  });

  testWidgets('search dialog loads query results', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState(client: ScreenClient());
    addTearDown(state.dispose);
    await state.init();
    await state.navigate('gopher://example.org');
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.tap(find.text('Search documents'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'some words');
    await tester.tap(find.widgetWithText(TextButton, 'Search'));
    await tester.pumpAndSettle();
    expect(find.text('Results for some words'), findsOneWidget);
    expect(state.currentAddress!.query, 'some words');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a search item on this computer asks for a question', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final client = ScreenClient();
    final state = AppState(client: client);
    addTearDown(state.dispose);
    await state.init();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          home: Scaffold(
            body: MenuView(
              items: [
                GopherItem.fromLine(
                  '7Chat with the AI\t/chat\t127.0.0.1\t7071',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Chat with the AI'));
    await tester.pumpAndSettle();
    expect(find.text('Your question'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Ask'), findsOneWidget);
    expect(find.text('Search query'), findsNothing);
  });

  testWidgets('the text of a menu can be selected', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MenuView(items: [GopherItem.fromLine('iSome words\t\t\t0')]),
        ),
      ),
    );
    expect(find.byType(SelectionArea), findsOneWidget);
  });

  testWidgets('an answer shows as it arrives, with Cancel and no animation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final client = StreamingClient();
    final state = AppState(client: client);
    addTearDown(state.dispose);
    await state.init();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    unawaited(state.navigate('gopher://127.0.0.1:7070/7/chat%09hello'));
    await tester.pump();
    expect(find.text('Cancel'), findsOneWidget);
    client.partial!([GopherItem.fromLine('iReading your question')]);
    await tester.pump();
    expect(find.text('Reading your question'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    client.answer.complete([
      GopherItem.fromLine('iReading your question'),
      GopherItem.fromLine('iI am the assistant'),
      GopherItem.fromLine('7Ask the next question\t/chat/a\t127.0.0.1\t7070'),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('I am the assistant'), findsOneWidget);
    expect(find.text('Ask the next question'), findsOneWidget);
    expect(find.byTooltip('Add bookmark'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long answer stays in sight and its end is left showing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final client = StreamingClient();
    final state = AppState(client: client);
    addTearDown(state.dispose);
    await state.init();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    unawaited(state.navigate('gopher://127.0.0.1:7070/7/chat%09hello'));
    await tester.pump();
    final lines = <GopherItem>[];
    for (var i = 0; i < 40; i++) {
      lines.add(GopherItem.fromLine('iLine $i'));
      client.partial!(List.of(lines));
      await tester.pump();
      await tester.pump();
    }
    expect(find.text('Line 39'), findsOneWidget);
    expect(find.text('Line 0'), findsNothing);
    client.answer.complete([
      ...lines,
      GopherItem.fromLine('7Ask the next question\t/chat/a\t127.0.0.1\t7070'),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Ask the next question'), findsOneWidget);
    expect(find.text('Line 0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening a bookmark switches to Browse and shows text', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState(client: ScreenClient());
    addTearDown(state.dispose);
    await state.init();
    await state.addBookmark('Saved document', 'gopher://example.org:70/0notes');
    state.selectTab(1);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.tap(find.text('Saved document'));
    await tester.pumpAndSettle();
    expect(state.selectedTab, 0);
    expect(find.text('Saved document body'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('small screens can show navigation and document controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final state = AppState(client: ScreenClient());
    addTearDown(state.dispose);
    await state.init();
    await state.navigate('gopher://example.org/0notes');
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
