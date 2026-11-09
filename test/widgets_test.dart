import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_2_gopher/models/gopher_item.dart';
import 'package:ai_2_gopher/screens/home_screen.dart';
import 'package:ai_2_gopher/services/app_state.dart';
import 'package:ai_2_gopher/services/gopher_client.dart';
import 'package:ai_2_gopher/widgets/chat_view.dart';
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

class ChatClient extends GopherClient {
  final List<GopherItem> first;
  final asked = <GopherAddress>[];
  final opened = <GopherAddress>[];
  Completer<List<GopherItem>>? _answer;
  void Function(List<GopherItem>)? partial;

  ChatClient(this.first);

  void finish(List<GopherItem> items) => _answer!.complete(items);
  void fail(Object error) => _answer!.completeError(error);

  @override
  Future<List<GopherItem>> fetchMenu(
    GopherAddress address, {
    GopherRequest? request,
    void Function(List<GopherItem>)? onPartial,
  }) {
    opened.add(address);
    if (address.type == GopherItemType.directory) {
      return Future.value([
        GopherItem.fromLine('7Saved one\t/chat/k\t127.0.0.1\t7071'),
        GopherItem.fromLine('1Delete all\t/chats/forget/all\t127.0.0.1\t7071'),
      ]);
    }
    if (address.query == null) return Future.value(first);
    asked.add(address);
    partial = onPartial;
    _answer = Completer<List<GopherItem>>();
    return _answer!.future;
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
                GopherItem.fromLine('7Ask the AI\t/ask\t127.0.0.1\t7071'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Ask the AI'));
    await tester.pumpAndSettle();
    expect(find.text('Your question'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Ask'), findsOneWidget);
    expect(find.text('Search query'), findsNothing);
  });

  for (final selector in ['/knowledge/search', '/search/first-aid']) {
    testWidgets('$selector says it is a search of its own', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final state = AppState(client: ScreenClient());
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
                    '7Look it up\t$selector\t127.0.0.1\t7071',
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Look it up'));
      await tester.pumpAndSettle();
      expect(
        find.text('A new search, separate from your chat'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextButton, 'Search'), findsOneWidget);
      expect(find.text('Your question'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Ask'), findsNothing);
    });
  }

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
    unawaited(state.navigate('gopher://127.0.0.1:7070/7/search/x%09hello'));
    await tester.pump();
    expect(find.text('Cancel'), findsOneWidget);
    client.partial!([GopherItem.fromLine('iReading your question')]);
    await tester.pump();
    expect(find.text('Reading your question'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    client.answer.complete([
      GopherItem.fromLine('iReading your question'),
      GopherItem.fromLine('iI am the assistant'),
      GopherItem.fromLine('7Ask the next question\t/search/x\t127.0.0.1\t7070'),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('I am the assistant'), findsOneWidget);
    expect(find.text('Ask the next question'), findsOneWidget);
    expect(find.byTooltip('Add bookmark'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('waiting for this computer shows nothing that moves', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState(client: StreamingClient());
    addTearDown(state.dispose);
    await state.init();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    unawaited(
      state.navigate('gopher://127.0.0.1:7071/7/knowledge/search%09burn'),
    );
    await tester.pump();
    expect(find.text('Cancel'), findsOneWidget);
    expect(
      find.text('This computer is working on it. Please wait.'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('waiting for another server still shows the spinner', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState(client: StreamingClient());
    addTearDown(state.dispose);
    await state.init();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    unawaited(state.navigate('gopher://gopher.example/7/search%09burn'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
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
    unawaited(state.navigate('gopher://127.0.0.1:7070/7/search/x%09hello'));
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
      GopherItem.fromLine('7Ask the next question\t/search/x\t127.0.0.1\t7070'),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Ask the next question'), findsOneWidget);
    expect(find.text('Line 0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  group('the chat page', () {
    const page = 'gopher://127.0.0.1:7071/7/chat';
    GopherItem next() =>
        GopherItem.fromLine('7Ask the next question\t/chat/k\t127.0.0.1\t7071');
    GopherItem fresh() => GopherItem.fromLine(
      '7Start a new conversation\t/chat\t127.0.0.1\t7071',
    );

    Future<ChatClient> open(WidgetTester tester, List<GopherItem> first) async {
      tester.view.physicalSize = const Size(800, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final client = ChatClient(first);
      final state = AppState(client: client);
      addTearDown(state.dispose);
      await state.init();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await state.navigate(page);
      await tester.pumpAndSettle();
      return client;
    }

    testWidgets('Enter asks in the conversation, with no popup', (
      tester,
    ) async {
      final client = await open(tester, [
        GopherItem.fromLine('iType your question.'),
        GopherItem.fromLine('7Chat with the AI\t/chat\t127.0.0.1\t7071'),
      ]);
      expect(find.text('Type your question.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Chat with the AI'), findsNothing);
      expect(find.text('Start a new conversation'), findsNothing);

      await tester.enterText(find.byType(TextField).last, 'hola');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(client.asked.last.selector, '/chat');
      expect(client.asked.last.query, 'hola');
      expect(find.text('Cancel'), findsOneWidget);
      // Nothing blinks away while the model reads.
      expect(find.text('Type your question.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      client.partial!([
        GopherItem.fromLine('i> hola'),
        GopherItem.fromLine('iProcessing ...\t/chat-status\t(NULL)\t0'),
      ]);
      await tester.pump();
      expect(find.text('Processing .'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Processing ..'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Processing ...'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Processing .'), findsOneWidget);
      client.partial!([
        GopherItem.fromLine('i> hola'),
        GopherItem.fromLine('iProcessing ...\t/chat-status\t(NULL)\t0'),
        GopherItem.fromLine('iBue'),
      ]);
      await tester.pump();
      expect(find.textContaining('Processing'), findsNothing);
      client.finish([
        GopherItem.fromLine('i> hola'),
        GopherItem.fromLine('iProcessing ...\t/chat-status\t(NULL)\t0'),
        GopherItem.fromLine('iBuenas'),
        next(),
        fresh(),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('> hola'), findsOneWidget);
      expect(find.text('Buenas'), findsOneWidget);
      expect(find.textContaining('Processing'), findsNothing);
      expect(find.text('Ask the next question'), findsNothing);
      expect(find.text('Start a new conversation'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, 'y\nahora');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(client.asked.last.selector, '/chat/k');
      expect(client.asked.last.query, 'y ahora');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Shift+Enter does not send, and an empty box asks nothing', (
      tester,
    ) async {
      final client = await open(tester, [next()]);
      final asked = client.asked.length;
      await tester.enterText(find.byType(TextField).last, '   ');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(client.asked.length, asked);
      await tester.enterText(find.byType(TextField).last, 'hola');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pump();
      expect(client.asked.length, asked);
    });

    testWidgets('the page follows the answer until you scroll up', (
      tester,
    ) async {
      final client = await open(tester, [next()]);
      await tester.enterText(find.byType(TextField).last, 'hola');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      final lines = <GopherItem>[];
      for (var i = 0; i < 60; i++) {
        lines.add(GopherItem.fromLine('iLine $i'));
        client.partial!(List.of(lines));
        await tester.pump();
        await tester.pump();
      }
      expect(find.text('Line 59'), findsOneWidget);
      expect(find.text('Line 0'), findsNothing);
      await tester.drag(find.byType(ListView).last, const Offset(0, 300));
      await tester.pump();
      lines.add(GopherItem.fromLine('iLine 60'));
      client.partial!(List.of(lines));
      await tester.pump();
      await tester.pump();
      expect(find.text('Line 60'), findsNothing);
      client.finish([...lines, next()]);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('what else the server offers becomes buttons', (tester) async {
      final client = await open(tester, [
        GopherItem.fromLine('iAn answer'),
        next(),
        fresh(),
        GopherItem.fromLine('1Earlier conversations\t/chats\t127.0.0.1\t7071'),
        GopherItem.fromLine(
          '1Delete this conversation\t/chats/forget/k\t127.0.0.1\t7071',
        ),
      ]);
      expect(find.text('Earlier conversations'), findsOneWidget);
      expect(find.text('Delete this conversation'), findsOneWidget);
      await tester.tap(find.text('Earlier conversations'));
      await tester.pumpAndSettle();
      expect(client.opened.last.selector, '/chats');
      expect(find.byType(MenuView), findsOneWidget);
      expect(find.text('127.0.0.1:7071'), findsNothing);
    });

    testWidgets('Search Knowledge Packs has its own icon and opens a menu', (
      tester,
    ) async {
      final knowledge = GopherItem.fromLine(
        '1Search Knowledge Packs\t/knowledge\t127.0.0.1\t7071',
      );
      final client = await open(tester, [fresh(), knowledge]);
      expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ChatView),
          matching: find.byIcon(Icons.history),
        ),
        findsNothing,
      );
      await tester.tap(find.text('Search Knowledge Packs'));
      await tester.pumpAndSettle();
      expect(client.opened.last.selector, '/knowledge');
      expect(find.byType(MenuView), findsOneWidget);
      expect(client.asked, isEmpty);
    });

    testWidgets('the button stays on a conversation', (tester) async {
      await open(tester, [
        GopherItem.fromLine('iAn answer'),
        next(),
        fresh(),
        GopherItem.fromLine(
          '1Search Knowledge Packs\t/knowledge\t127.0.0.1\t7071',
        ),
      ]);
      expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
      expect(find.text('Search Knowledge Packs'), findsOneWidget);
    });

    testWidgets('a failure keeps the conversation and the box', (tester) async {
      final client = await open(tester, [
        GopherItem.fromLine('iEarlier answer'),
        next(),
      ]);
      await tester.enterText(find.byType(TextField).last, 'hola');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      client.fail(GopherException('No connection'));
      await tester.pumpAndSettle();
      expect(find.text('Earlier answer'), findsOneWidget);
      expect(find.text('No connection'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Ask'), findsOneWidget);
    });
  });

  testWidgets('a long menu from a server opens at its first line', (
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
    unawaited(state.navigate('gopher://example.org/1/'));
    await tester.pump();
    final lines = <GopherItem>[];
    for (var i = 0; i < 40; i++) {
      lines.add(GopherItem.fromLine('iLine $i'));
      client.partial!(List.of(lines));
      await tester.pump();
      await tester.pump();
    }
    expect(find.text('Line 0'), findsOneWidget);
    expect(find.text('Line 39'), findsNothing);
    client.answer.complete(lines);
    await tester.pumpAndSettle();
    expect(find.text('Line 0'), findsOneWidget);
    expect(find.text('Line 39'), findsNothing);
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
