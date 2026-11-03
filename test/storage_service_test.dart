import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_2_gopher/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'damaged JSON is preserved and does not prevent reading other data',
    () async {
      SharedPreferences.setMockInitialValues({
        'bookmarks': '{broken json',
        'history': '[]',
      });
      final storage = StorageService();
      expect(await storage.getBookmarks(), isEmpty);
      expect(await storage.getHistory(), isEmpty);
      expect(storage.warning, isNotNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('bookmarks.recovery'), '{broken json');
      await storage.addBookmark(
        Bookmark(title: 'New', url: 'gopher://example.org:70/1'),
      );
      expect((await storage.getBookmarks()).single.title, 'New');
      expect(prefs.getString('bookmarks.recovery'), '{broken json');
    },
  );

  test('valid entries survive a damaged entry', () async {
    final raw = jsonEncode([
      Bookmark(title: 'Kept', url: 'gopher://example.org:70/0readme').toJson(),
      {'title': 'Broken', 'url': 'bad', 'created': 'not a date'},
    ]);
    SharedPreferences.setMockInitialValues({'bookmarks': raw});
    final storage = StorageService();
    expect((await storage.getBookmarks()).single.title, 'Kept');
    expect(
      (await SharedPreferences.getInstance()).getString('bookmarks.recovery'),
      raw,
    );
  });

  test(
    'overlapping writes preserve all entries and avoid duplicates',
    () async {
      SharedPreferences.setMockInitialValues({});
      final storage = StorageService();
      await Future.wait(
        List.generate(
          20,
          (i) => storage.addBookmark(
            Bookmark(title: '$i', url: 'gopher://example.org:70/0$i'),
          ),
        ),
      );
      expect((await storage.getBookmarks()).length, 20);
      await storage.addBookmark(
        Bookmark(title: 'Duplicate', url: 'gopher://example.org:70/00'),
      );
      expect((await storage.getBookmarks()).length, 20);
    },
  );

  test('history remains bounded and most recent visits come first', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService();
    await Future.wait(
      List.generate(
        110,
        (i) => storage.addToHistory(
          HistoryEntry(title: '$i', url: 'gopher://example.org:70/0$i'),
        ),
      ),
    );
    final history = await storage.getHistory();
    expect(history.length, 100);
    expect(history.first.title, '109');
    await storage.clearHistory();
    expect(await storage.getHistory(), isEmpty);
  });
}
