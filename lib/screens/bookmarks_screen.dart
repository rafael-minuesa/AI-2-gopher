import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../services/storage_service.dart';
import '../l10n/l10n.dart';

class BookmarksScreen extends StatelessWidget {
  const BookmarksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, child) {
        if (state.bookmarks.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.bookmark_border,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  t.noBookmarks,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(t.bookmarkFavorites, textAlign: TextAlign.center),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: state.bookmarks.length,
          itemBuilder: (context, index) {
            final bookmark = state.bookmarks[index];
            return _BookmarkItem(bookmark: bookmark);
          },
        );
      },
    );
  }
}

class _BookmarkItem extends StatelessWidget {
  final Bookmark bookmark;

  const _BookmarkItem({required this.bookmark});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.bookmark),
      title: Text(bookmark.title),
      subtitle: Text(
        bookmark.url,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete),
        onPressed: () => _confirmDelete(context),
      ),
      onTap: () {
        context.read<AppState>().navigate(bookmark.url, title: bookmark.title);
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.deleteBookmark),
        content: Text(t.removeFromBookmarks(bookmark.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.delete),
          ),
        ],
      ),
    );

    if (result == true && context.mounted) {
      final removed = await context.read<AppState>().removeBookmark(
        bookmark.url,
      );
      if (removed && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t.bookmarkRemoved)));
      }
    }
  }
}
