import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_2_gopher/companion/client.dart';
import 'package:ai_2_gopher/screens/web_library_screen.dart';

class LibraryClient extends CompanionClient {
  LibraryClient()
    : super(CompanionPaths('/unused', '/unused/socket'), '/unused');
  final calls = <String>[];
  bool fail = false;
  final pages = <Map<String, dynamic>>[
    {
      'id': '11111111-1111-4111-8111-111111111111',
      'title': 'A saved article',
      'source': 'https://example.org/article',
      'url':
          'gopher://127.0.0.1:7070/1/page/11111111-1111-4111-8111-111111111111',
    },
  ];
  @override
  Future<Map<String, dynamic>> request(
    Map<String, dynamic> message, {
    bool start = false,
  }) async {
    calls.add(message['action'] as String);
    if (fail) throw const FormatException('Port 7070 is occupied');
    if (message['action'] == 'remove') {
      pages.removeWhere((page) => page['id'] == message['id']);
    }
    return {'ok': true, 'pages': pages.toList()};
  }
}

Future<void> openLibrary(WidgetTester tester, LibraryClient client) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => WebLibraryScreen(client: client),
              ),
            ),
            child: const Text('Open library'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open library'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'removal requires confirmation and refreshes the saved-page list',
    (tester) async {
      final client = LibraryClient();
      await openLibrary(tester, client);
      expect(find.text('A saved article'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove saved copy'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(client.calls, ['list']);
      await tester.tap(find.byTooltip('Remove saved copy'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(client.calls, ['list', 'remove', 'list']);
      expect(find.text('A saved article'), findsNothing);
    },
  );

  testWidgets(
    'stopping serving keeps copies and returns to the browser with a status message',
    (tester) async {
      final client = LibraryClient();
      await openLibrary(tester, client);
      await tester.tap(find.text('Stop serving'));
      await tester.pumpAndSettle();
      expect(client.calls, ['list', 'stop']);
      expect(client.pages, hasLength(1));
      expect(find.text('Open library'), findsOneWidget);
      expect(find.textContaining('Saved copies are kept'), findsOneWidget);
    },
  );

  testWidgets('a startup error is visible and retry restores the library', (
    tester,
  ) async {
    final client = LibraryClient()..fail = true;
    await openLibrary(tester, client);
    expect(find.textContaining('Port 7070 is occupied'), findsOneWidget);
    client.fail = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('A saved article'), findsOneWidget);
    expect(find.textContaining('Port 7070 is occupied'), findsNothing);
  });
}
