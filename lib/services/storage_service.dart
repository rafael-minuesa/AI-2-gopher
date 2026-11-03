import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/l10n.dart';

/// Bookmark data model
class Bookmark {
  final String title;
  final String url;
  final DateTime created;

  Bookmark({required this.title, required this.url, DateTime? created})
    : created = created ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'title': title,
    'url': url,
    'created': created.toIso8601String(),
  };

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
    title: json['title'] as String,
    url: json['url'] as String,
    created: DateTime.parse(json['created'] as String),
  );
}

/// History entry data model
class HistoryEntry {
  final String url;
  final String title;
  final DateTime timestamp;

  HistoryEntry({required this.url, required this.title, DateTime? timestamp})
    : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'url': url,
    'title': title,
    'timestamp': timestamp.toIso8601String(),
  };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
    url: json['url'] as String,
    title: json['title'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
  );
}

/// Service for managing bookmarks and history
class StorageService {
  static const String _bookmarksKey = 'bookmarks';
  static const String _historyKey = 'history';
  static const int _maxHistoryItems = 100;

  SharedPreferences? _prefs;
  Future<void>? _initialization;
  Future<void> _writes = Future.value();
  String? warning;

  Future<void> init() async {
    if (_prefs != null) return;
    final initialization = _initialization ??= (() async {
      _prefs = await SharedPreferences.getInstance();
    })();
    try {
      await initialization;
    } finally {
      _initialization = null;
    }
  }

  Future<T> _mutate<T>(Future<T> Function() action) {
    final result = _writes.then((_) => action());
    _writes = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Future<List<T>> _readEntries<T>(
    String key,
    T Function(Map<String, dynamic>) decode,
  ) async {
    await _ensureInitialized();
    final raw = _prefs!.getString(key);
    if (raw == null) return [];
    final entries = <T>[];
    var damaged = false;
    try {
      final data = json.decode(raw);
      if (data is! List) throw const FormatException('Expected a list');
      for (final entry in data) {
        try {
          entries.add(decode(Map<String, dynamic>.from(entry as Map)));
        } catch (_) {
          damaged = true;
        }
      }
    } catch (_) {
      damaged = true;
    }
    if (damaged) {
      // Preserve the original before a later user action rewrites the list.
      final backup = '$key.recovery';
      if (!_prefs!.containsKey(backup) &&
          !await _prefs!.setString(backup, raw)) {
        throw StateError('Could not preserve damaged saved data');
      }
      warning = t.someEntriesUnreadable;
    }
    return entries;
  }

  // Bookmarks management

  Future<List<Bookmark>> getBookmarks() async {
    return _readEntries(_bookmarksKey, Bookmark.fromJson);
  }

  Future<void> addBookmark(Bookmark bookmark) => _mutate(() async {
    final bookmarks = await getBookmarks();

    // Avoid duplicates
    if (bookmarks.any((b) => b.url == bookmark.url)) {
      return;
    }

    bookmarks.add(bookmark);
    await _saveBookmarks(bookmarks);
  });

  Future<void> removeBookmark(String url) => _mutate(() async {
    final bookmarks = await getBookmarks();
    bookmarks.removeWhere((b) => b.url == url);
    await _saveBookmarks(bookmarks);
  });

  Future<bool> isBookmarked(String url) async {
    final bookmarks = await getBookmarks();
    return bookmarks.any((b) => b.url == url);
  }

  Future<void> _saveBookmarks(List<Bookmark> bookmarks) async {
    await _ensureInitialized();
    final jsonString = json.encode(bookmarks.map((b) => b.toJson()).toList());
    if (!await _prefs!.setString(_bookmarksKey, jsonString)) {
      throw StateError('Could not save bookmarks');
    }
  }

  // History management

  Future<List<HistoryEntry>> getHistory() async {
    return _readEntries(_historyKey, HistoryEntry.fromJson);
  }

  Future<void> addToHistory(HistoryEntry entry) => _mutate(() async {
    final history = await getHistory();

    // Remove existing entry with same URL to avoid duplicates
    history.removeWhere((h) => h.url == entry.url);

    // Add new entry at the beginning
    history.insert(0, entry);

    // Limit history size
    if (history.length > _maxHistoryItems) {
      history.removeRange(_maxHistoryItems, history.length);
    }

    await _saveHistory(history);
  });

  Future<void> clearHistory() => _mutate(() async {
    await _ensureInitialized();
    if (!await _prefs!.remove(_historyKey)) {
      throw StateError('Could not clear history');
    }
  });

  Future<void> _saveHistory(List<HistoryEntry> history) async {
    await _ensureInitialized();
    final jsonString = json.encode(history.map((h) => h.toJson()).toList());
    if (!await _prefs!.setString(_historyKey, jsonString)) {
      throw StateError('Could not save history');
    }
  }

  Future<void> _ensureInitialized() async {
    if (_prefs == null) {
      await init();
    }
  }
}
