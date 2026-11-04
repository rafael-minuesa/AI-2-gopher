import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/gopher_item.dart';
import 'gopher_client.dart';
import 'storage_service.dart';
import '../l10n/l10n.dart';

class _Visit {
  final GopherAddress address;
  final String title;

  /// The answer to a local question. Back and Forward show it again rather
  /// than ask the model a second time.
  List<GopherItem>? answer;
  _Visit(this.address, this.title);
}

/// Loads every page through the same typed navigation path.
class AppState extends ChangeNotifier {
  final GopherClient _client;
  final StorageService _storage;
  final Future<bool> Function(Uri) _openUrl;

  AppState({
    GopherClient? client,
    StorageService? storage,
    Future<bool> Function(Uri)? openUrl,
  }) : _client = client ?? GopherClient(),
       _storage = storage ?? StorageService(),
       _openUrl =
           openUrl ??
           ((uri) => launchUrl(uri, mode: LaunchMode.externalApplication));

  GopherAddress? _currentAddress;
  String? _currentTitle;
  List<GopherItem>? _currentMenu;
  List<GopherItem>? _partialMenu;
  String? _currentContent;
  bool _isLoading = false;
  String? _error;
  String? _storageWarning;
  int _selectedTab = 0;
  final List<_Visit> _navigationHistory = [];
  int _navigationIndex = -1;
  List<Bookmark> _bookmarks = [];
  List<HistoryEntry> _history = [];
  GopherRequest? _request;
  int _requestId = 0;
  bool _disposed = false;
  _Visit? _retryVisit;
  int? _retryIndex;

  GopherAddress? get currentAddress => _currentAddress;
  String? get currentTitle => _currentTitle;
  List<GopherItem>? get currentMenu => _currentMenu;

  /// What has arrived so far of the page being loaded.
  List<GopherItem>? get partialMenu => _partialMenu;

  /// Changes with every load, so a page starts at its own scroll position
  /// and keeps it from its first lines to its last.
  int get pageId => _requestId;
  String? get currentContent => _currentContent;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get storageWarning => _storageWarning;
  int get selectedTab => _selectedTab;
  bool get canGoBack => !_isLoading && _navigationIndex > 0;
  bool get canGoForward =>
      !_isLoading && _navigationIndex < _navigationHistory.length - 1;
  bool get canRetry => _retryVisit != null;

  /// An answer being written on this computer is read as it grows. A menu
  /// from a server is read from the top.
  bool get isAskingLocally =>
      _isLoading && (_retryVisit?.address.isLocalQuestion ?? false);

  /// Reloading the answer to a local question would ask the model again.
  bool get canReload =>
      _currentAddress != null &&
      !_isLoading &&
      !_currentAddress!.isLocalQuestion &&
      !_currentAddress!.isLocalChat;

  /// The page being shown or loaded is the chat.
  bool get isChat =>
      (_retryVisit?.address ?? _currentAddress)?.isLocalChat ?? false;

  /// The conversation on the chat page: what has arrived of this answer, or
  /// else the page before it, so nothing blinks away while the model reads.
  List<GopherItem> get chatItems =>
      _partialMenu ??
      ((_currentAddress?.isLocalChat ?? false) ? _currentMenu : null) ??
      const [];
  List<Bookmark> get bookmarks => List.unmodifiable(_bookmarks);
  List<HistoryEntry> get history => List.unmodifiable(_history);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void selectTab(int index) {
    _selectedTab = index;
    _notify();
  }

  Future<void> init() async {
    await _withStorage(() async {
      await _storage.init();
      _bookmarks = await _storage.getBookmarks();
      _history = await _storage.getHistory();
    });
  }

  Future<void> _withStorage(Future<void> Function() action) async {
    try {
      await action();
      _storageWarning = _storage.warning;
    } catch (_) {
      _storageWarning = t.storageUnavailable;
    }
    _notify();
  }

  Future<void> navigate(String url, {String? title}) async {
    try {
      final address = GopherAddress.fromUrl(url);
      await _load(_Visit(address, title ?? address.toUrl()));
    } on ArgumentError catch (e) {
      _invalidAddress(localizedAddressError(e.message.toString()));
    } on FormatException catch (e) {
      _invalidAddress(e.message);
    }
  }

  void _invalidAddress(String message) {
    _requestId++;
    _request?.cancel();
    _isLoading = false;
    _partialMenu = null;
    _retryVisit = null;
    _error = message;
    _selectedTab = 0;
    _notify();
  }

  /// An address from outside the window. Choosing AI-2 Chat while chatting only
  /// brings the window up: it must not end the conversation or its answer. After
  /// a failure it loads again, because that is how the server comes back.
  Future<void> openFromOutside(String url) async {
    GopherAddress? address;
    try {
      address = GopherAddress.fromUrl(url);
    } on ArgumentError {
      address = null;
    } on FormatException {
      address = null;
    }
    if (address != null &&
        address.isLocalChat &&
        address.query == null &&
        isChat &&
        _error == null) {
      selectTab(0);
      return;
    }
    await navigate(url);
  }

  /// The next question of the conversation on the page.
  Future<void> askChat(String question) async {
    final page = _retryVisit?.address ?? _currentAddress;
    if (page == null) return;
    final next = chatItems
        .where((i) => i.isSearchItem && i.address.isLocalChat)
        .fold<GopherItem?>(
          null,
          (best, i) => i.selector != '/chat' ? i : best ?? i,
        );
    final selector = next?.selector ?? page.selector;
    try {
      await _load(
        _Visit(
          GopherAddress(
            host: page.host,
            port: page.port,
            selector: selector,
            type: GopherItemType.search,
            query: question,
          ),
          question,
        ),
      );
    } on ArgumentError catch (e) {
      _invalidAddress(localizedAddressError(e.message.toString()));
    }
  }

  Future<void> _load(_Visit visit, {int? historyIndex}) async {
    if (_disposed) return;
    final id = ++_requestId;
    _request?.cancel();
    final request = GopherRequest();
    _request = request;
    _retryVisit = visit;
    _retryIndex = historyIndex;
    _selectedTab = 0;
    _isLoading = true;
    _partialMenu = null;
    _error = null;
    _notify();
    try {
      final address = visit.address;
      if (address.type == GopherItemType.html &&
          address.selector.startsWith('URL:')) {
        final uri = Uri.parse(address.selector.substring(4));
        if (!['http', 'https'].contains(uri.scheme) || uri.host.isEmpty) {
          throw GopherException(t.onlyWebLinks);
        }
        if (!await _openUrl(uri)) {
          throw GopherException(t.couldNotOpenBrowser);
        }
        if (id != _requestId || _disposed) return;
        _isLoading = false;
        _retryVisit = null;
        _notify();
        return;
      }
      List<GopherItem>? menu;
      String? content;
      switch (address.type) {
        case GopherItemType.directory:
          menu = await _client.fetchMenu(
            address,
            request: request,
            onPartial: (soFar) => _showPartial(id, soFar),
          );
        case GopherItemType.search:
          if (!address.isLocalChat &&
              (address.query == null || address.query!.trim().isEmpty)) {
            throw GopherException(t.chooseSearchItem);
          }
          menu =
              visit.answer ??
              await _client.fetchMenu(
                address,
                request: request,
                onPartial: (soFar) => _showPartial(id, soFar),
              );
          if (address.isLocalQuestion) visit.answer = menu;
        case GopherItemType.file:
        case GopherItemType.html:
          content = await _client.fetchText(address, request: request);
        default:
          throw GopherException(t.itemTypeNotSupported);
      }
      if (id != _requestId || _disposed) return;
      if (historyIndex == null &&
          address.isLocalChat &&
          (_currentAddress?.isLocalChat ?? false) &&
          _navigationIndex >= 0) {
        // Back leaves the chat, rather than step through its questions.
        _navigationHistory[_navigationIndex] = visit;
      } else if (historyIndex == null) {
        if (_navigationIndex < _navigationHistory.length - 1) {
          _navigationHistory.removeRange(
            _navigationIndex + 1,
            _navigationHistory.length,
          );
        }
        _navigationHistory.add(visit);
        _navigationIndex = _navigationHistory.length - 1;
      } else {
        _navigationIndex = historyIndex;
      }
      _currentAddress = address;
      _currentTitle = visit.title;
      _currentMenu = menu;
      _partialMenu = null;
      _currentContent = content;
      _isLoading = false;
      _retryVisit = null;
      _notify();
      // A question to this computer stays out of the saved history, which
      // would ask it again when opened.
      if (address.isLocalQuestion ||
          address.isLocalChat ||
          address.isLocalChatMenu) {
        return;
      }
      // A persistence error must not hide the successfully loaded page.
      await _withStorage(() async {
        await _storage.addToHistory(
          HistoryEntry(url: address.toUrl(), title: visit.title),
        );
        _history = await _storage.getHistory();
      });
    } catch (e) {
      if (id != _requestId || _disposed) return;
      _error = e is GopherException ? e.message : t.couldNotLoadPage('$e');
      // What already arrived stays on screen, above the error.
      _isLoading = false;
      _notify();
    }
  }

  void _showPartial(int id, List<GopherItem> soFar) {
    if (id != _requestId || _disposed) return;
    _partialMenu = soFar;
    _notify();
  }

  /// Stops the page being loaded and goes back to showing the one before it.
  void cancelLoading() {
    if (!_isLoading) return;
    _requestId++;
    _request?.cancel();
    _isLoading = false;
    _partialMenu = null;
    _retryVisit = null;
    _notify();
  }

  Future<void> navigateToItem(GopherItem item) =>
      navigate(item.toUrl(), title: item.displayText);

  Future<void> viewFile(GopherItem item) => navigateToItem(item);

  Future<void> search(GopherItem item, String query) async {
    try {
      await navigate(
        GopherAddress(
          host: item.host,
          port: item.port,
          selector: item.selector,
          type: GopherItemType.search,
          query: query.trim(),
        ).toUrl(),
        title: '${item.displayText}: ${query.trim()}',
      );
    } on ArgumentError catch (e) {
      _invalidAddress(localizedAddressError(e.message.toString()));
    }
  }

  Future<void> goBack() async {
    if (canGoBack) {
      final index = _navigationIndex - 1;
      await _load(_navigationHistory[index], historyIndex: index);
    }
  }

  Future<void> goForward() async {
    if (canGoForward) {
      final index = _navigationIndex + 1;
      await _load(_navigationHistory[index], historyIndex: index);
    }
  }

  Future<void> reload() async {
    if (_navigationIndex >= 0 && canReload) {
      await _load(
        _navigationHistory[_navigationIndex],
        historyIndex: _navigationIndex,
      );
    }
  }

  Future<void> retry() async {
    final visit = _retryVisit;
    if (visit != null && !_isLoading) {
      await _load(visit, historyIndex: _retryIndex);
    }
  }

  Future<void> loadBookmarks() => _withStorage(() async {
    _bookmarks = await _storage.getBookmarks();
  });

  Future<bool> addBookmark(String title, String url) async {
    var saved = false;
    await _withStorage(() async {
      await _storage.addBookmark(Bookmark(title: title, url: url));
      _bookmarks = await _storage.getBookmarks();
      saved = true;
    });
    return saved;
  }

  Future<bool> removeBookmark(String url) async {
    var saved = false;
    await _withStorage(() async {
      await _storage.removeBookmark(url);
      _bookmarks = await _storage.getBookmarks();
      saved = true;
    });
    return saved;
  }

  Future<bool> isBookmarked(String url) async =>
      _bookmarks.any((b) => b.url == url);

  Future<void> loadHistory() => _withStorage(() async {
    _history = await _storage.getHistory();
  });

  Future<bool> clearHistory() async {
    var cleared = false;
    await _withStorage(() async {
      await _storage.clearHistory();
      _history = [];
      cleared = true;
    });
    return cleared;
  }

  void clearError() {
    _error = null;
    _partialMenu = null;
    _retryVisit = null;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _requestId++;
    _request?.cancel();
    super.dispose();
  }
}
