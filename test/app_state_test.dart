import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_2_gopher/models/gopher_item.dart';
import 'package:ai_2_gopher/services/app_state.dart';
import 'package:ai_2_gopher/services/gopher_client.dart';
import 'package:ai_2_gopher/services/storage_service.dart';

class FixtureClient extends GopherClient {
  final visits = <GopherAddress>[];
  final delayed = <String, Completer<List<GopherItem>>>{};
  final answers = <String, List<GopherItem>>{};
  String? failure;
  void Function(List<GopherItem>)? partial;

  @override
  Future<List<GopherItem>> fetchMenu(
    GopherAddress address, {
    GopherRequest? request,
    void Function(List<GopherItem>)? onPartial,
  }) async {
    visits.add(address);
    partial = onPartial;
    if (failure == address.selector) throw GopherException('Fixture failure');
    if (delayed.containsKey(address.selector)) {
      return delayed[address.selector]!.future;
    }
    return answers[address.selector] ??
        [GopherItem.fromLine('i${address.selector}')];
  }

  @override
  Future<String> fetchText(
    GopherAddress address, {
    GopherRequest? request,
  }) async {
    visits.add(address);
    return 'Text for ${address.selector}';
  }
}

class FailingStorage extends StorageService {
  @override
  Future<void> init() async => throw StateError('Unavailable');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FixtureClient client;
  late AppState state;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    client = FixtureClient();
    state = AppState(client: client);
    await state.init();
  });
  tearDown(() => state.dispose());

  test(
    'Back and Forward traverse menus and text without adding visits',
    () async {
      await state.navigate('gopher://example.org/1A');
      await state.navigate('gopher://example.org/0B');
      await state.navigate('gopher://example.org/1C');
      await state.goBack();
      expect(state.currentAddress!.selector, 'B');
      expect(state.currentContent, 'Text for B');
      expect(state.canGoForward, isTrue);
      await state.goBack();
      expect(state.currentAddress!.selector, 'A');
      expect(state.canGoBack, isFalse);
      await state.goForward();
      expect(state.currentAddress!.selector, 'B');
      await state.goForward();
      expect(state.currentAddress!.selector, 'C');
      expect(state.canGoForward, isFalse);
    },
  );

  test('new visits drop the forward branch; reload preserves it', () async {
    await state.navigate('gopher://example.org/1A');
    await state.navigate('gopher://example.org/1B');
    await state.goBack();
    await state.reload();
    expect(state.canGoForward, isTrue);
    await state.navigate('gopher://example.org/1C');
    expect(state.canGoForward, isFalse);
    await state.goBack();
    expect(state.currentAddress!.selector, 'A');
  });

  test('failed traversal retains cursor and Retry completes it', () async {
    await state.navigate('gopher://example.org/1A');
    await state.navigate('gopher://example.org/1B');
    client.failure = 'A';
    await state.goBack();
    expect(state.currentAddress!.selector, 'B');
    expect(state.canGoBack, isTrue);
    expect(state.canGoForward, isFalse);
    expect(state.error, 'Fixture failure');
    client.failure = null;
    await state.retry();
    expect(state.currentAddress!.selector, 'A');
    expect(state.canGoForward, isTrue);
  });

  test(
    'text bookmark and history entries reopen as text and select Browse',
    () async {
      await state.navigate('gopher://example.org/0notes', title: 'My notes');
      await state.addBookmark('My notes', state.currentAddress!.toUrl());
      state.selectTab(1);
      await state.navigate(state.bookmarks.single.url);
      expect(state.selectedTab, 0);
      expect(state.currentMenu, isNull);
      expect(state.currentContent, 'Text for notes');
      expect(
        GopherAddress.fromUrl(state.history.single.url).type,
        GopherItemType.file,
      );
    },
  );

  test('search results retain query in address and history', () async {
    await state.search(
      GopherItem.fromLine('7Find\t/search\texample.org\t70'),
      ' two words ',
    );
    expect(client.visits.single.request, '/search\ttwo words');
    expect(GopherAddress.fromUrl(state.history.single.url).query, 'two words');
  });

  test('obsolete responses cannot replace a newer successful page', () async {
    final delayed = Completer<List<GopherItem>>();
    client.delayed['slow'] = delayed;
    final old = state.navigate('gopher://example.org/1slow');
    await state.navigate('gopher://example.org/0latest');
    delayed.complete([GopherItem.fromLine('iOld page')]);
    await old;
    expect(state.currentAddress!.selector, 'latest');
    expect(state.currentMenu, isNull);
    expect(state.history.length, 1);
  });

  test(
    'obsolete failures cannot replace a newer page error or loading state',
    () async {
      final delayed = Completer<List<GopherItem>>();
      client.delayed['slow'] = delayed;
      final old = state.navigate('gopher://example.org/1slow');
      await state.navigate('gopher://example.org/1latest');
      delayed.completeError(GopherException('Old failure'));
      await old;
      expect(state.currentAddress!.selector, 'latest');
      expect(state.error, isNull);
      expect(state.isLoading, isFalse);
    },
  );

  group('the chat', () {
    const page = 'gopher://127.0.0.1:7071/7/chat';

    test('opens with no question, and stays out of history', () async {
      await state.navigate(page);
      expect(state.error, isNull);
      expect(state.isChat, isTrue);
      expect(state.canReload, isFalse);
      expect(state.history, isEmpty);
    });

    test('its questions are one page: Back leaves the chat', () async {
      await state.navigate('gopher://example.org/1A');
      await state.navigate(page);
      await state.askChat('one');
      await state.askChat('two');
      expect(state.currentAddress!.query, 'two');
      expect(state.currentAddress!.shownUrl, page);
      await state.goBack();
      expect(state.currentAddress!.selector, 'A');
    });

    test('the next question goes to the conversation on the page', () async {
      client.answers['/chat'] = [
        GopherItem.fromLine('7Ask the next question\t/chat/k\t127.0.0.1\t7071'),
        GopherItem.fromLine(
          '7Start a new conversation\t/chat\t127.0.0.1\t7071',
        ),
      ];
      await state.navigate(page);
      await state.askChat('one');
      expect(client.visits.last.selector, '/chat/k');
      expect(client.visits.last.query, 'one');
    });

    test('AI-2 Chat chosen while chatting does not disturb it', () async {
      await state.navigate(page);
      await state.askChat('one');
      final asked = client.visits.length;
      await state.openFromOutside(page);
      expect(client.visits.length, asked);
      expect(state.currentAddress!.query, 'one');
      await state.openFromOutside('gopher://example.org/1A');
      expect(state.isChat, isFalse);
    });

    test('AI-2 Chat chosen after a failure loads the page again', () async {
      client.failure = '/chat';
      await state.navigate(page);
      expect(state.error, isNotNull);
      client.failure = null;
      await state.openFromOutside(page);
      expect(state.error, isNull);
      expect(state.currentAddress!.selector, '/chat');
    });

    test('the conversations menu stays out of history', () async {
      await state.navigate('gopher://127.0.0.1:7071/1/chats');
      expect(state.error, isNull);
      expect(state.isChat, isFalse);
      expect(state.history, isEmpty);
      await state.navigate('gopher://127.0.0.1:7071/7/chat/k');
      expect(state.isChat, isTrue);
      await state.goBack();
      expect(state.currentAddress!.selector, '/chats');
    });

    test('other search items on this computer still need a query', () async {
      await state.navigate('gopher://127.0.0.1:7071/7/search/x');
      expect(state.error, isNotNull);
    });
  });

  group('questions to this computer', () {
    const url = 'gopher://127.0.0.1:7070/7/chat%09who%20are%20you';

    test('lines show while loading and the page commits at the end', () async {
      final answer = Completer<List<GopherItem>>();
      client.delayed['/chat'] = answer;
      final loading = state.navigate(url);
      await Future<void>.delayed(Duration.zero);
      client.partial!([GopherItem.fromLine('iReading')]);
      expect(state.isLoading, isTrue);
      expect(state.partialMenu!.single.displayText, 'Reading');
      expect(state.currentAddress, isNull);
      answer.complete([GopherItem.fromLine('iDone')]);
      await loading;
      expect(state.partialMenu, isNull);
      expect(state.currentMenu!.single.displayText, 'Done');
    });

    test('a failure keeps what arrived, and Retry asks again', () async {
      final answer = Completer<List<GopherItem>>();
      client.delayed['/chat'] = answer;
      final loading = state.navigate(url);
      await Future<void>.delayed(Duration.zero);
      client.partial!([GopherItem.fromLine('iHalf an answer')]);
      answer.completeError(
        GopherException('The answer stopped before it finished'),
      );
      await loading;
      expect(state.isLoading, isFalse);
      expect(state.error, 'The answer stopped before it finished');
      expect(state.partialMenu!.single.displayText, 'Half an answer');
      expect(state.canRetry, isTrue);
      final again = Completer<List<GopherItem>>();
      client.delayed['/chat'] = again;
      final retrying = state.retry();
      await Future<void>.delayed(Duration.zero);
      expect(state.partialMenu, isNull);
      again.complete([GopherItem.fromLine('iWhole answer')]);
      await retrying;
      expect(state.error, isNull);
      expect(state.currentMenu!.single.displayText, 'Whole answer');
    });

    test('Dismiss clears a failed answer', () async {
      final answer = Completer<List<GopherItem>>();
      client.delayed['/chat'] = answer;
      final loading = state.navigate(url);
      await Future<void>.delayed(Duration.zero);
      client.partial!([GopherItem.fromLine('iHalf')]);
      answer.completeError(GopherException('Stopped'));
      await loading;
      state.clearError();
      expect(state.error, isNull);
      expect(state.partialMenu, isNull);
    });

    test('Cancel returns to the page before it, with no error', () async {
      await state.navigate('gopher://example.org/1A');
      final answer = Completer<List<GopherItem>>();
      client.delayed['/chat'] = answer;
      final loading = state.navigate(url);
      await Future<void>.delayed(Duration.zero);
      client.partial!([GopherItem.fromLine('iReading')]);
      state.cancelLoading();
      expect(state.isLoading, isFalse);
      expect(state.partialMenu, isNull);
      expect(state.error, isNull);
      expect(state.canRetry, isFalse);
      expect(state.currentAddress!.selector, 'A');
      answer.complete([GopherItem.fromLine('iLate')]);
      await loading;
      expect(state.currentAddress!.selector, 'A');
      expect(state.currentMenu!.single.displayText, 'A');
      client.partial!([GopherItem.fromLine('iLater')]);
      expect(state.partialMenu, isNull);
    });

    test('Back and Forward show the answer without asking again', () async {
      await state.navigate(url);
      await state.navigate('gopher://example.org/1A');
      final asked = client.visits.length;
      await state.goBack();
      expect(state.currentAddress!.isLocalQuestion, isTrue);
      expect(state.currentMenu!.single.displayText, '/chat');
      await state.goForward();
      await state.goBack();
      expect(client.visits.where((v) => v.selector == '/chat').length, 1);
      expect(client.visits.length, asked + 1);
    });

    test('Reload does not ask again and history stays clean', () async {
      await state.navigate(url);
      expect(state.canReload, isFalse);
      await state.reload();
      expect(client.visits.length, 1);
      expect(state.history, isEmpty);
    });

    test('a search on another computer behaves as before', () async {
      await state.navigate('gopher://example.org/7/s%09x');
      await state.navigate('gopher://example.org/1A');
      await state.goBack();
      expect(client.visits.where((v) => v.selector == '/s').length, 2);
      expect(state.canReload, isTrue);
      expect(state.history.length, greaterThan(0));
    });
  });

  test('storage errors do not prevent reading', () async {
    final unavailable = AppState(client: client, storage: FailingStorage());
    addTearDown(unavailable.dispose);
    await unavailable.init();
    await unavailable.navigate('gopher://example.org/0readme');
    expect(unavailable.currentContent, 'Text for readme');
    expect(unavailable.error, isNull);
    expect(unavailable.storageWarning, isNotNull);
    expect(
      await unavailable.addBookmark(
        'Readme',
        unavailable.currentAddress!.toUrl(),
      ),
      isFalse,
    );
  });

  test('HTML web links open externally; unsafe schemes are rejected', () async {
    final opened = <Uri>[];
    final links = AppState(
      client: client,
      openUrl: (uri) async {
        opened.add(uri);
        return true;
      },
    );
    addTearDown(links.dispose);
    await links.navigateToItem(
      GopherItem.fromLine(
        'hWeb\tURL:https://example.org/docs\texample.org\t70',
      ),
    );
    expect(opened.single.toString(), 'https://example.org/docs');
    expect(client.visits, isEmpty);
    expect(links.isLoading, isFalse);
    await links.navigateToItem(
      GopherItem.fromLine('hBad\tURL:javascript:alert(1)\texample.org\t70'),
    );
    expect(opened.length, 1);
    expect(links.error, contains('HTTP and HTTPS'));
  });

  test('a disposed state ignores late completions', () async {
    final delayed = Completer<List<GopherItem>>();
    client.delayed['slow'] = delayed;
    final disposed = AppState(client: client);
    final navigation = disposed.navigate('gopher://example.org/1slow');
    disposed.dispose();
    delayed.complete([]);
    await navigation;
    expect(disposed.currentAddress, isNull);
  });
}
